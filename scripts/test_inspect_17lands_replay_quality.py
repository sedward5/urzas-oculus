import gzip
import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts.inspect_17lands_replay_quality import compare, read_archive


def write_csv_gz(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
        stream.write(",".join(header) + "\n")
        for row in rows:
            stream.write(",".join(row) + "\n")


class ReplayQualityAuditTests(unittest.TestCase):
    def test_replay_quality_detects_deck_discrepancy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = ["draft-a", "0", "1", "1"]
            game_header = [
                "draft_id", "build_index", "match_number", "game_number",
                "deck_Forest", "deck_Island", "sideboard_Mountain",
                "opening_hand_Forest", "opening_hand_Island",
            ]
            replay_header = [
                "draft_id", "build_index", "match_number", "game_number",
                "deck_Forest", "deck_Island", "sideboard_Mountain", "candidate_hand_1",
            ]
            game_path, replay_path = root / "game.csv.gz", root / "replay.csv.gz"
            write_csv_gz(game_path, game_header, [key + ["7", "8", "1", "2", "1"]])
            write_csv_gz(replay_path, replay_header, [key + ["6", "8", "1", "opaque"]])

            connection = sqlite3.connect(":memory:")
            game = read_archive(game_path, "game", "game", connection)
            replay = read_archive(replay_path, "replay", "replay", connection)
            result = compare(connection)
            connection.close()

            self.assertEqual(game["unique_keys"], replay["unique_keys"])
            self.assertEqual(result["comparisons"]["matched_games"], 1)
            self.assertEqual(result["comparisons"]["main_deck_mismatch_games"], 1)
            self.assertEqual(result["comparisons"].get("sideboard_mismatch_games", 0), 0)
            self.assertEqual(result["comparisons"].get("opening_hand_exceeds_deck_games", 0), 0)
            self.assertEqual(replay["candidate_nonempty_cells"], 1)

    def test_opening_hand_overage_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game_header = [
                "draft_id", "build_index", "match_number", "game_number",
                "deck_Forest", "opening_hand_Forest",
            ]
            replay_header = [
                "draft_id", "build_index", "match_number", "game_number", "deck_Forest",
            ]
            game_path, replay_path = root / "game.csv.gz", root / "replay.csv.gz"
            write_csv_gz(game_path, game_header, [["draft-b", "0", "1", "1", "1", "2"]])
            write_csv_gz(replay_path, replay_header, [["draft-b", "0", "1", "1", "1"]])

            connection = sqlite3.connect(":memory:")
            read_archive(game_path, "game", "game", connection)
            read_archive(replay_path, "replay", "replay", connection)
            result = compare(connection)
            connection.close()

            self.assertEqual(result["comparisons"]["opening_hand_exceeds_deck_games"], 1)


if __name__ == "__main__":
    unittest.main()
