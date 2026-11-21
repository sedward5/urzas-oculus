import gzip
import sqlite3
from pathlib import Path

from scripts.inspect_17lands_replay_quality import compare, read_archive


def write_csv_gz(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
        stream.write(",".join(header) + "\n")
        for row in rows:
            stream.write(",".join(row) + "\n")


def test_replay_quality_detects_deck_discrepancy(tmp_path: Path) -> None:
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
    game_path, replay_path = tmp_path / "game.csv.gz", tmp_path / "replay.csv.gz"
    write_csv_gz(game_path, game_header, [key + ["7", "8", "1", "2", "1"]])
    write_csv_gz(replay_path, replay_header, [key + ["6", "8", "1", "opaque"]])

    connection = sqlite3.connect(":memory:")
    game = read_archive(game_path, "game", "game", connection)
    replay = read_archive(replay_path, "replay", "replay", connection)
    result = compare(connection)

    assert game["unique_keys"] == replay["unique_keys"] == 1
    assert result["comparisons"]["matched_games"] == 1
    assert result["comparisons"]["main_deck_mismatch_games"] == 1
    assert result["comparisons"].get("sideboard_mismatch_games", 0) == 0
    assert result["comparisons"].get("opening_hand_exceeds_deck_games", 0) == 0
    assert replay["candidate_nonempty_cells"] == 1
    connection.close()


def test_opening_hand_overage_is_reported(tmp_path: Path) -> None:
    header = [
        "draft_id", "build_index", "match_number", "game_number",
        "deck_Forest", "opening_hand_Forest",
    ]
    path = tmp_path / "game.csv.gz"
    write_csv_gz(path, header, [["draft-b", "0", "1", "1", "1", "2"]])
    replay_path = tmp_path / "replay.csv.gz"
    replay_header = ["draft_id", "build_index", "match_number", "game_number", "deck_Forest"]
    write_csv_gz(replay_path, replay_header, [["draft-b", "0", "1", "1", "1"]])

    connection = sqlite3.connect(":memory:")
    read_archive(path, "game", "game", connection)
    read_archive(replay_path, "replay", "replay", connection)
    result = compare(connection)
    assert result["comparisons"]["opening_hand_exceeds_deck_games"] == 1
    connection.close()
