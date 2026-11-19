import gzip
import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("inspect-17lands-replay.py")
SPEC = importlib.util.spec_from_file_location("replay_audit", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class ReplayAuditTests(unittest.TestCase):
    def test_archive_url_uses_replay_data_layout(self):
        self.assertEqual(
            AUDIT.archive_url("replay", "HOB", "PremierDraft"),
            "https://17lands-public.s3.amazonaws.com/analysis_data/replay_data/"
            "replay_data_public.HOB.PremierDraft.csv.gz",
        )

    def test_scan_archive_counts_game_keys_and_column_families(self):
        with tempfile.NamedTemporaryFile(suffix=".csv.gz", delete=False) as handle:
            path = Path(handle.name)
        self.addCleanup(path.unlink, missing_ok=True)
        with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
            stream.write(
                "draft_id,build_index,match_number,game_number,deck_Card A,"
                "candidate_hand_1,user_turn_1_cards_drawn\n"
                "d1,0,1,1,2,1|2|3,4\n"
                "d1,0,1,1,2,1|2|3,5\n"
                "d2,0,1,1,1,1|2|3,\n"
            )
        result = AUDIT.scan_archive(path, "replay")
        self.assertEqual(result["rows"], 3)
        self.assertEqual(result["unique_game_keys"], 2)
        self.assertEqual(result["duplicate_key_rows"], 1)
        self.assertEqual(result["missing_identity_rows"], 0)
        self.assertEqual(result["prefixes"]["deck_"]["count"], 1)
        self.assertEqual(result["prefixes"]["candidate_hand_"]["count"], 1)


if __name__ == "__main__":
    unittest.main()
