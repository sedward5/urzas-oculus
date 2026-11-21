#!/usr/bin/env python3
"""Descriptive turn-length audit of a 17Lands public game archive."""
from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

BASE = "https://17lands-public.s3.amazonaws.com/analysis_data"


def archive_url(set_code: str, event_type: str) -> str:
    return f"{BASE}/game_data/game_data_public.{set_code}.{event_type}.csv.gz"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "Urzas-Oculus-SetSpeedAudit/1.0"})
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


class GameStats:
    def __init__(self) -> None:
        self.games = self.wins = 0
        self.turns: Counter[int] = Counter()
        self.wins_by_turn: Counter[int] = Counter()

    def add(self, turns: int, won: bool) -> None:
        self.games += 1
        self.wins += int(won)
        self.turns[turns] += 1
        self.wins_by_turn[turns] += int(won)

    def percentile(self, fraction: float) -> int | None:
        if not self.games:
            return None
        target = max(1, int(self.games * fraction + 0.999999))
        seen = 0
        for turn, count in sorted(self.turns.items()):
            seen += count
            if seen >= target:
                return turn
        return max(self.turns)

    def summary(self) -> dict:
        by_turn = []
        for turn, count in sorted(self.turns.items()):
            by_turn.append({
                "turns": turn, "games": count, "share": count / self.games,
                "wins": self.wins_by_turn[turn],
                "win_rate": self.wins_by_turn[turn] / count,
            })
        ended = {str(n): sum(c for t, c in self.turns.items() if t <= n) for n in (5, 6, 7)}
        long_games = sum(c for t, c in self.turns.items() if t >= 10)
        return {
            "games": self.games, "wins": self.wins,
            "win_rate": self.wins / self.games if self.games else None,
            "median_turns": self.percentile(.5), "p25_turns": self.percentile(.25),
            "p75_turns": self.percentile(.75), "p90_turns": self.percentile(.90),
            "ended_by_turn": ended,
            "ended_by_turn_share": {k: v / self.games for k, v in ended.items()} if self.games else {},
            "reached_turn_10_plus": long_games,
            "reached_turn_10_plus_share": long_games / self.games if self.games else None,
            "turn_distribution": by_turn,
        }


def analyze_archive(path: Path) -> dict:
    overall = GameStats()
    splits = {"on_play": GameStats(), "on_draw": GameStats()}
    rows = missing_turns = invalid_turns = invalid_results = missing_seat = 0
    missing_identity = 0
    first_time = last_time = None
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = reader.fieldnames or []
        if len(fields) != len(set(fields)):
            raise ValueError("game archive has duplicate headers")
        missing = [name for name in ("num_turns", "won") if name not in fields]
        if missing:
            raise ValueError(f"game archive missing required fields: {missing}")
        identity = ("draft_id", "build_index", "match_number", "game_number")
        has_identity = all(name in fields for name in identity)
        has_seat = "on_play" in fields
        for rows, row in enumerate(reader, 1):
            if has_identity and not all((row.get(k) or "").strip() for k in identity):
                missing_identity += 1
            timestamp = (row.get("draft_time") or "").strip()
            if timestamp:
                first_time = timestamp if first_time is None else min(first_time, timestamp)
                last_time = timestamp if last_time is None else max(last_time, timestamp)
            raw_turns = (row.get("num_turns") or "").strip()
            if not raw_turns:
                missing_turns += 1
                continue
            try:
                turns = int(raw_turns)
            except ValueError:
                invalid_turns += 1
                continue
            if turns <= 0:
                invalid_turns += 1
                continue
            won = parse_bool(row.get("won"))
            if won is None:
                invalid_results += 1
                continue
            overall.add(turns, won)
            if has_seat:
                seat = parse_bool(row.get("on_play"))
                if seat is None:
                    missing_seat += 1
                else:
                    splits["on_play" if seat else "on_draw"].add(turns, won)
    return {
        "source_rows": rows, "missing_turn_count_rows": missing_turns,
        "invalid_turn_count_rows": invalid_turns, "missing_or_invalid_result_rows": invalid_results,
        "missing_identity_rows": missing_identity if has_identity else None,
        "missing_play_draw_rows": missing_seat if has_seat else None,
        "draft_time_min": first_time, "draft_time_max": last_time,
        "overall": overall.summary(),
        "by_play_draw": {k: v.summary() for k, v in splits.items()} if has_seat else None,
    }


def pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.1%}"


