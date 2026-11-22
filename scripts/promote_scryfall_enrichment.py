#!/usr/bin/env python3
"""Promote a validated Scryfall enrichment artifact into the reviewed catalog.

The human-reviewed card relationships and source evidence remain authoritative.
Only Scryfall identity, rules, and presentation metadata are copied.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / "scripts/data/reviewed_cards.json"
SYNC_SCRIPT = ROOT / "scripts/sync_reviewed_card_catalog.py"
METADATA_FIELDS = (
    "scryfall_id", "oracle_id", "scryfall_name", "set_code", "set_name",
    "collector_number", "rarity", "layout", "mana_cost", "mana_value",
    "type_line", "oracle_text", "colors", "color_identity", "keywords",
    "image_uris", "scryfall_uri", "resolved_at_source",
    "identity_review_status",
)


class PromotionError(ValueError):
    pass


def merge_catalog(reviewed: dict, enriched: dict) -> dict:
    if reviewed.get("schema_version") != 1 or enriched.get("schema_version") != 1:
        raise PromotionError("Unsupported catalog schema version.")
    reviewed_sets = reviewed.get("sets", {})
    enriched_sets = enriched.get("sets", {})
    if set(reviewed_sets) != set(enriched_sets):
        raise PromotionError("Candidate set codes do not exactly match the reviewed catalog.")

    result = json.loads(json.dumps(reviewed))
    total = 0
    for code, reviewed_set in result["sets"].items():
        original_cards = reviewed_set.get("cards", [])
        candidate_cards = enriched_sets[code].get("cards", [])
        original_by_name = {card["name"]: card for card in original_cards}
        candidate_by_name = {card["name"]: card for card in candidate_cards}
        if len(original_by_name) != len(original_cards):
            raise PromotionError(f"{code}: duplicate names in reviewed catalog.")
        if len(candidate_by_name) != len(candidate_cards):
            raise PromotionError(f"{code}: duplicate names in enrichment candidate.")
        if set(original_by_name) != set(candidate_by_name):
            missing = sorted(set(original_by_name) - set(candidate_by_name))
            extra = sorted(set(candidate_by_name) - set(original_by_name))
            raise PromotionError(f"{code}: card identity mismatch; missing={missing}, extra={extra}.")

        for name, card in original_by_name.items():
            metadata = candidate_by_name[name]
            if str(metadata.get("set_code", "")).upper() != code:
                raise PromotionError(f"{code}/{name}: Scryfall set code mismatch.")
            if metadata.get("identity_review_status") != "resolved_from_scryfall":
                raise PromotionError(f"{code}/{name}: identity is not resolved.")
            if not metadata.get("scryfall_id") or not metadata.get("scryfall_uri"):
                raise PromotionError(f"{code}/{name}: missing Scryfall identity or URI.")
            if not (metadata.get("image_uris") or {}).get("normal"):
                raise PromotionError(f"{code}/{name}: missing normal image URI.")
            for field in METADATA_FIELDS:
                if field in metadata:
                    card[field] = metadata[field]
            total += 1

    if total == 0:
        raise PromotionError("Refusing to promote an empty catalog.")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True,
                        help="reviewed_cards.enriched.json from a successful Actions artifact")
    args = parser.parse_args()
    reviewed = json.loads(CANONICAL.read_text(encoding="utf-8"))
    enriched = json.loads(args.candidate.read_text(encoding="utf-8"))
    promoted = merge_catalog(reviewed, enriched)
    CANONICAL.write_text(json.dumps(promoted, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8")
    print(f"Promoted Scryfall metadata for {sum(len(s['cards']) for s in promoted['sets'].values())} reviewed cards.")


if __name__ == "__main__":
    main()
