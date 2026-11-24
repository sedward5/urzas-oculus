import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ops_inventory

class OpsInventoryTests(unittest.TestCase):
    def test_enriches_set_status_from_local_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest_dir = root / "website/static/data/sets/TRK"
            (manifest_dir / "scryfall").mkdir(parents=True)
            (manifest_dir / "manifest.json").write_text(json.dumps({
                "generated_at": "2026-11-23T12:00:00Z",
                "status": {"scryfall": "acquired", "17lands": "not_yet_published"}
            }))
            (manifest_dir / "scryfall/trk-cards.json").write_text("{}")
            archetype_dir = root / "scripts/data"
            archetype_dir.mkdir(parents=True)
            (archetype_dir / "reviewed_archetypes.json").write_text(json.dumps({
                "sets": {"TRK": {"source_url": "https://magic.wizards.com/en/news/feature/star-trek-prerelease-guide",
                    "overview_image": {"source_url": "https://media.wizards.com/example.jpg"}}}
            }))
            report = {"sets": [{"code": "TRK", "name": "Star Trek", "17lands": []}]}
            result = build_ops_inventory.build_inventory(root, report, runs=[])
            item = result["sets"][0]
            self.assertEqual(item["acquisition"]["status"], "acquired")
            self.assertTrue(item["acquisition"]["card_file_present"])
            self.assertEqual(item["archetype_image"]["status"], "present")
            self.assertEqual(item["wizards_guide"]["status"], "found_in_reviewed_catalog")
            self.assertEqual(item["prediction"]["status"], "not_run")
            self.assertEqual(result["workflow_runs"], [])

    def test_missing_sources_are_explicit_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            result = build_ops_inventory.build_inventory(directory,
                {"sets": [{"code": "ZZZ", "name": "Unknown", "17lands": []}]}, runs=[])
            item = result["sets"][0]
            self.assertEqual(item["acquisition"]["status"], "not_run")
            self.assertFalse(item["acquisition"]["card_file_present"])
            self.assertEqual(item["archetype_image"]["status"], "missing")
            self.assertEqual(item["prediction"]["status"], "not_run")
            self.assertEqual(item["wizards_guide"]["status"], "search_available")

if __name__ == "__main__":
    unittest.main()
