import copy
import unittest

from scripts.promote_scryfall_enrichment import PromotionError, merge_catalog


def reviewed_catalog():
    return {
        "schema_version": 1,
        "description": "Human-reviewed source.",
        "sets": {"ABC": {"cards": [{
            "name": "Example // Back",
            "relationships": [{"archetype_id": "test", "role": "payoff",
                               "review_status": "reviewed", "evidence": "Reviewed evidence."}],
            "source_references": [{"source": "Wizards", "url": "https://example.test"}],
        }]}},
    }


def enriched_catalog():
    return {
        "schema_version": 1,
        "source": {"name": "Scryfall"},
        "sets": {"ABC": {"cards": [{
            "name": "Example // Back",
            "set_code": "ABC",
            "identity_review_status": "resolved_from_scryfall",
            "scryfall_id": "card-id",
            "scryfall_name": "Example // Back",
            "scryfall_uri": "https://scryfall.com/card/abc/1/example",
            "image_uris": {"normal": "https://cards.scryfall.io/normal/example.jpg"},
            "rarity": "uncommon",
        }]}},
    }


class PromoteScryfallEnrichmentTests(unittest.TestCase):
    def test_merges_metadata_without_changing_reviewed_relationships(self):
        reviewed = reviewed_catalog()
        original_relationships = copy.deepcopy(reviewed["sets"]["ABC"]["cards"][0]["relationships"])
        result = merge_catalog(reviewed, enriched_catalog())
        card = result["sets"]["ABC"]["cards"][0]
        self.assertEqual(card["relationships"], original_relationships)
        self.assertEqual(card["source_references"], reviewed["sets"]["ABC"]["cards"][0]["source_references"])
        self.assertEqual(card["image_uris"]["normal"], "https://cards.scryfall.io/normal/example.jpg")
        self.assertEqual(result["description"], "Human-reviewed source.")

    def test_rejects_missing_card(self):
        candidate = enriched_catalog()
        candidate["sets"]["ABC"]["cards"] = []
        with self.assertRaisesRegex(PromotionError, "card identity mismatch"):
            merge_catalog(reviewed_catalog(), candidate)

    def test_rejects_set_mismatch(self):
        candidate = enriched_catalog()
        candidate["sets"]["ABC"]["cards"][0]["set_code"] = "XYZ"
        with self.assertRaisesRegex(PromotionError, "set code mismatch"):
            merge_catalog(reviewed_catalog(), candidate)

    def test_rejects_unresolved_identity(self):
        candidate = enriched_catalog()
        candidate["sets"]["ABC"]["cards"][0]["identity_review_status"] = "unresolved"
        with self.assertRaisesRegex(PromotionError, "not resolved"):
            merge_catalog(reviewed_catalog(), candidate)


if __name__ == "__main__":
    unittest.main()
