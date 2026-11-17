import gzip
import io
import importlib.util
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate-17lands-archives.py")
SPEC = importlib.util.spec_from_file_location("archive_validator", SCRIPT)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class ArchiveReferenceTests(unittest.TestCase):
    def write_gzip_csv(self, text):
        handle = tempfile.NamedTemporaryFile(suffix=".csv.gz", delete=False)
        path = Path(handle.name)
        handle.close()
        with gzip.open(path, "wt", encoding="utf-8", newline="") as stream:
            stream.write(text)
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def test_game_reference_aggregates_copy_weighted_metrics(self):
        path = self.write_gzip_csv(
            "won,main_colors,deck_A,sideboard_A,opening_hand_A,drawn_A,tutored_A\n"
            "true,WU,2,0,1,1,0\n"
            "false,WU,1,1,0,0,1\n"
        )
        rows, wins, metrics = VALIDATOR.game_reference(path)
        self.assertEqual((rows, wins), (2, 1))
        self.assertEqual(metrics["A"]["gamesPlayedCount"], 3)
        self.assertAlmostEqual(metrics["A"]["gamesPlayedWinRate"], 2 / 3)
        self.assertAlmostEqual(metrics["A"]["playRate"], 3 / 4)
        self.assertEqual(metrics["A"]["gamesInHandCount"], 2)
        self.assertEqual(metrics["A"]["gamesInHandWinRate"], 1.0)
        self.assertIsNone(metrics["A"]["gamesNotSeenWinRate"])

    def test_archive_urls_use_documented_s3_layout(self):
        draft, game = VALIDATOR.archive_urls("hob", "PremierDraft")
        base = "https://17lands-public.s3.amazonaws.com/analysis_data"
        self.assertEqual(draft, f"{base}/draft_data/draft_data_public.HOB.PremierDraft.csv.gz")
        self.assertEqual(game, f"{base}/game_data/game_data_public.HOB.PremierDraft.csv.gz")

    def test_archives_fall_back_when_catalog_markup_has_no_links(self):
        with (
            patch.object(VALIDATOR, "get", return_value=io.BytesIO(b"<html></html>")),
            patch.object(VALIDATOR, "verify_archive_url") as verify,
        ):
            draft, game, updated = VALIDATOR.archives("HOB", "PremierDraft")
        self.assertIn("draft_data_public.HOB.PremierDraft.csv.gz", draft)
        self.assertIn("game_data_public.HOB.PremierDraft.csv.gz", game)
        self.assertIn("unknown", updated)
        self.assertEqual(verify.call_count, 2)

    def test_draft_reference_tracks_wheel_in_pack_lane(self):
        path = self.write_gzip_csv(
            "draft_id,pack_number,pick_number,pick,pick_2,pack_card_Wheel,pack_card_Late\n"
            "d1,1,1,Picked,,1,0\n"
            "d1,1,2,Other,,0,1\n"
            "d1,1,9,Wheel,,1,0\n"
            "d1,1,10,Late,,0,1\n"
        )
        rows, metrics = VALIDATOR.draft_reference(path)
        self.assertEqual(rows, 4)
        self.assertEqual(metrics["Wheel"]["seenCount"], 1)
        self.assertEqual(metrics["Wheel"]["averageLastSeen"], 9)
        self.assertEqual(metrics["Wheel"]["pickCount"], 1)
        self.assertEqual(metrics["Wheel"]["averageTakenAt"], 9)
        self.assertEqual(metrics["Late"]["averageLastSeen"], 10)
        self.assertEqual(metrics["Late"]["averageTakenAt"], 10)


if __name__ == "__main__":
    unittest.main()
