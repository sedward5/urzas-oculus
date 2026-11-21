import gzip
import tempfile
import unittest
from pathlib import Path

from scripts.analyze_17lands_archetypes import (
    analyze_archive,
    bootstrap_delta_interval,
    bootstrap_win_rate_interval,
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

    def test_game_weighted_rates_and_deck_cluster_bootstrap(self):
        decks = [
            {"games": 2, "wins": 1},
            {"games": 10, "wins": 9},
        ]
        self.assertAlmostEqual(
            sum(deck["wins"] for deck in decks) / sum(deck["games"] for deck in decks),
            10 / 12,
        )
        first = bootstrap_win_rate_interval(decks)
        self.assertIsNotNone(first)
        self.assertEqual(first, bootstrap_win_rate_interval(decks))
        comparison = [{"games": 2, "wins": 0}, {"games": 2, "wins": 2}]
        delta = bootstrap_delta_interval(decks, comparison, seed=42)
        self.assertIsNotNone(delta)
        self.assertEqual(delta, bootstrap_delta_interval(decks, comparison, seed=42))
        self.assertIsNone(bootstrap_win_rate_interval([decks[0]]))

    def test_deck_aggregation_conflicts_and_incomplete_deck_exclusion(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            header = ["draft_id", "build_index", "main_colors", "won"]
            rows = [
                ["a", "0", "UW", "true"],
                ["a", "0", "UB", "false"],  # conflicting assignment
                ["b", "0", "WU", "true"],
                ["f", "0", "UW", "false"],  # same pair, separate deck
                ["c", "0", "BR", "false"],
                ["c", "0", "BR", "false"],
                ["g", "0", "BR", "true"],
                ["d", "0", "G", "true"],
                ["e", "0", "WUB", "true"],
                ["h", "0", "", "true"],  # incomplete deck identity
                ["j", "0", "WU", "true"],
                ["j", "0", "WU", "unknown"],  # excludes the entire deck
                ["", "0", "WU", "true"],
            ]
            write_archive(path, header, rows)
            result = analyze_archive(path)
            self.assertEqual(result["source_rows"], 13)
            self.assertEqual(result["missing_identity_rows"], 1)
            self.assertEqual(result["missing_main_colors_rows"], 1)
            self.assertEqual(result["missing_or_invalid_result_rows"], 1)
            self.assertEqual(result["conflicting_deck_identity_count"], 1)
            self.assertEqual(result["incomplete_deck_identity_count"], 2)
            self.assertEqual(result["excluded_deck_identity_count"], 3)
            self.assertEqual(
                result["excluded_valid_game_rows_from_incomplete_or_conflicting_decks"], 3
            )
            self.assertEqual(result["non_two_color_decks"], 2)
            self.assertEqual(result["valid_deck_count"], 6)

            baseline = result["overall_deck_baseline"]
            self.assertEqual(baseline["decks"], 6)
            self.assertEqual(baseline["games"], 7)
            self.assertAlmostEqual(baseline["game_weighted_win_rate"], 4 / 7)
            self.assertNotIn("mean_deck_win_rate", baseline)

            wu = result["by_color_pair"]["WU"]
            self.assertEqual(wu["decks"], 2)
            self.assertEqual(wu["games"], 2)
            self.assertAlmostEqual(wu["game_weighted_win_rate"], 0.5)
            self.assertAlmostEqual(wu["comparison_game_weighted_win_rate"], 3 / 5)
            self.assertAlmostEqual(wu["delta_vs_rest_percentage_points"], -10.0)
            self.assertIsNotNone(wu["delta_vs_rest_ci_95_percentage_points"])

    def test_missing_fields_are_reported_and_required_schema_is_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["draft_id", "build_index", "won"], [["a", "0", "true"]])
            with self.assertRaisesRegex(ValueError, "main_colors"):
                analyze_archive(path)

    def test_report_explains_weighting_comparison_and_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["draft_id", "build_index", "main_colors", "won"], [
                ["a", "0", "WU", "true"],
                ["b", "0", "WU", "false"],
                ["c", "0", "BR", "true"],
                ["d", "0", "BR", "false"],
            ])
            report = render_report("HOB", "PremierDraft", analyze_archive(path))
            self.assertIn("game-weighted win rate", report)
            self.assertIn("resample whole decks", report)
            self.assertIn("rest of the field", report)
            self.assertIn("Color pairs are proxies", report)
            self.assertNotIn("mean deck win rate", report)


if __name__ == "__main__":
    unittest.main()
