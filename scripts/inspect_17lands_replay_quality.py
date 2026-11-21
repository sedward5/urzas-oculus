#!/usr/bin/env python3
"""Compare 17Lands game and replay deck observations.

Evidence-gathering audit only; it does not classify games as valid or invalid.
SQLite keeps the join bounded in memory for full public archives.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import sqlite3
import urllib.request
from collections import Counter
from pathlib import Path
from tempfile import TemporaryDirectory

BASE = "https://17lands-public.s3.amazonaws.com/analysis_data"
KEY_FIELDS = ("draft_id", "build_index", "match_number", "game_number")
USER_AGENT = "Urzas-Oculus-ReplayQualityAudit/1.0"


def archive_url(kind: str, set_code: str, event_type: str) -> str:
    return f"{BASE}/{kind}_data/{kind}_data_public.{set_code}.{event_type}.csv.gz"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=180) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def count_value(value: str, column: str, row_number: int) -> int:
    value = value.strip()
    if not value:
        return 0
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ValueError(f"row {row_number}, {column}: expected integer, got {value!r}") from exc
    if parsed < 0:
        raise ValueError(f"row {row_number}, {column}: negative count {parsed}")
    return parsed


def read_archive(path: Path, label: str, table: str, connection: sqlite3.Connection) -> dict:
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        header = reader.fieldnames or []
        if len(header) != len(set(header)):
            raise ValueError(f"{label} archive has duplicate headers")
        missing = [field for field in KEY_FIELDS if field not in header]
        if missing:
            raise ValueError(f"{label} archive missing identity fields: {missing}")

        facets = {
            facet: [name for name in header if name.startswith(facet)]
            for facet in ("deck_", "sideboard_", "opening_hand_")
        }
        if not facets["deck_"]:
            raise ValueError(f"{label} archive missing deck_ columns")
        if label == "game" and not facets["opening_hand_"]:
            raise ValueError("game archive missing opening_hand_ columns")

        connection.execute(
            f"CREATE TABLE {table} (draft_id TEXT, build_index TEXT, match_number TEXT, "
            "game_number TEXT, deck_json TEXT, sideboard_json TEXT, opening_json TEXT, "
            "PRIMARY KEY (draft_id, build_index, match_number, game_number))"
        )
        rows = missing_keys = duplicate_keys = candidate_cells = 0
        candidate_examples = []
        insert_sql = f"INSERT OR IGNORE INTO {table} VALUES (?, ?, ?, ?, ?, ?, ?)"

        for rows, row in enumerate(reader, 1):
            key = tuple((row.get(field) or "").strip() for field in KEY_FIELDS)
            if not all(key):
                missing_keys += 1
                continue

            def collect(columns: list[str]) -> dict[str, int]:
                result = {}
                for column in columns:
                    value = count_value(row.get(column, ""), column, rows + 1)
                    if value:
                        result[column.split("_", 1)[1]] = value
                return result

            deck = collect(facets["deck_"])
            sideboard = collect(facets["sideboard_"])
            opening = collect(facets["opening_hand_"])
            cursor = connection.execute(
                insert_sql,
                (*key, json.dumps(deck, sort_keys=True), json.dumps(sideboard, sort_keys=True),
                 json.dumps(opening, sort_keys=True)),
            )
            if cursor.rowcount == 0:
                duplicate_keys += 1

            if label == "replay":
                for field in header:
                    value = (row.get(field) or "").strip()
                    if field.startswith("candidate_hand_") and value:
                        candidate_cells += 1
                        if len(candidate_examples) < 5:
                            candidate_examples.append((field, value[:160]))
            if rows % 50000 == 0:
                connection.commit()

    connection.commit()
    unique = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    return {
        "rows": rows,
        "unique_keys": unique,
        "duplicate_rows": duplicate_keys,
        "missing_identity_rows": missing_keys,
        "columns": len(header),
        "facet_columns": {key: len(value) for key, value in facets.items()},
        "candidate_nonempty_cells": candidate_cells,
        "candidate_examples": candidate_examples,
    }


def compare(connection: sqlite3.Connection, example_limit: int = 12) -> dict:
    cursor = connection.execute(
        """SELECT g.draft_id, g.build_index, g.match_number, g.game_number,
                  g.deck_json, g.sideboard_json, g.opening_json,
                  r.deck_json, r.sideboard_json
           FROM game g JOIN replay r USING
             (draft_id, build_index, match_number, game_number)"""
    )
    totals = Counter()
    examples = []
    card_mismatches = Counter()
    for row in cursor:
        totals["matched_games"] += 1
        key = row[:4]
        game_deck, game_side, game_open, replay_deck, replay_side = (
            json.loads(value) for value in row[4:]
        )
        for label, left, right in (
            ("main_deck", game_deck, replay_deck),
            ("sideboard", game_side, replay_side),
        ):
            if left != right:
                totals[f"{label}_mismatch_games"] += 1
                for name in sorted(set(left) | set(right)):
                    if left.get(name, 0) != right.get(name, 0):
                        card_mismatches[f"{label}:{name}"] += 1
                        if len(examples) < example_limit:
                            examples.append({
                                "key": key, "check": label, "card": name,
                                "game_count": left.get(name, 0),
                                "replay_count": right.get(name, 0),
                            })
        overages = {
            name: count - game_deck.get(name, 0)
            for name, count in game_open.items()
            if count > game_deck.get(name, 0)
        }
        if overages:
            totals["opening_hand_exceeds_deck_games"] += 1
            for name, excess in overages.items():
                if len(examples) < example_limit:
                    examples.append({
                        "key": key, "check": "opening_hand_exceeds_main_deck",
                        "card": name, "opening_hand_count": game_open[name],
                        "game_deck_count": game_deck.get(name, 0), "excess": excess,
                    })

    game_count = connection.execute("SELECT COUNT(*) FROM game").fetchone()[0]
    replay_count = connection.execute("SELECT COUNT(*) FROM replay").fetchone()[0]
    totals["game_only_keys"] = connection.execute(
        """SELECT COUNT(*) FROM game g LEFT JOIN replay r USING
           (draft_id, build_index, match_number, game_number)
           WHERE r.draft_id IS NULL"""
    ).fetchone()[0]
    totals["replay_only_keys"] = connection.execute(
        """SELECT COUNT(*) FROM replay r LEFT JOIN game g USING
           (draft_id, build_index, match_number, game_number)
           WHERE g.draft_id IS NULL"""
    ).fetchone()[0]
    return {
        "game_unique_keys": game_count,
        "replay_unique_keys": replay_count,
        "comparisons": dict(totals),
        "card_mismatch_counts": card_mismatches.most_common(20),
        "examples": examples,
    }


def render_report(set_code: str, event_type: str, game: dict, replay: dict, result: dict) -> str:
    checks = result["comparisons"]
    lines = [
        f"# 17Lands replay-backed data quality audit — {set_code} {event_type}",
        "",
        "This report compares archive observations. It does not classify games as valid or invalid.",
        "",
        f"- Game rows / unique keys: {game['rows']:,} / {game['unique_keys']:,}",
        f"- Replay rows / unique keys: {replay['rows']:,} / {replay['unique_keys']:,}",
        f"- Matched games: {checks.get('matched_games', 0):,}",
        f"- Game-only keys: {checks.get('game_only_keys', 0):,}",
        f"- Replay-only keys: {checks.get('replay_only_keys', 0):,}",
        "",
        "## Consistency checks",
        "",
        "| Check | Games |",
        "|---|---:|",
        f"| Main-deck count mismatches | {checks.get('main_deck_mismatch_games', 0):,} |",
        f"| Sideboard count mismatches | {checks.get('sideboard_mismatch_games', 0):,} |",
        f"| Opening-hand counts exceed main-deck counts | {checks.get('opening_hand_exceeds_deck_games', 0):,} |",
        "",
        "## Candidate-hand fields",
        "",
        f"- Nonempty candidate-hand cells: {replay['candidate_nonempty_cells']:,}",
        "- Candidate-hand values are shown as opaque examples only; this audit does not assume their meaning.",
        "",
        "## Representative discrepancies",
        "",
    ]
    if result["examples"]:
        lines.extend(f"- {json.dumps(item, sort_keys=True)}" for item in result["examples"])
    else:
        lines.append("No discrepancies were found in the checks above.")
    lines += [
        "",
        "## Interpretation limits",
        "",
        "- Matching keys allow row association; they do not prove 17Lands' internal eligibility decision.",
        "- Deck and sideboard equality is evidence of consistency between exports, not proof of upstream validation.",
        "- An opening-hand overage is a discrepancy signal, but must be checked against field definitions and game mechanics.",
        "- Missing replay rows are not classified as invalid games.",
        "- Drawn/tutored totals are not compared with deck size because game effects can alter repeated observations.",
        "- Candidate-hand fields are not interpreted until their schema is documented.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-code", default="HOB")
    parser.add_argument("--event-type", default="PremierDraft")
    parser.add_argument("--output-dir", default="replay-quality-output")
    args = parser.parse_args()
    set_code = args.set_code.strip().upper()
    event_type = args.event_type.strip()
    if not re.fullmatch(r"[A-Z0-9]+", set_code):
        parser.error("set code must contain only letters and numbers")
    if not re.fullmatch(r"[A-Za-z0-9]+", event_type):
        parser.error("event type must contain only letters and numbers")

    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    try:
        with TemporaryDirectory(prefix="urzas-oculus-replay-quality-") as temp:
            temp_dir = Path(temp)
            game_path, replay_path = temp_dir / "game.csv.gz", temp_dir / "replay.csv.gz"
            download(archive_url("game", set_code, event_type), game_path)
            download(archive_url("replay", set_code, event_type), replay_path)
            connection = sqlite3.connect(temp_dir / "audit.sqlite")
            try:
                game = read_archive(game_path, "game", "game", connection)
                replay = read_archive(replay_path, "replay", "replay", connection)
                result = compare(connection)
            finally:
                connection.close()
        report = render_report(set_code, event_type, game, replay, result)
        (output / "replay-quality-report.md").write_text(report, encoding="utf-8")
        print(report)
        return 0
    except Exception as exc:
        message = f"Replay quality audit failed: {type(exc).__name__}: {exc}"
        (output / "replay-quality-error.txt").write_text(message + "\n", encoding="utf-8")
        print(message)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
