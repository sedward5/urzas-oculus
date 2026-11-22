#!/usr/bin/env python3
"""Resolve manually curated set-card identities against Scryfall.

This tool enriches card identity and presentation metadata only. It never
infers archetype relationships from article co-occurrence, color identity,
oracle text, or card names.
"""
from __future__ import annotations
import argparse
import json
import re
import time
from pathlib import Path
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

DEFAULT_CATALOG = Path(__file__).parent / "data" / "reviewed_cards.json"
ARCHETYPE_CATALOG = Path(__file__).parent / "data" / "reviewed_archetypes.json"
USER_AGENT = "UrzasOculusCardCatalog/0.1 (+https://github.com/sedward5/urzas-oculus)"
ALLOWED_ROLES = {"signpost", "enabler", "payoff", "supporting"}

class CatalogError(ValueError):
    pass

def normalize_name(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip().casefold()

def fetch_json(url: str, timeout: int = 30) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        if response.status != 200:
            raise CatalogError(f"Scryfall returned HTTP {response.status}: {url}")
        return json.loads(response.read().decode("utf-8"))

def validate_catalog(catalog: dict) -> None:
    archetypes = json.loads(ARCHETYPE_CATALOG.read_text(encoding="utf-8"))["sets"]
    if catalog.get("schema_version") != 1 or not isinstance(catalog.get("sets"), dict):
        raise CatalogError("Expected reviewed card catalog schema_version 1 with a sets object.")
    for set_code, set_record in catalog["sets"].items():
        if not re.fullmatch(r"[A-Z0-9]{3,5}", set_code):
            raise CatalogError(f"Invalid set code: {set_code}")
        cards = set_record.get("cards")
        if not isinstance(cards, list):
            raise CatalogError(f"{set_code}.cards must be an array.")
        seen: set[str] = set()
        for card in cards:
            name = card.get("name")
            if not isinstance(name, str) or not name.strip():
                raise CatalogError(f"{set_code} contains a card without a name.")
            key = card.get("scryfall_id") or normalize_name(name)
            if key in seen:
                raise CatalogError(f"{set_code} contains duplicate card identity: {name}")
            seen.add(key)
            for relationship in card.get("relationships", []):
                if relationship.get("role") not in ALLOWED_ROLES:
                    raise CatalogError(f"Unsupported card role for {name}: {relationship.get('role')}")
                archetype_id = relationship.get("archetype_id")
                if not archetype_id:
                    raise CatalogError(f"Relationship for {name} needs an archetype_id.")
                valid_ids = {item["id"] for item in archetypes.get(set_code, {}).get("archetypes", [])}
                if archetype_id not in valid_ids:
                    raise CatalogError(f"Unknown {set_code} archetype ID for {name}: {archetype_id}")
                if relationship.get("review_status") not in {"needs_review", "reviewed", "rejected"}:
                    raise CatalogError(f"Relationship for {name} needs an explicit review_status.")
                if relationship.get("review_status") == "reviewed" and not relationship.get("evidence"):
                    raise CatalogError(f"Reviewed relationship for {name} needs evidence.")

def image_uris(payload: dict) -> dict:
    images = payload.get("image_uris") or {}
    if images:
        return {key: images[key] for key in ("small", "normal", "large", "png", "art_crop", "border_crop") if images.get(key)}
    faces = payload.get("card_faces") or []
    return {"faces": [{"name": face.get("name"), "image_uris": image_uris(face)}
                      for face in faces if face.get("image_uris")]}

def card_metadata(payload: dict, expected_set: str, expected_name: str) -> dict:
    actual_set = str(payload.get("set", "")).upper()
    if actual_set != expected_set:
        raise CatalogError(f"Set mismatch for {expected_name}: expected {expected_set}, got {actual_set or 'missing'}.")
    actual_name = payload.get("name", "")
    if normalize_name(actual_name) != normalize_name(expected_name):
        raise CatalogError(f"Name mismatch: expected {expected_name!r}, got {actual_name!r}.")
    return {
        "scryfall_id": payload["id"], "oracle_id": payload.get("oracle_id"),
        "name": actual_name, "set_code": actual_set, "set_name": payload.get("set_name"),
        "collector_number": payload.get("collector_number"), "rarity": payload.get("rarity"),
        "layout": payload.get("layout"), "mana_cost": payload.get("mana_cost"),
        "mana_value": payload.get("cmc"), "type_line": payload.get("type_line"),
        "oracle_text": payload.get("oracle_text"), "colors": payload.get("colors", []),
        "color_identity": payload.get("color_identity", []), "keywords": payload.get("keywords", []),
        "image_uris": image_uris(payload), "scryfall_uri": payload.get("scryfall_uri"),
        "resolved_at_source": "Scryfall API",
    }

def resolve_card(card: dict, set_code: str, fetcher: Callable[[str], dict] = fetch_json) -> dict:
    if card.get("scryfall_id"):
        url = f"https://api.scryfall.com/cards/{card['scryfall_id']}"
    else:
        url = "https://api.scryfall.com/cards/named?" + urlencode({"exact": card["name"], "set": set_code.lower()})
    metadata = card_metadata(fetcher(url), set_code, card["name"])
    return {**metadata, "relationships": card.get("relationships", []),
            "source_references": card.get("source_references", []),
            "identity_review_status": "resolved_from_scryfall"}

def enrich(catalog: dict, set_code: str | None = None,
           fetcher: Callable[[str], dict] = fetch_json, delay_seconds: float = 0.1) -> dict:
    validate_catalog(catalog)
    selected = [set_code] if set_code else sorted(catalog["sets"])
    output = {"schema_version": 1,
              "source": {"name": "Scryfall", "attribution": "Card data and images © Scryfall"},
              "sets": {}}
    for code in selected:
        if code not in catalog["sets"]:
            raise CatalogError(f"Set {code} is not present in the reviewed card catalog.")
        enriched = []
        for index, card in enumerate(catalog["sets"][code]["cards"]):
            if index and delay_seconds:
                time.sleep(delay_seconds)
            enriched.append(resolve_card(card, code, fetcher))
        output["sets"][code] = {"cards": enriched}
    return output

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", type=Path, default=Path("card-catalog-candidate.json"))
    parser.add_argument("--set-code", choices=["HOB", "ECL", "TDM"])
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    result = enrich(catalog, args.set_code)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({code: len(record["cards"]) for code, record in result["sets"].items()}, indent=2))

if __name__ == "__main__":
    try:
        main()
    except (CatalogError, HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        raise SystemExit(f"Card catalog enrichment failed: {error}")
