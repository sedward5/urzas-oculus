import json
import tempfile
import unittest
from pathlib import Path

from scripts.generate_website_archetype_pages import generate


class GenerateWebsiteArchetypePagesTests(unittest.TestCase):
    def test_generates_reviewed_page_and_preserves_preliminary_page(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog_path = root / "reviewed.json"
            destination = root / "archetypes"
            catalog_path.write_text(
                json.dumps({
                    "sets": {
                        "HOB": {
                            "set_name": "The Hobbit",
                            "release_date": "2026-08-14",
                            "archetypes": [{"id": "humans"}],
                        }
                    }
                }),
                encoding="utf-8",
            )
            preliminary = destination / "trk" / "_index.md"
            preliminary.parent.mkdir(parents=True)
            preliminary.write_text(
                '---\ntitle: "Star Trek"\ncontent_status: "preliminary"\n---\n',
                encoding="utf-8",
            )

            self.assertEqual(generate(catalog_path, destination), 1)

            generated = (destination / "hob" / "_index.md").read_text(encoding="utf-8")
            self.assertIn('release_date: "2026-08-14"', generated)
            self.assertIn('content_status: "reviewed"', generated)
            self.assertEqual(
                preliminary.read_text(encoding="utf-8"),
                '---\ntitle: "Star Trek"\ncontent_status: "preliminary"\n---\n',
            )

    def test_requires_release_date_for_deterministic_ordering(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog_path = root / "reviewed.json"
            catalog_path.write_text(
                json.dumps({"sets": {"HOB": {"set_name": "The Hobbit", "archetypes": []}}}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "release_date"):
                generate(catalog_path, root / "archetypes")


if __name__ == "__main__":
    unittest.main()
