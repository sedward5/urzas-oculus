import gzip
import tempfile
import unittest
from pathlib import Path

from scripts.analyze_17lands_set_speed import analyze_archive, render_report


def write_archive(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
        stream.write(",".join(header) + "\n")
        for row in rows:
            stream.write(",".join(row) + "\n")


class SetSpeedAuditTests(unittest.TestCase):
    def test_distribution_and_play_draw_splits(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            header = ["draft_id", "build_index", "match_number", "game_number",
                      "num_turns", "won", "on_play", "draft_time"]
            rows = [
                ["a", "0", "1", "1", "5", "1", "True", "2026-01-01"],
                ["b", "0", "1", "1", "6", "0", "False", "2026-01-02"],
                ["c", "0", "1", "1", "7", "1", "True", "2026-01-03"],
                ["d", "0", "1", "1", "10", "0", "True", "2026-01-04"],
                ["e", "0", "1", "1", "10", "1", "False", "2026-01-05"],
                ["f", "0", "1", "1", "0", "1", "True", "2026-01-06"],
                ["g", "0", "1", "1", "8", "", "True", "2026-01-07"],
            ]
            write_archive(path, header, rows)
            result = analyze_archive(path)
            stats = result["overall"]
            self.assertEqual(result["source_rows"], 7)
            self.assertEqual(stats["games"], 5)
            self.assertEqual(result["invalid_turn_count_rows"], 1)
            self.assertEqual(result["missing_or_invalid_result_rows"], 1)
            self.assertEqual(stats["median_turns"], 7)
            self.assertEqual(stats["ended_by_turn"], {"5": 1, "6": 2, "7": 3})
            self.assertEqual(stats["reached_turn_10_plus"], 2)
            self.assertEqual(result["by_play_draw"]["on_play"]["games"], 3)
            self.assertEqual(result["by_play_draw"]["on_draw"]["games"], 2)

    def test_historical_win_rate_buckets_are_not_performance_groups(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(
                path,
                ["num_turns", "won", "user_game_win_rate_bucket"],
                [["6", "true", "Top"], ["9", "false", "Bottom"]],
            )
            result = analyze_archive(path)
            self.assertEqual(result["historical_user_win_rate_bucket_field"], "user_game_win_rate_bucket")
            self.assertEqual(result["by_historical_user_win_rate_bucket"]["Top"]["games"], 1)
            self.assertEqual(result["by_historical_user_win_rate_bucket"]["Bottom"]["games"], 1)
            self.assertEqual(result["missing_historical_user_win_rate_bucket_games"], 0)
            report = render_report("HOB", "PremierDraft", result)
            self.assertIn("Historical user win-rate buckets", report)
            self.assertIn("not 17Lands Top/Middle/Bottom performance groups", report)
            self.assertNotIn("Player-performance groups", report)

    def test_missing_historical_bucket_count(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["num_turns", "won", "user_game_win_rate_bucket"], [
                ["6", "true", "0.70"], ["8", "false", ""], ["9", "true", "0.72"]
            ])
            result = analyze_archive(path)
            self.assertEqual(result["missing_historical_user_win_rate_bucket_games"], 1)
            self.assertEqual(sum(v["games"] for v in result["by_historical_user_win_rate_bucket"].values()), 2)

    def test_optional_play_draw_field(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["num_turns", "won"], [["8", "true"], ["9", "false"]])
            result = analyze_archive(path)
            self.assertEqual(result["overall"]["games"], 2)
            self.assertEqual(result["overall"]["median_turns"], 8.5)
            self.assertIsNone(result["by_play_draw"])

    def test_report_states_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "game.csv.gz"
            write_archive(path, ["num_turns", "won"], [["8", "true"]])
            report = render_report("HOB", "PremierDraft", analyze_archive(path))
            self.assertIn("does not show that longer or shorter games cause wins", report)
            self.assertIn("No faster/balanced/slower label", report)


if __name__ == "__main__":
    unittest.main()
