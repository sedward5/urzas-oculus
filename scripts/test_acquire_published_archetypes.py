import json
import tempfile
import unittest
from pathlib import Path

from scripts.acquire_published_archetypes import acquire, extract_candidates, ArticleParser


FIXTURE = """<!doctype html><html><head><title>Sample Prerelease Guide</title></head>
<body><main><h2>Draft Archetypes</h2>
<h3>White-Blue Humans</h3><p>Draw cards and make tokens.</p>
<h3>Black-Red Goblins</h3><p>Build an Army token.</p>
<h3>Abzan Endure</h3><p>Three-color strategy.</p>
<h2>Other Limited Notes</h2><p>Not an archetype.</p>
<img alt="Draft Archetypes Overview" src="/images/archetypes.jpg">
</main></body></html>"""


class PublishedArchetypeAcquisitionTests(unittest.TestCase):
    def test_extracts_heading_names_and_only_explicit_two_color_identity(self):
        parser = ArticleParser()
        parser.feed(FIXTURE)
        candidates = extract_candidates(parser)
        self.assertEqual([item["display_name"] for item in candidates],
                         ["Humans", "Goblins", "Abzan Endure"])
        self.assertEqual(candidates[0]["published_color_identity"], "WU")
        self.assertEqual(candidates[1]["published_color_identity"], "BR")
        self.assertIsNone(candidates[2]["published_color_identity"])
        self.assertEqual(candidates[2]["color_identity_status"], "unresolved")

    def test_stops_at_next_section_and_preserves_image_review_requirement(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "article.html"
            fixture.write_text(FIXTURE, encoding="utf-8")
            result = acquire("HOB", Path(directory) / "out", fixture)
            self.assertEqual(len(result["candidates"]), 3)
            self.assertEqual(len(result["overview_images"]), 1)
            self.assertEqual(result["overview_images"][0]["download_status"], "not_attempted")
            self.assertEqual(result["review"]["image_text_ocr"], "not_performed")
            self.assertEqual(result["review"]["taxonomy_completeness"], "not_assessed")
            saved = json.loads((Path(directory) / "out" / "hob-catalog-candidate.json").read_text())
            self.assertEqual(saved["schema_version"], 1)
            self.assertEqual(saved["source"]["url"],
                             "https://magic.wizards.com/en/news/feature/the-hobbit-prerelease-guide")

    def test_missing_archetype_section_is_not_treated_as_empty_complete_catalog(self):
        parser = ArticleParser()
        parser.feed("<html><body><h2>Deckbuilding</h2><h3>White-Blue</h3></body></html>")
        self.assertEqual(extract_candidates(parser), [])


if __name__ == "__main__":
    unittest.main()
