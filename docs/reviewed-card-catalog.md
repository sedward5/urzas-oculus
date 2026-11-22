# Reviewed card catalog

Urza's Oculus keeps card identity separate from archetype relationships.

## Source of truth

`scripts/data/reviewed_cards.json` is the human-maintained input. It contains cards selected for review in each set. Each card entry begins with an exact card name and may include a Scryfall UUID to disambiguate printings.

Supported relationship roles:

- `signpost`: explicitly points toward an archetype.
- `enabler`: helps turn on an archetype mechanic or plan.
- `payoff`: rewards the archetype's plan.
- `supporting`: contributes to the plan without being a defining signpost, enabler, or payoff.

Each relationship includes an archetype ID, review status (`needs_review`, `reviewed`, or `rejected`), and evidence. A relationship cannot be marked reviewed without evidence.

## Enrich Scryfall metadata

After adding exact card names to a set's `cards` array:

```sh
python3 scripts/enrich_reviewed_cards.py --set-code HOB --output /tmp/hob-card-catalog.json
```

Or enrich all configured sets:

```sh
python3 scripts/enrich_reviewed_cards.py --output /tmp/card-catalog-candidate.json
```

The script uses Scryfall's exact-name endpoint scoped to the set, or a supplied Scryfall UUID. It validates the returned name and set. It preserves Scryfall and Oracle UUIDs, collector number, rarity, mana cost/value, type line, rules text, colors, keywords, image URIs, and per-face images for double-faced cards.

Requests are spaced by 100 ms. Output is a candidate artifact; the tool never updates the reviewed source file.

## Evidence boundaries

- Article co-occurrence does not establish archetype membership.
- A card's color identity does not establish its role.
- Oracle text or keyword matching does not establish its role.
- The resolver enriches identity and presentation metadata only. It copies relationship records without changing them.
- A reviewed relationship requires explicit evidence and review status.
- Scryfall metadata is attributed to Scryfall; Wizards article evidence remains separately attributed to Wizards.

## Website and app consumption

Join the reviewed archetype taxonomy and card catalog by set code, archetype ID, and Scryfall UUID. Display card names and image URLs from resolved Scryfall records, not hand-built URLs or name-only lookups.
