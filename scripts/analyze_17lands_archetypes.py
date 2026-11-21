#!/usr/bin/env python3
"""Deck-clustered, game-weighted color-pair performance audit of 17Lands data."""
from __future__ import annotations

import argparse
import csv
import gzip
import json
import random
import re
import urllib.request
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


def pooled_win_rate(decks: list[dict]) -> float | None:
    games = sum(deck["games"] for deck in decks)
    return sum(deck["wins"] for deck in decks) / games if games else None


def bootstrap_win_rate_interval(
    decks: list[dict], *, seed: int = BOOTSTRAP_SEED
) -> tuple[float, float] | None:
    """Percentile interval for pooled game win rate, resampling whole decks."""
    if len(decks) < 2:
        return None
    rng = random.Random(seed)
    sample_size = len(decks)
    estimates = []
    for _ in range(BOOTSTRAP_RESAMPLES):
        sample = [decks[rng.randrange(sample_size)] for _ in range(sample_size)]
        rate = pooled_win_rate(sample)
        if rate is not None:
            estimates.append(rate)
    estimates.sort()
    low = estimates[int(0.025 * (len(estimates) - 1))]
    high = estimates[int(0.975 * (len(estimates) - 1))]
    return low, high


def bootstrap_delta_interval(
    group: list[dict], comparison: list[dict], *, seed: int
) -> tuple[float, float] | None:
    """95% interval for game-win-rate difference, resampling whole decks by group."""
    if len(group) < 2 or len(comparison) < 2:
        return None
    rng = random.Random(seed)
    group_size = len(group)
    comparison_size = len(comparison)
    deltas = []
    for _ in range(BOOTSTRAP_RESAMPLES):
        group_sample = [group[rng.randrange(group_size)] for _ in range(group_size)]
        comparison_sample = [
            comparison[rng.randrange(comparison_size)] for _ in range(comparison_size)
        ]
        group_rate = pooled_win_rate(group_sample)
        comparison_rate = pooled_win_rate(comparison_sample)
        if group_rate is not None and comparison_rate is not None:
            deltas.append(group_rate - comparison_rate)
    deltas.sort()
    low = deltas[int(0.025 * (len(deltas) - 1))]
    high = deltas[int(0.975 * (len(deltas) - 1))]
    return low, high


def summarize_decks(decks: list[dict], *, seed: int = BOOTSTRAP_SEED) -> dict:
    games = sum(deck["games"] for deck in decks)
    wins = sum(deck["wins"] for deck in decks)
    interval = bootstrap_win_rate_interval(decks, seed=seed)
    return {
        "decks": len(decks),
        "games": games,
        "game_wins": wins,
        "game_weighted_win_rate": wins / games if games else None,
        "game_weighted_win_rate_ci_95": list(interval) if interval else None,
    }


def analyze_archive(path: Path) -> dict:
    required = ("draft_id", "build_index", "main_colors", "won")
    source_rows = invalid_results = missing_identity = missing_colors = invalid_colors = 0
    decks: dict[tuple[str, str], dict] = {}
    identity_colors: dict[tuple[str, str], str] = {}
    conflicting_decks: set[tuple[str, str]] = set()
    incomplete_decks: set[tuple[str, str]] = set()

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
                incomplete_decks.add(key)
                continue
            if colors is None:
                invalid_colors += 1
                incomplete_decks.add(key)
                continue

            if key in identity_colors and identity_colors[key] != colors:
                conflicting_decks.add(key)
            identity_colors[key] = colors

            won = parse_bool(row.get("won"))
            if won is None:
                invalid_results += 1
                incomplete_decks.add(key)
                continue
            deck = decks.setdefault(key, {"colors": colors, "games": 0, "wins": 0})
            deck["games"] += 1
            deck["wins"] += int(won)

    excluded_decks = conflicting_decks | incomplete_decks
    valid_decks = [value for key, value in decks.items() if key not in excluded_decks]
    excluded_game_rows = sum(decks[key]["games"] for key in excluded_decks if key in decks)

    pair_decks: dict[str, list[dict]] = {}
    non_pair_decks = 0
    for deck in valid_decks:
        if len(deck["colors"]) == 2:
            pair_decks.setdefault(deck["colors"], []).append(deck)
        else:
            non_pair_decks += 1

    baseline = summarize_decks(valid_decks)
    by_color_pair = {}
    for pair, members in sorted(pair_decks.items()):
        comparison = [
            deck for deck in valid_decks if deck["colors"] != pair
        ]
        seed = BOOTSTRAP_SEED + sum(ord(char) for char in pair)
        summary = summarize_decks(members, seed=seed)
        comparison_rate = pooled_win_rate(comparison)
        pair_rate = summary["game_weighted_win_rate"]
        delta_interval = bootstrap_delta_interval(members, comparison, seed=seed + 1)
        summary["comparison_decks"] = len(comparison)
        summary["comparison_games"] = sum(deck["games"] for deck in comparison)
        summary["comparison_game_weighted_win_rate"] = comparison_rate
        summary["delta_vs_rest_percentage_points"] = (
            (pair_rate - comparison_rate) * 100
            if pair_rate is not None and comparison_rate is not None else None
        )
        summary["delta_vs_rest_ci_95_percentage_points"] = (
            [value * 100 for value in delta_interval] if delta_interval else None
        )
        by_color_pair[pair] = summary

    return {
        "source_rows": source_rows,
        "missing_identity_rows": missing_identity,
        "missing_main_colors_rows": missing_colors,
        "invalid_main_colors_rows": invalid_colors,
        "missing_or_invalid_result_rows": invalid_results,
        "conflicting_deck_identity_count": len(conflicting_decks),
        "incomplete_deck_identity_count": len(incomplete_decks - conflicting_decks),
        "excluded_deck_identity_count": len(excluded_decks),
        "excluded_valid_game_rows_from_incomplete_or_conflicting_decks": excluded_game_rows,
        "non_two_color_decks": non_pair_decks,
        "valid_deck_count": len(valid_decks),
        "overall_deck_baseline": baseline,
        "by_color_pair": by_color_pair,
    }


def pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.1%}"


def interval_text(value: list[float] | None, *, scale: float = 1.0, suffix: str = "") -> str:
    if not value:
        return "n/a"
    return f"{value[0] * scale:.1f}{suffix}–{value[1] * scale:.1f}{suffix}"


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
        f"- Deck identities with incomplete game rows (excluded): {result['incomplete_deck_identity_count']:,}",
        f"- Valid game rows excluded with incomplete/conflicting decks: {result['excluded_valid_game_rows_from_incomplete_or_conflicting_decks']:,}",
        f"- Valid non-two-color decks (not in pair table): {result['non_two_color_decks']:,}", "",
        "## Format baseline", "",
        f"- Decks: {baseline['decks']:,}; games: {baseline['games']:,}",
        f"- Game-weighted win rate: {pct(baseline['game_weighted_win_rate'])}",
        f"- 95% deck-cluster bootstrap interval: {interval_text(baseline['game_weighted_win_rate_ci_95'], scale=100, suffix='%')}",
        "", "## Two-color results", "",
        "Sorted by observed game-weighted win rate for readability; this is not a strength ranking.", "",
        "| Colors | Decks | Games | Game-weighted win rate | 95% interval | vs. rest of field (95% interval) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for pair, part in sorted(
        result["by_color_pair"].items(),
        key=lambda item: (item[1]["game_weighted_win_rate"] or 0),
        reverse=True,
    ):
        delta = part["delta_vs_rest_percentage_points"]
        delta_text = "n/a" if delta is None else f"{delta:+.1f} pp"
        delta_ci = part["delta_vs_rest_ci_95_percentage_points"]
        delta_text += f" ({interval_text(delta_ci, suffix=' pp')})"
        lines.append(
            f"| {pair} | {part['decks']:,} | {part['games']:,} | "
            f"{pct(part['game_weighted_win_rate'])} | "
            f"{interval_text(part['game_weighted_win_rate_ci_95'], scale=100, suffix='%')} | "
            f"{delta_text} |"
        )
    lines += [
        "", "## Method and limitations", "",
        "- The primary win-rate estimate is pooled game wins divided by pooled games, matching the familiar game-level win-rate measure.",
        "- Uncertainty intervals resample whole decks (draft_id, build_index) as clusters, then recompute the pooled game win rate. Games from one deck are not treated as independent bootstrap observations.",
        "- Each color pair is compared with the rest of the field, excluding that pair from its comparison baseline. The delta interval independently resamples deck clusters from each side.",
        "- The public archive does not provide a stable player identifier for clustering multiple decks by drafter. Repeated decks by one player may therefore remain correlated.",
        "- Deck identities with conflicting main-color assignments or any incomplete game rows are excluded in full, rather than estimating a deck from only its valid subset of games.",
        "- The overall baseline includes mono-color and three-or-more-color decks. Only exactly two-color decks appear in the comparison table.",
        "- main_colors is used as the deck's primary color identity. Splash colors are not folded into the pair label.",
        "- Color pairs are broad buckets. They do not distinguish different strategies within a pair, and a pair can contain multiple archetypes.",
        "- Results are descriptive and are not adjusted for player skill, rank, date, or event subgroup. Confidence intervals do not remove those confounders.",
        "- Do not use these results to modify live recommendations until sample coverage, cohort comparability, and archetype semantics have been reviewed.",
        "",
    ]
    return "\n".join(lines)


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
            "schema_version": 2,
            "analysis": "17lands-archetype-performance",
            "set_code": set_code,
            "event_type": event_type,
            "source_url": archive_url(set_code, event_type),
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            **result,
        }
        (output / "archetype-summary.json").write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )
        print(report)
        return 0
    except Exception as exc:
        message = f"Archetype audit failed: {type(exc).__name__}: {exc}"
        (output / "archetype-error.txt").write_text(message + "\n", encoding="utf-8")
        print(message)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
