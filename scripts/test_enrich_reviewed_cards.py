import json
import unittest
from unittest.mock import patch

from scripts.enrich_reviewed_cards import (
    CatalogError, COLLECTION_URL, card_metadata, enrich, validate_catalog,
)


def payload(name="Test Card", set_code="HOB"):
    return {
        "id": "00000000-0000-0000-0000-000000000001",
        "oracle_id": "00000000-0000-0000-0000-000000000002",
        "name": name, "set": set_code.lower(), "set_name": "The Hobbit",
        "collector_number": "123", "rarity": "uncommon", "mana_cost": "{1}{W}",
        "cmc": 2, "type_line": "Creature — Human", "oracle_text": "Vigilance",
        "colors": ["W"], "color_identity": ["W"], "keywords": ["Vigilance"],
        "image_uris": {"small": "https://img.test/small.jpg", "normal": "https://img.test/normal.jpg"},
        "scryfall_uri": "https://scryfall.com/card/hob/123",
    }


def catalog_with(*cards):
    return {"schema_version": 1, "sets": {"HOB": {"cards": list(cards)}}}


class ReviewedCardCatalogTests(unittest.TestCase):
    def test_collection_batches_cards_and_preserves_relationships(self):
        relation = {"archetype_id": "humans", "role": "signpost", "review_status": "needs_review", "evidence": []}
        source = {"name": "Test Card", "relationships": [relation],
                  "source_references": [{"type": "article", "url": "https://example.test"}]}
        calls = []
        def fetch(url, payload=None):
            calls.append((url, payload))
            return {"data": [globals()["payload"]()], "not_found": []}
        result = enrich(catalog_with(source), "HOB", fetcher=fetch, delay_seconds=0)
        card = result["sets"]["HOB"]["cards"][0]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], COLLECTION_URL)
        self.assertEqual(calls[0][1]["identifiers"], [{"name": "Test Card", "set": "hob"}])
        self.assertEqual(card["scryfall_id"], payload()["id"])
        self.assertEqual(card["image_uris"]["normal"], "https://img.test/normal.jpg")
        self.assertEqual(card["relationships"], [relation])

    def test_reuses_matching_existing_metadata_without_request(self):
        source = {"name": "Test Card", "relationships": []}
        old = {**card_metadata(payload(), "HOB", "Test Card"),
               "relationships": [], "source_references": [],
               "identity_review_status": "resolved_from_scryfall"}
        existing = {"sets": {"HOB": {"cards": [old]}}}
        def fail_if_called(*args, **kwargs):
            raise AssertionError("cached card should not trigger a request")
        result = enrich(catalog_with(source), "HOB", fetcher=fail_if_called, existing=existing)
        self.assertEqual(result["sets"]["HOB"]["cards"][0]["scryfall_id"], old["scryfall_id"])

    def test_reports_collection_not_found(self):
        source = {"name": "Missing Card", "relationships": []}
        with self.assertRaisesRegex(CatalogError, "could not resolve HOB"):
            enrich(catalog_with(source), "HOB",
                   fetcher=lambda *args, **kwargs: {"data": [], "not_found": [{"name": "Missing Card"}]},
                   delay_seconds=0)

    def test_rejects_wrong_set(self):
        with self.assertRaisesRegex(CatalogError, "Set mismatch"):
            card_metadata(payload(set_code="ECL"), "HOB", "Test Card")

    def test_rejects_wrong_name(self):
        with self.assertRaisesRegex(CatalogError, "Name mismatch"):
            card_metadata(payload(name="Different Card"), "HOB", "Test Card")

    def test_reviewed_relationship_requires_evidence(self):
        catalog = catalog_with({"name": "Test Card", "relationships": [{
            "archetype_id": "humans", "role": "payoff", "review_status": "reviewed", "evidence": []
        }]})
        with self.assertRaisesRegex(CatalogError, "needs evidence"):
            validate_catalog(catalog)

    def test_rejects_unknown_archetype_id(self):
        catalog = catalog_with({"name": "Test Card", "relationships": [{
            "archetype_id": "not-a-hob-archetype", "role": "payoff",
            "review_status": "needs_review", "evidence": []
        }]})
        with self.assertRaisesRegex(CatalogError, "Unknown HOB archetype ID"):
            validate_catalog(catalog)

    def test_rejects_unknown_role(self):
        catalog = catalog_with({"name": "Test Card", "relationships": [{
            "archetype_id": "humans", "role": "bomb", "review_status": "needs_review", "evidence": []
        }]})
        with self.assertRaisesRegex(CatalogError, "Unsupported card role"):
            validate_catalog(catalog)

    def test_double_faced_card_images_are_preserved(self):
        face = {"id": payload()["id"], "name": "Front // Back", "set": "hob", "card_faces": [
            {"name": "Front", "image_uris": {"normal": "https://img.test/front.jpg"}},
            {"name": "Back", "image_uris": {"normal": "https://img.test/back.jpg"}},
        ]}
        images = card_metadata(face, "HOB", "Front // Back")["image_uris"]["faces"]
        self.assertEqual(images[1]["image_uris"]["normal"], "https://img.test/back.jpg")


if __name__ == "__main__":
    unittest.main()
