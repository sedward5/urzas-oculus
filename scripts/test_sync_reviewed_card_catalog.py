import json
import subprocess
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parent
class ReviewedCardCatalogSyncTests(unittest.TestCase):
    def test_generated_copies_match_canonical(self):
        subprocess.run([sys.executable, str(ROOT / "sync_reviewed_card_catalog.py")], check=True)
        expected = json.loads((ROOT / "data/reviewed_cards.json").read_text(encoding="utf-8"))
        for path in (ROOT.parent / "website/data/reviewed_cards.json", ROOT.parent / "Sources/UrzasOculusApp/Resources/reviewed_cards.json"):
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), expected)
if __name__ == "__main__":
    unittest.main()
