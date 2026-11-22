import unittest
from scripts.enrich_reviewed_cards import CatalogError, card_metadata, enrich, validate_catalog

def payload(name="Test Card", set_code="HOB"):
    return {"id":"00000000-0000-0000-0000-000000000001","oracle_id":"00000000-0000-0000-0000-000000000002",
            "name":name,"set":set_code.lower(),"set_name":"The Hobbit","collector_number":"123",
            "rarity":"uncommon","mana_cost":"{1}{W}","cmc":2,"type_line":"Creature — Human",
            "oracle_text":"Vigilance","colors":["W"],"color_identity":["W"],"keywords":["Vigilance"],
            "image_uris":{"small":"https://img.test/small.jpg","normal":"https://img.test/normal.jpg"},
            "scryfall_uri":"https://scryfall.com/card/hob/123"}

class ReviewedCardCatalogTests(unittest.TestCase):
    def test_enrichment_preserves_relationships_without_inference(self):
        relation={"archetype_id":"humans","role":"signpost","review_status":"needs_review","evidence":[]}
        catalog={"schema_version":1,"sets":{"HOB":{"cards":[{"name":"Test Card","relationships":[relation],
                 "source_references":[{"type":"article","url":"https://example.test"}]}]}}}
        card=enrich(catalog,"HOB",fetcher=lambda _:payload(),delay_seconds=0)["sets"]["HOB"]["cards"][0]
        self.assertEqual(card["scryfall_id"],payload()["id"])
        self.assertEqual(card["image_uris"]["normal"],"https://img.test/normal.jpg")
        self.assertEqual(card["relationships"],[relation])

    def test_rejects_wrong_set(self):
        with self.assertRaisesRegex(CatalogError,"Set mismatch"):
            card_metadata(payload(set_code="ECL"),"HOB","Test Card")

    def test_rejects_wrong_name(self):
        with self.assertRaisesRegex(CatalogError,"Name mismatch"):
            card_metadata(payload(name="Different Card"),"HOB","Test Card")

    def test_reviewed_relationship_requires_evidence(self):
        catalog={"schema_version":1,"sets":{"HOB":{"cards":[{"name":"Test Card","relationships":[{
            "archetype_id":"humans","role":"payoff","review_status":"reviewed","evidence":[]}]}]}}}
        with self.assertRaisesRegex(CatalogError,"needs evidence"): validate_catalog(catalog)

    def test_rejects_unknown_role(self):
        catalog={"schema_version":1,"sets":{"HOB":{"cards":[{"name":"Test Card","relationships":[{
            "archetype_id":"humans","role":"bomb","review_status":"needs_review","evidence":[]}]}]}}}
        with self.assertRaisesRegex(CatalogError,"Unsupported card role"): validate_catalog(catalog)

    def test_double_faced_card_images_are_preserved(self):
        face={"id":payload()["id"],"name":"Front // Back","set":"hob","card_faces":[
            {"name":"Front","image_uris":{"normal":"https://img.test/front.jpg"}},
            {"name":"Back","image_uris":{"normal":"https://img.test/back.jpg"}}]}
        images=card_metadata(face,"HOB","Front // Back")["image_uris"]["faces"]
        self.assertEqual(images[1]["image_uris"]["normal"],"https://img.test/back.jpg")

if __name__ == "__main__": unittest.main()
