#!/usr/bin/env python3
"""Resolve manually curated set-card identities against Scryfall.

Uses Scryfall's Collection endpoint in batches. Enrichment is presentation and
identity metadata only; it never infers archetype relationships.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_CATALOG = Path(__file__).parent / "data" / "reviewed_cards.json"
ARCHETYPE_CATALOG = Path(__file__).parent / "data" / "reviewed_archetypes.json"
USER_AGENT = "UrzasOculusCardCatalog/0.2 (+https://github.com/sedward5/urzas-oculus)"
COLLECTION_URL = "https://api.scryfall.com/cards/collection"
BATCH_SIZE = 75
REQUEST_DELAY_SECONDS = 1.0
MAX_ATTEMPTS = 4
ALLOWED_ROLES = {"signpost", "enabler", "payoff", "supporting"}


class CatalogError(ValueError):
    pass


def normalize_name(value: str) -> str:
    return re.sub(r"\\s+", " ", value).strip().casefold()


def retry_delay(error: HTTPError, attempt: int) -> float:
    """Honor Retry-After; otherwise use conservative bounded backoff."""
    retry_after = error.headers.get("Retry-After") if error.headers else None
    if retry_after:
        try:
            return max(1.0, float(retry_after))
        except ValueError:
            try:
                target = parsedate_to_datetime(retry_after)
                if target.tzinfo is None:
                    target = target.replace(tzinfo=timezone.utc)
                return max(1.0, (target - datetime.now(timezone.utc)).total_seconds())
            except (TypeError, ValueError, OverflowError):
                pass
    return 60.0 if error.code == 429 else min(2 ** attempt, 30.0)


def fetch_json(url: str, timeout: int = 30, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                if response.status != 200:
                    raise CatalogError(f"Scryfall returned HTTP {response.status}: {url}")
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            if error.code not in {429, 500, 502, 503, 504} or attempt == MAX_ATTEMPTS:
                raise
            delay = retry_delay(error, attempt)
            print(f"Scryfall HTTP {error.code}; retrying in {delay:.1f}s (attempt {attempt}/{MAX_ATTEMPTS - 1}).")
            time.sleep(delay)
        except (URLError, TimeoutError):
            if attempt == MAX_ATTEMPTS:
                raise
            delay = min(2 ** attempt, 30.0)
            print(f"Transient Scryfall connection error; retrying in {delay:.1f}s.")
            time.sleep(delay)
    raise CatalogError("Scryfall request exhausted retries.")


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


def payload_name_aliases(payload: dict) -> set[str]:
    """Return exact Scryfall card and face names for matching reviewed entries."""
    aliases = set()
    full_name = payload.get("name", "")
    if full_name:
        aliases.add(normalize_name(full_name))
        aliases.update(normalize_name(part) for part in full_name.split(" // ") if part.strip())
    for face in payload.get("card_faces") or []:
        face_name = face.get("name")
        if face_name:
            aliases.add(normalize_name(face_name))
    return aliases


def card_metadata(payload: dict, expected_set: str, expected_name: str) -> dict:
    actual_set = str(payload.get("set", "")).upper()
    if actual_set != expected_set:
        raise CatalogError(f"Set mismatch for {expected_name}: expected {expected_set}, got {actual_set or 'missing'}.")
    actual_name = payload.get("name", "")
    if normalize_name(expected_name) not in payload_name_aliases(payload):
        raise CatalogError(f"Name mismatch: expected {expected_name!r}, got {actual_name!r}.")
    return {
        "scryfall_id": payload["id"], "oracle_id": payload.get("oracle_id"),
        "name": expected_name, "scryfall_name": actual_name,
        "set_code": actual_set, "set_name": payload.get("set_name"),
        "collector_number": payload.get("collector_number"), "rarity": payload.get("rarity"),
        "layout": payload.get("layout"), "mana_cost": payload.get("mana_cost"),
        "mana_value": payload.get("cmc"), "type_line": payload.get("type_line"),
        "oracle_text": payload.get("oracle_text"), "colors": payload.get("colors", []),
        "color_identity": payload.get("color_identity", []), "keywords": payload.get("keywords", []),
        "image_uris": image_uris(payload), "scryfall_uri": payload.get("scryfall_uri"),
        "resolved_at_source": "Scryfall API",
    }


def _existing_metadata(existing: dict | None, set_code: str, card_name: str) -> dict | None:
    if not existing:
        return None
    for card in existing.get("sets", {}).get(set_code, {}).get("cards", []):
        if (card.get("identity_review_status") == "resolved_from_scryfall"
                and card.get("set_code") == set_code
                and normalize_name(card.get("name", "")) == normalize_name(card_name)
                and card.get("scryfall_id")):
            return card
    return None


def enrich(catalog: dict, set_code: str | None = None,
           fetcher: Callable[[str], dict] = fetch_json,
           delay_seconds: float = REQUEST_DELAY_SECONDS,
           existing: dict | None = None) -> dict:
    validate_catalog(catalog)
    selected = [set_code] if set_code else sorted(catalog["sets"])
    output = {"schema_version": 1,
              "source": {"name": "Scryfall", "attribution": "Card data and images © Scryfall"},
              "sets": {}}
    for code in selected:
        if code not in catalog["sets"]:
            raise CatalogError(f"Set {code} is not present in the reviewed card catalog.")
        source_cards = catalog["sets"][code]["cards"]
        resolved_by_name = {}
        pending = []
        reused = 0
        for card in source_cards:
            cached = _existing_metadata(existing, code, card["name"])
            if cached:
                resolved_by_name[normalize_name(card["name"])] = {
                    **{key: value for key, value in cached.items()
                       if key not in {"relationships", "source_references", "identity_review_status"}},
                    "relationships": card.get("relationships", []),
                    "source_references": card.get("source_references", []),
                    "identity_review_status": "resolved_from_scryfall",
                }
                reused += 1
            else:
                pending.append(card)
        chunks = [pending[index:index + BATCH_SIZE] for index in range(0, len(pending), BATCH_SIZE)]
        for chunk_index, chunk in enumerate(chunks):
            if chunk_index and delay_seconds:
                time.sleep(delay_seconds)
            identifiers = [{"name": card["name"], "set": code.lower()} for card in chunk]
            response = fetcher(COLLECTION_URL, payload={"identifiers": identifiers})
            not_found = response.get("not_found", [])
            if not_found:
                missing = [item.get("name", str(item)) for item in not_found]
                raise CatalogError(f"Scryfall could not resolve {code} card(s): {', '.join(missing)}")
            returned = response.get("data", [])
            by_name = {}
            for payload in returned:
                for key in payload_name_aliases(payload):
                    previous = by_name.get(key)
                    if previous is not None and previous.get("id") != payload.get("id"):
                        raise CatalogError(f"Scryfall returned ambiguous card/face name in {code}: {key}")
                    by_name[key] = payload
            for card in chunk:
                key = normalize_name(card["name"])
                payload = by_name.get(key)
                if payload is None:
                    raise CatalogError(f"Scryfall omitted {code} card from collection response: {card['name']}")
                metadata = card_metadata(payload, code, card["name"])
                resolved_by_name[key] = {
                    **metadata, "relationships": card.get("relationships", []),
                    "source_references": card.get("source_references", []),
                    "identity_review_status": "resolved_from_scryfall",
                }
        output["sets"][code] = {"cards": [resolved_by_name[normalize_name(card["name"])] for card in source_cards]}
        print(f"{code}: {len(source_cards)} cards; reused {reused}; queried {len(pending)}.")
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", type=Path, default=Path("card-catalog-candidate.json"))
    parser.add_argument("--set-code", choices=["HOB", "ECL", "TDM"])
    parser.add_argument("--existing", type=Path, help="Previously enriched candidate to reuse when identities match.")
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    existing = json.loads(args.existing.read_text(encoding="utf-8")) if args.existing and args.existing.exists() else None
    result = enrich(catalog, args.set_code, existing=existing)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({code: len(record["cards"]) for code, record in result["sets"].items()}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (CatalogError, HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        raise SystemExit(f"Card catalog enrichment failed: {error}")