def render_report(set_code: str, event_type: str, result: dict) -> str:
    stats = result["overall"]
    lines = [
        f"# 17Lands set-speed audit — {set_code} {event_type}", "",
        "Descriptive summary of the public game archive; not a causal model or a reproduction of 17Lands' eligibility decisions.", "",
        "## Coverage", "",
        f"- Source rows: {result['source_rows']:,}",
        f"- Included games: {stats['games']:,}",
        f"- Missing turn counts: {result['missing_turn_count_rows']:,}",
        f"- Invalid turn counts: {result['invalid_turn_count_rows']:,}",
        f"- Missing/invalid results: {result['missing_or_invalid_result_rows']:,}",
        f"- Rows missing identity fields: {result['missing_identity_rows'] if result['missing_identity_rows'] is not None else 'not available'}",
        f"- Draft-time range: {result['draft_time_min'] or 'not available'} to {result['draft_time_max'] or 'not available'}", "",
        "## Overall game length", "",
        f"- Median: {stats['median_turns']} (P25 {stats['p25_turns']}; P75 {stats['p75_turns']}; P90 {stats['p90_turns']})",
        f"- Ended by turn 5: {stats['ended_by_turn']['5']:,} ({pct(stats['ended_by_turn_share'].get('5'))})",
        f"- Ended by turn 6: {stats['ended_by_turn']['6']:,} ({pct(stats['ended_by_turn_share'].get('6'))})",
        f"- Ended by turn 7: {stats['ended_by_turn']['7']:,} ({pct(stats['ended_by_turn_share'].get('7'))})",
        f"- Reached turn 10+: {stats['reached_turn_10_plus']:,} ({pct(stats['reached_turn_10_plus_share'])})",
        f"- Overall user win rate: {pct(stats['win_rate'])}", "",
        "## Turn-count distribution", "",
        "| Turns | Games | Share | User win rate |", "|---:|---:|---:|---:|",
    ]
    for item in stats["turn_distribution"]:
        lines.append(f"| {item['turns']} | {item['games']:,} | {pct(item['share'])} | {pct(item['win_rate'])} |")
    lines += ["", "## Play/draw split", ""]
    if result["by_play_draw"] is None:
        lines.append("The archive does not include an on_play field.")
    else:
        lines += ["| Seat status | Games | Median turns | Ended by turn 6 | Reached turn 10+ | Win rate |",
                  "|---|---:|---:|---:|---:|---:|"]
        for key, label in (("on_play", "On the play"), ("on_draw", "On the draw")):
            part = result["by_play_draw"][key]
            lines.append(f"| {label} | {part['games']:,} | {part['median_turns']} | "
                         f"{pct(part['ended_by_turn_share'].get('6'))} | "
                         f"{pct(part['reached_turn_10_plus_share'])} | {pct(part['win_rate'])} |")
        lines += ["", f"- Rows without a usable on_play value: {result['missing_play_draw_rows']:,}"]
    lines += ["", "## Interpretation notes", "",
        "- num_turns is reported as supplied by the archive; this audit does not reinterpret it as match length or a player-turn count.",
        "- Win rate by game length is descriptive; it does not show that longer or shorter games cause wins.",
        "- Play/draw groups are separated because seat status can affect game length and outcomes.",
        "- Compare only compatible event types, player-performance groups, and overlapping date/coverage windows.",
        "- The public archive may omit games 17Lands considers inconsistent. This audit does not reproduce that eligibility filter.",
        "- No faster/balanced/slower label is assigned from one median; classification needs a compatible baseline and uncertainty review.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set-code", default="HOB")
    parser.add_argument("--event-type", default="PremierDraft")
    parser.add_argument("--output-dir", default="set-speed-output")
    args = parser.parse_args()
    set_code, event_type = args.set_code.strip().upper(), args.event_type.strip()
    if not re.fullmatch(r"[A-Z0-9]+", set_code):
        parser.error("set code must contain only letters and numbers")
    if not re.fullmatch(r"[A-Za-z0-9]+", event_type):
        parser.error("event type must contain only letters and numbers")
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    try:
        with TemporaryDirectory(prefix="urzas-oculus-set-speed-") as temp:
            archive = Path(temp) / "game.csv.gz"
            download(archive_url(set_code, event_type), archive)
            result = analyze_archive(archive)
        report = render_report(set_code, event_type, result)
        (output / "set-speed-report.md").write_text(report, encoding="utf-8")
        payload = {"schema_version": 1, "analysis": "17lands-set-speed",
                   "set_code": set_code, "event_type": event_type,
                   "source_url": archive_url(set_code, event_type),
                   "generated_at_utc": datetime.now(timezone.utc).isoformat(),
                   **result}
        (output / "set-speed-summary.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(report)
        return 0
    except Exception as exc:
        message = f"Set-speed audit failed: {type(exc).__name__}: {exc}"
        (output / "set-speed-error.txt").write_text(message + "\n", encoding="utf-8")
        print(message)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
