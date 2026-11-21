import gzip
import tempfile
import unittest
from pathlib import Path

from scripts.analyze_17lands_archetypes import (
    analyze_archive,
    bootstrap_interval,
    canonical_colors,
    render_report,
)


def write_archive(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
        stream.write(",".join(header) + "\n")
        for row in rows:
            stream.write(",".join(row) + "\n")


class ArchetypeAuditTests(unittest.TestCase):
    def test_color_canonicalization(self):
        self.assertEqual(canonical_colors("UW"), "WU")
        self.assertEqual(canonical_colors("rg"), "RG")
        self.assertIsNone(canonical_colors("WUX"))
        self.assertIsNone(canonical_colors("WW"))

    def test_deck_level_aggregation_and_conflicting_identity_exclusion(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            header = ["draft_id", "build_index", "main_colors", "won"]
            rows = [
                ["a", "0", "UW", "true"],
                ["a", "0", "WU", "false"],
                ["b", "0", "WU", "true"],
                ["c", "0", "BR", "false"],
                ["c", "0", "BR", "false"],
                ["d", "0", "G", "true"],
                ["e", "0", "WUB", "true"],
                ["f", "0", "UR", "false"],
                ["f", "0", "UB", "true"],
                ["", "0", "WU", "true"],
            ]
            write_archive(path, header, rows)
            result = analyze_archive(path)
            self.assertEqual(result["source_rows"], 10)
            self.assertEqual(result["missing_identity_rows"], 1)
            self.assertEqual(result["conflicting_deck_identity_count"], 1)
            self.assertEqual(result["excluded_conflicting_deck_game_rows"], 2)
            self.assertEqual(result["non_two_color_decks"], 2)
            self.assertEqual(result["by_color_pair"]["WU"]["decks"], 1)
            self.assertEqual(result["by_color_pair"]["WU"]["games"], 1)
            self.assertEqual(result["by_color_pair"]["BR"]["mean_deck_win_rate"], 0.0)
            self.assertEqual(result["overall_deck_baseline"]["decks"], 3)

    def test_missing_fields_are_reported_and_required_schema_is_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["draft_id", "build_index", "won"], [["a", "0", "true"]])
            with self.assertRaisesRegex(ValueError, "main_colors"):
                analyze_archive(path)

    def test_bootstrap_is_deterministic_and_requires_multiple_decks(self):
        self.assertIsNone(bootstrap_interval([0.5]))
        self.assertEqual(bootstrap_interval([0.0, 1.0]), bootstrap_interval([0.0, 1.0]))

    def test_report_explains_color_pair_proxy_and_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["draft_id", "build_index", "main_colors", "won"], [
                ["a", "0", "WU", "true"], ["b", "0", "WU", "false"]
            ])
            report = render_report("HOB", "PremierDraft", analyze_archive(path))
            self.assertIn("Color pairs are proxies", report)
            self.assertIn("not a strength ranking", report)
            self.assertIn("bootstrap over deck-level win rates", report)


if __name__ == "__main__":
    unittest.main()
