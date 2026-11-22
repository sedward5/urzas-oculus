# Reviewed card catalog

Urza's Oculus keeps card identity separate from archetype relationships.

## Source of truth

`scripts/data/reviewed_cards.json` is the human-maintained input. It contains the cards selected for review in each set. Each card entry begins with an exact card name and may include a Scryfall UUID to disambiguate unusual printings.

The catalog supports four relationship roles:

- `signpost`: a card that explicitly points toward an archetype.
- `enabler`: a card that helps turn on an archetype mechanic or plan.
- `payoff`: a card that rewards the archetype's plan.
- `supporting`: a card that contributes to the plan without being a defining signpost, enabler, or payoff.

Each relationship is explicitly attached to an archetype ID and includes:
- `review_status`: `needs_review`, `reviewed`, or `rejected`.
- `evidence`: source references or review notes. A relationship cannot be marked reviewed without evidence.

## Enrich Scryfall metadata

After adding exact card names to the appropriate set's `cards` array, run:

```sh
python3 scripts/enrich_reviewed_cards.py --set-code HOB --output /tmp/hob-card-catalog.json
```

Or enrich every set:

```sh
python3 scripts/enrich_reviewed_cards.py --output /tmp/card-catalog-candidate.json
```

The script uses Scryfall's exact-name endpoint scoped to the set, or a supplied Scryfall UUID. It validates that the returned card name and set match the requested identity. It preserves Scryfall UUID, Oracle UUID, collector number, rarity, mana cost/value, type line, rules text, colors, keywords, image URIs, and per-face images for double-faced cards.

Scryfall requests are spaced by 100 ms. The script writes a candidate artifact; it does not silently update the reviewed source file.

## Evidence boundaries

- Article co-occurrence does not establish archetype membership.
- A card's color identity does not establish its role.
- Oracle text or keyword matching does not establish its role.
- The resolver enriches identity and presentation metadata only. It copies relationship records without changing them.
- A reviewed relationship requires explicit evidence and review status.
- Scryfall metadata is attributed to Scryfall. Wizards article evidence remains separately attributed to Wizards.

## Website and app consumption

The reviewed archetype taxonomy and card catalog are separate data sources. Website templates and the macOS app should join them by stable IDs: set code, archetype ID, and Scryfall UUID. Display card names and image URLs from the resolved Scryfall record, not hand-built URLs or name-only lookups.
