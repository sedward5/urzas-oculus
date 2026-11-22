import json
import tempfile
import unittest
from pathlib import Path

from scripts.acquire_published_archetypes import (
    ArticleParser, acquire, extract_candidates, reviewed_candidates,
)

FIXTURE = """<!doctype html><html><head><title>Sample Prerelease Guide</title></head>
<body><main><h2>Draft Archetypes</h2>
<h3>White-Blue Humans</h3><p>Draw cards and make tokens.</p>
<h3>Black-Red Goblins</h3><p>Build an Army token.</p>
<h3>Magic Rules Blog: Mana Abilities</h3>
<h3>Collecting Nauctis: The Sunken Realm | A First Look</h3>
<h3>IDIC: Infinite Diversity in Infinite Combinations</h3>
<h3>Abzan Endure</h3><p>Three-color strategy.</p>
<h2>Other Limited Notes</h2><p>Not an archetype.</p>
<img alt="Draft Archetypes Overview" src="/images/archetypes.jpg">
</main></body></html>"""


class PublishedArchetypeAcquisitionTests(unittest.TestCase):
    def test_heading_extractor_accepts_only_explicit_two_color_headings(self):
        parser = ArticleParser()
        parser.feed(FIXTURE)
        candidates = extract_candidates(parser)
        self.assertEqual([item["display_name"] for item in candidates], ["Humans", "Goblins"])
        self.assertEqual([item["published_color_identity"] for item in candidates], ["WU", "BR"])

    def test_reviewed_catalog_contains_expected_taxonomies(self):
        expected = {"HOB": (5, {"two_color"}), "ECL": (5, {"two_color"}),
                    "TDM": (10, {"three_color_clan", "two_color_theme"})}
        for set_code, (count, types) in expected.items():
            candidates = reviewed_candidates(set_code)
            self.assertEqual(len(candidates), count)
            self.assertEqual({item["archetype_type"] for item in candidates}, types)
            self.assertTrue(all(item["review_status"] == "reviewed" for item in candidates))
            self.assertTrue(all(item["published_color_identity"] for item in candidates))
            self.assertTrue(all(not item["signpost_card_references"] for item in candidates))
            self.assertTrue(all(not item["supporting_card_references"] for item in candidates))

    def test_tdm_keeps_overlapping_clans_and_two_color_themes_distinct(self):
        candidates = reviewed_candidates("TDM")
        self.assertEqual(sum(item["archetype_type"] == "three_color_clan" for item in candidates), 5)
        self.assertEqual(sum(item["archetype_type"] == "two_color_theme" for item in candidates), 5)
        self.assertIn("WBG", [item["published_color_identity"] for item in candidates])
        self.assertIn("BR", [item["published_color_identity"] for item in candidates])

    def test_acquisition_uses_reviewed_catalog_and_writes_real_newlines(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "article.html"
            fixture.write_text(FIXTURE, encoding="utf-8")
            output = Path(directory) / "out"
            result = acquire("HOB", output, fixture)
            self.assertEqual(len(result["candidates"]), 5)
            self.assertEqual(len(result["observed_article_heading_candidates"]), 2)
            self.assertEqual(result["taxonomy"]["status"], "reviewed")
            self.assertEqual(result["review"]["taxonomy_completeness"], "manually_reviewed")
            saved = json.loads((output / "hob-catalog-candidate.json").read_text())
            self.assertEqual(saved["schema_version"], 2)
            notes = (output / "hob-source-notes.md").read_text()
            self.assertIn("\n## Reviewed archetypes\n", notes)
            self.assertNotIn("\\n## Reviewed archetypes", notes)

    def test_missing_archetype_headings_do_not_invalidate_reviewed_catalog(self):
        parser = ArticleParser()
        parser.feed("<html><body><h2>Deckbuilding</h2><h3>White-Blue</h3></body></html>")
        self.assertEqual(extract_candidates(parser), [])
        self.assertEqual(len(reviewed_candidates("TDM")), 10)


if __name__ == "__main__":
    unittest.main()
