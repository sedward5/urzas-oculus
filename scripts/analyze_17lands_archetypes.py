#!/usr/bin/env python3
"""Deck-level color-pair performance audit of a 17Lands public game archive."""
from __future__ import annotations

import argparse
import csv
import gzip
import json
import random
import re
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

BASE = "https://17lands-public.s3.amazonaws.com/analysis_data"
COLOR_ORDER = "WUBRG"
BOOTSTRAP_RESAMPLES = 2000
BOOTSTRAP_SEED = 17021


def archive_url(set_code: str, event_type: str) -> str:
    return f"{BASE}/game_data/game_data_public.{set_code}.{event_type}.csv.gz"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Urzas-Oculus-ArchetypeAudit/1.0"})
    with urllib.request.urlopen(request, timeout=180) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def parse_bool(value: str | None) -> bool | None:
    value = (value or "").strip().lower()
    if value in {"1", "true", "t", "yes"}:
        return True
    if value in {"0", "false", "f", "no"}:
        return False
    return None


def canonical_colors(value: str | None) -> str | None:
    raw = (value or "").strip().upper()
    if not raw or any(char not in COLOR_ORDER for char in raw):
        return None
    colors = set(raw)
    if len(colors) != len(raw):
        return None
    return "".join(color for color in COLOR_ORDER if color in colors)


def bootstrap_interval(values: list[float], *, seed: int = BOOTSTRAP_SEED) -> tuple[float, float] | None:
    """Percentile interval for the mean of independent deck-level win rates."""
    if len(values) < 2:
        return None
    rng = random.Random(seed)
    size = len(values)
    means = []
    for _ in range(BOOTSTRAP_RESAMPLES):
        means.append(sum(values[rng.randrange(size)] for _ in range(size)) / size)
    means.sort()
    return means[int(0.025 * (BOOTSTRAP_RESAMPLES - 1))], means[int(0.975 * (BOOTSTRAP_RESAMPLES - 1))]


def summarize_decks(decks: dict[tuple[str, str], dict]) -> dict:
    rates = [deck["wins"] / deck["games"] for deck in decks.values()]
    games = sum(deck["games"] for deck in decks.values())
    wins = sum(deck["wins"] for deck in decks.values())
    interval = bootstrap_interval(rates)
    return {
        "decks": len(decks),
        "games": games,
        "game_wins": wins,
        "game_weighted_win_rate": wins / games if games else None,
        "mean_deck_win_rate": sum(rates) / len(rates) if rates else None,
        "mean_deck_win_rate_ci_95": list(interval) if interval else None,
    }


def analyze_archive(path: Path) -> dict:
    required = ("draft_id", "build_index", "main_colors", "won")
    source_rows = invalid_results = missing_identity = missing_colors = invalid_colors = 0
    decks: dict[tuple[str, str], dict] = {}
    identity_colors: dict[tuple[str, str], str] = {}
    conflicting_decks: set[tuple[str, str]] = set()
    non_pair_decks: set[tuple[str, str]] = set()
    color_values: Counter[str] = Counter()

    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = reader.fieldnames or []
        if len(fields) != len(set(fields)):
            raise ValueError("game archive has duplicate headers")
        missing_fields = [name for name in required if name not in fields]
        if missing_fields:
            raise ValueError(f"game archive missing required fields: {missing_fields}")

        for source_rows, row in enumerate(reader, 1):
            draft_id = (row.get("draft_id") or "").strip()
            build_index = (row.get("build_index") or "").strip()
            if not draft_id or not build_index:
                missing_identity += 1
                continue
            key = (draft_id, build_index)
            colors_raw = (row.get("main_colors") or "").strip()
            colors = canonical_colors(colors_raw)
            if not colors_raw:
                missing_colors += 1
                continue
            if colors is None:
                invalid_colors += 1
                continue
            won = parse_bool(row.get("won"))
            if won is None:
                invalid_results += 1
                continue
            if key in identity_colors and identity_colors[key] != colors:
                conflicting_decks.add(key)
            identity_colors[key] = colors
            deck = decks.setdefault(key, {"colors": colors, "games": 0, "wins": 0})
            deck["games"] += 1
            deck["wins"] += int(won)

    for key, deck in decks.items():
        if len(deck["colors"]) != 2:
            non_pair_decks.add(key)
        else:
            color_values[deck["colors"]] += 1

    valid_decks = {key: value for key, value in decks.items() if key not in conflicting_decks}
    pair_decks: dict[str, dict[tuple[str, str], dict]] = {}
    for key, deck in valid_decks.items():
        if len(deck["colors"]) == 2:
            pair_decks.setdefault(deck["colors"], {})[key] = deck

    baseline = summarize_decks(valid_decks)
    by_color_pair = {}
    for pair, members in sorted(pair_decks.items()):
        summary = summarize_decks(members)
        rate = summary["mean_deck_win_rate"]
        baseline_rate = baseline["mean_deck_win_rate"]
        summary["delta_vs_all_decks_percentage_points"] = (
            (rate - baseline_rate) * 100 if rate is not None and baseline_rate is not None else None
        )
        by_color_pair[pair] = summary

    return {
        "source_rows": source_rows,
        "missing_identity_rows": missing_identity,
        "missing_main_colors_rows": missing_colors,
        "invalid_main_colors_rows": invalid_colors,
        "missing_or_invalid_result_rows": invalid_results,
        "conflicting_deck_identity_count": len(conflicting_decks),
        "excluded_conflicting_deck_game_rows": sum(decks[key]["games"] for key in conflicting_decks),
        "non_two_color_decks": len(non_pair_decks),
        "valid_deck_count": len(valid_decks),
        "overall_deck_baseline": baseline,
        "by_color_pair": by_color_pair,
    }


def pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.1%}"


def render_report(set_code: str, event_type: str, result: dict) -> str:
    baseline = result["overall_deck_baseline"]
    lines = [
        f"# 17Lands archetype performance audit — {set_code} {event_type}", "",
        "Exploratory two-color deck performance using the public game archive. Color pairs are proxies, not refined archetype labels.", "",
        "## Coverage", "",
        f"- Source game rows: {result['source_rows']:,}",
        f"- Valid deck identities: {result['valid_deck_count']:,}",
        f"- Rows missing deck identity: {result['missing_identity_rows']:,}",
        f"- Rows missing main colors: {result['missing_main_colors_rows']:,}",
        f"- Rows with invalid main colors: {result['invalid_main_colors_rows']:,}",
        f"- Rows with missing/invalid results: {result['missing_or_invalid_result_rows']:,}",
        f"- Deck identities with conflicting color assignments (excluded): {result['conflicting_deck_identity_count']:,}",
        f"- Games excluded with conflicting deck identities: {result['excluded_conflicting_deck_game_rows']:,}",
        f"- Valid non-two-color decks (not in pair table): {result['non_two_color_decks']:,}", "",
        "## Format baseline", "",
        f"- Decks: {baseline['decks']:,}; games: {baseline['games']:,}",
        f"- Mean deck win rate: {pct(baseline['mean_deck_win_rate'])}",
        f"- 95% deck-bootstrap interval: {interval_text(baseline['mean_deck_win_rate_ci_95'])}",
        f"- Game-weighted win rate (context only): {pct(baseline['game_weighted_win_rate'])}", "",
        "## Two-color results", "",
        "Sorted by observed mean deck win rate for readability; this is not a strength ranking.", "",
        "| Colors | Decks | Games | Mean deck win rate | 95% interval | vs. all-deck baseline |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for pair, part in sorted(result["by_color_pair"].items(),
                             key=lambda item: (item[1]["mean_deck_win_rate"] or 0), reverse=True):
        lines.append(
            f"| {pair} | {part['decks']:,} | {part['games']:,} | "
            f"{pct(part['mean_deck_win_rate'])} | {interval_text(part['mean_deck_win_rate_ci_95'])} | "
            f"{part['delta_vs_all_decks_percentage_points']:+.1f} pp |"
        )
    lines += [
        "", "## Method and limitations", "",
        "- A deck is identified by the pair (draft_id, build_index); each deck contributes one win-rate observation regardless of how many games it played.",
        "- The reported archetype estimate is the unweighted mean of each deck's game win rate. The game-weighted rate is shown only as context.",
        "- The 95% interval is a deterministic percentile bootstrap over deck-level win rates, not individual games.",
        "- The baseline includes all valid-color decks, including mono-color and three-or-more-color decks. Only exactly two-color decks appear in the pair table.",
        "- main_colors is used as the deck's primary color identity. Splash colors are not folded into the pair label.",
        "- Color pairs are broad buckets. They do not distinguish different strategies within a pair, and a pair can contain multiple archetypes.",
        "- The delta is descriptive against the all-deck baseline. It is not causal and is not adjusted for player skill, rank, date, or event subgroup.",
        "- Do not use these results to modify live recommendations until sample coverage, cohort comparability, and archetype semantics have been reviewed.",
        "",
    ]
    return "\n".join(lines)


def interval_text(value: list[float] | None) -> str:
    if not value:
        return "n/a"
    return f"{pct(value[0])}–{pct(value[1])}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-code", default="HOB")
    parser.add_argument("--event-type", default="PremierDraft")
    parser.add_argument("--output-dir", default="archetype-output")
    args = parser.parse_args()
    set_code, event_type = args.set_code.strip().upper(), args.event_type.strip()
    if not re.fullmatch(r"[A-Z0-9]+", set_code):
        parser.error("set code must contain only letters and numbers")
    if not re.fullmatch(r"[A-Za-z0-9]+", event_type):
        parser.error("event type must contain only letters and numbers")
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    try:
        with TemporaryDirectory(prefix="urzas-oculus-archetype-") as temp:
            archive = Path(temp) / "game.csv.gz"
            download(archive_url(set_code, event_type), archive)
            result = analyze_archive(archive)
        report = render_report(set_code, event_type, result)
        (output / "archetype-report.md").write_text(report, encoding="utf-8")
        payload = {
            "schema_version": 1,
            "analysis": "17lands-archetype-performance",
            "set_code": set_code,
            "event_type": event_type,
            "source_url": archive_url(set_code, event_type),
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            **result,
        }
        (output / "archetype-summary.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(report)
        return 0
    except Exception as exc:
        message = f"Archetype audit failed: {type(exc).__name__}: {exc}"
        (output / "archetype-error.txt").write_text(message + "\n", encoding="utf-8")
        print(message)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
