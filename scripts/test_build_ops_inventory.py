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

    def test_uses_preliminary_page_evidence_and_manifest_card_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            set_root = root / "website/static/data/sets/TRK"
            (set_root / "scryfall").mkdir(parents=True)
            (set_root / "wizards").mkdir()
            (set_root / "manifest.json").write_text(json.dumps({
                "generated_at": "2026-11-23T12:00:00Z",
                "status": {"scryfall": "acquired"},
                "files": [{"path": "scryfall/trk-cards.json", "records": 311}]
            }))
            (set_root / "scryfall/trk-cards.json").write_text("{}")
            (set_root / "wizards/guide-evidence.json").write_text(json.dumps({
                "source_url": "https://magic.wizards.com/en/news/feature/star-trek-prerelease-guide",
                "overview_images": [{"url": "https://media.wizards.com/example.jpg"}]
            }))
            page = root / "website/content/archetypes/trk"
            page.mkdir(parents=True)
            (page / "_index.md").write_text(
                '---\ncontent_status: "preliminary"\nevidence_path: "static/data/sets/TRK/wizards/guide-evidence.json"\n---\n')
            report = {"sets": [{"code": "TRK", "name": "Star Trek", "17lands": []}]}
            item = build_ops_inventory.build_inventory(root, report, runs=[])["sets"][0]
            self.assertEqual(item["acquisition"]["card_record_count"], 311)
            self.assertEqual(item["archetype_page"]["status"], "preliminary")
            self.assertEqual(item["archetype_image"]["status"], "present")
            self.assertEqual(item["wizards_guide"]["status"], "found_in_acquisition_evidence")

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

    def test_merges_retained_event_manifest_when_catalog_is_unavailable_and_raw_archives_are_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            event_dir = root / "website/static/data/17lands/HOB/PremierDraft"
            event_dir.mkdir(parents=True)
            (event_dir / "manifest.json").write_text(json.dumps({
                "schema_version": 1, "set_code": "HOB", "event_type": "PremierDraft",
                "generated_at": "2026-11-24T22:08:22Z",
                "catalog_status": "unavailable",
                "archives": {
                    "draft": {"url": "https://data.example/draft.csv.gz", "sha256": "a" * 64,
                              "bytes": 100, "physical_lines": 10, "gzip_valid": True},
                    "game": {"url": "https://data.example/game.csv.gz", "sha256": "b" * 64,
                             "bytes": 200, "physical_lines": 20, "gzip_valid": True}
                },
                "archive_retention": "ci_ephemeral_not_committed_or_published"
            }))
            report = {"sets": [{"code": "HOB", "name": "The Hobbit", "17lands": [],
                                "17lands_status": "unavailable"}]}
            item = build_ops_inventory.build_inventory(root, report, runs=[])["sets"][0]
            event = item["17lands"][0]
            self.assertEqual(event["event_type"], "PremierDraft")
            self.assertEqual(event["provenance_archive_count"], 2)
            self.assertEqual(event["local_raw_archive_count"], 0)
            self.assertFalse(event["refresh_recommended"])
            self.assertEqual(event["refresh_reason"],
                             "source listing unavailable; retained acquisition provenance is current")
            self.assertEqual(event["processed_data"]["status"], "not_generated")

    def test_processed_artifacts_are_tracked_separately_from_raw_archive_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            event_dir = root / "website/static/data/17lands/HOB/PremierDraft"
            processed = event_dir / "processed"
            processed.mkdir(parents=True)
            (event_dir / "manifest.json").write_text(json.dumps({
                "event_type": "PremierDraft", "generated_at": "2026-11-24T22:08:22Z",
                "archives": {"draft": {"url": "https://data.example/d.csv.gz",
                    "sha256": "a" * 64, "gzip_valid": True}}
            }))
            (processed / "card-metrics.json").write_text("{}")
            report = {"sets": [{"code": "HOB", "name": "The Hobbit", "17lands": []}]}
            event = build_ops_inventory.build_inventory(root, report, runs=[])["sets"][0]["17lands"][0]
            self.assertEqual(event["processed_data"]["status"], "available")
            self.assertEqual(len(event["processed_data"]["artifacts"]), 1)
            self.assertEqual(event["local_raw_archive_count"], 0)

    def test_recommends_refresh_when_public_listing_is_newer_than_local_acquisition(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            set_root = root / "website/static/data/sets/TRK"
            set_root.mkdir(parents=True)
            (set_root / "manifest.json").write_text(json.dumps({
                "generated_at": "2026-11-01T12:00:00Z",
                "event_type": "PremierDraft",
                "status": {"scryfall": "acquired"}
            }))
            local_dir = root / "website/static/data/17lands/TRK/PremierDraft"
            local_dir.mkdir(parents=True)
            (local_dir / "draft.csv.gz").write_bytes(b"fixture")
            report = {"sets": [{"code": "TRK", "name": "Star Trek", "17lands": [{
                "event_type": "PremierDraft", "last_updated": "2026-11-20",
                "archives": {"draft": "https://example.test/draft.csv.gz"}
            }]}]}
            result = build_ops_inventory.build_inventory(root, report, runs=[])
            event = result["sets"][0]["17lands"][0]
            self.assertTrue(event["refresh_recommended"])
            self.assertEqual(event["refresh_reason"], "source listing is newer than the local acquisition")
            self.assertEqual(event["days_since_update"], (build_ops_inventory.datetime.now(build_ops_inventory.timezone.utc).date() - build_ops_inventory.date(2026, 11, 20)).days)

if __name__ == "__main__":
    unittest.main()
