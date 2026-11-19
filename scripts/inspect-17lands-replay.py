#!/usr/bin/env python3
"""Inspect 17Lands replay coverage and schema against the game archive.

This is a research probe only. It does not classify games as valid or invalid.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import re
import urllib.request
from pathlib import Path
from tempfile import TemporaryDirectory

BASE = "https://17lands-public.s3.amazonaws.com/analysis_data"
KEY_FIELDS = ("draft_id", "build_index", "match_number", "game_number")
USER_AGENT = "UrzasOculus-ReplayAudit/1.0"


def archive_url(kind: str, set_code: str, event_type: str) -> str:
    return f"{BASE}/{kind}_data/{kind}_data_public.{set_code}.{event_type}.csv.gz"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=180) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def scan_archive(path: Path, label: str) -> dict:
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        try:
            header = next(reader)
        except StopIteration as exc:
            raise ValueError(f"{label} archive is empty") from exc
        if len(header) != len(set(header)):
            raise ValueError(f"{label} archive has duplicate headers")
        missing = [field for field in KEY_FIELDS if field not in header]
        if missing:
            raise ValueError(f"{label} archive is missing game identity fields: {missing}")

        indexes = [header.index(field) for field in KEY_FIELDS]
        keys = set()
        duplicate_rows = 0
        missing_identity_rows = 0
        row_count = 0
        for row_count, row in enumerate(reader, 1):
            if len(row) != len(header):
                raise ValueError(f"{label} row {row_count + 1}: width mismatch")
            key = tuple(row[index].strip() for index in indexes)
            if not all(key):
                missing_identity_rows += 1
                continue
            if key in keys:
                duplicate_rows += 1
            keys.add(key)

    prefixes = {}
    for prefix in ("deck_", "sideboard_", "candidate_hand_", "user_turn_", "oppo_turn_"):
        matches = [name for name in header if name.startswith(prefix)]
        prefixes[prefix] = {
            "count": len(matches),
            "examples": matches[:8],
        }

    return {
        "rows": row_count,
        "unique_game_keys": len(keys),
        "duplicate_key_rows": duplicate_rows,
        "missing_identity_rows": missing_identity_rows,
        "column_count": len(header),
        "key_fields": list(KEY_FIELDS),
        "prefixes": prefixes,
        "keys": keys,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-code", default="HOB")
    parser.add_argument("--event-type", default="PremierDraft")
    parser.add_argument("--output-dir", default="replay-audit-output")
    args = parser.parse_args()

    set_code = args.set_code.strip().upper()
    event_type = args.event_type.strip()
    if not re.fullmatch(r"[A-Z0-9]+", set_code):
        parser.error("set code must contain only letters and numbers")
    if not re.fullmatch(r"[A-Za-z0-9]+", event_type):
        parser.error("event type must contain only letters and numbers")

    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    game_url = archive_url("game", set_code, event_type)
    replay_url = archive_url("replay", set_code, event_type)

    try:
        with TemporaryDirectory(prefix="urzas-oculus-replay-") as temp:
            temp_dir = Path(temp)
            game_path = temp_dir / "game.csv.gz"
            replay_path = temp_dir / "replay.csv.gz"
            print(f"Downloading game archive: {game_url}", flush=True)
            download(game_url, game_path)
            print(f"Downloading replay archive: {replay_url}", flush=True)
            download(replay_url, replay_path)

            print("Scanning game archive...", flush=True)
            game = scan_archive(game_path, "game")
            print("Scanning replay archive...", flush=True)
            replay = scan_archive(replay_path, "replay")

        overlap = game["keys"] & replay["keys"]
        game_only = game["keys"] - replay["keys"]
        replay_only = replay["keys"] - game["keys"]

        lines = [
            f"# 17Lands replay schema audit — {set_code} {event_type}",
            "",
            "This is a schema and coverage probe only. It does not infer or apply a game-validity rule.",
            "",
            f"- Game archive: {game_url}",
            f"- Replay archive: {replay_url}",
            f"- Game rows: {game['rows']:,}",
            f"- Replay rows: {replay['rows']:,}",
            f"- Game unique keys: {game['unique_game_keys']:,}",
            f"- Replay unique keys: {replay['unique_game_keys']:,}",
            f"- Matching game keys: {len(overlap):,}",
            f"- Game-only keys: {len(game_only):,}",
            f"- Replay-only keys: {len(replay_only):,}",
            "",
            "## Identity and duplicate diagnostics",
            "",
        ]
        for label, result in (("Game", game), ("Replay", replay)):
            lines += [
                f"### {label}",
                f"- Duplicate-key rows: {result['duplicate_key_rows']:,}",
                f"- Rows with missing identity: {result['missing_identity_rows']:,}",
                f"- Columns: {result['column_count']:,}",
                "",
            ]

        lines += ["## Replay column families", ""]
        for prefix, detail in replay["prefixes"].items():
            examples = ", ".join(f"`{name}`" for name in detail["examples"]) or "none"
            lines.append(f"- `{prefix}`: {detail['count']:,} columns; examples: {examples}")
        lines += [
            "",
            "## Interpretation boundary",
            "",
            "A shared game key establishes that the replay row can be associated with a game-data row. "
            "It does not establish that either row passed 17Lands' internal consistency checks.",
            "Replay coverage may be a subset of all game rows. Any deck comparison must account for "
            "that selection boundary and must not treat missing replay as an invalid game.",
            "",
        ]
        (output / "replay-audit-report.md").write_text("\n".join(lines), encoding="utf-8")
        print("\n".join(lines))
        return 0
    except Exception as exc:
        message = f"Replay audit failed: {type(exc).__name__}: {exc}"
        (output / "replay-audit-error.txt").write_text(message + "\n", encoding="utf-8")
        print(message)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
