# Reviewed card guide relationships

This catalog is a first reviewed pass over cards explicitly named in the official Wizards of the Coast Limited/prerelease guides for HOB, ECL, and TDM.

## Scope and evidence

- Every card has a source reference to the guide and archetype subsection where it is named.
- Archetype relationships are recorded only where the guide explicitly connects the card to that archetype's plan.
- The role labels (`signpost`, `enabler`, `payoff`, `supporting`) are Oculus editorial classifications of those explicit descriptions, not Wizards terminology except where the guide itself calls out signpost uncommons.
- Featured cards are classified as `supporting` unless the guide explicitly describes a signpost role. The guide's featured-card callouts alone do not establish that a card is a signpost uncommon.
- TDM's guide discusses the five three-color clans in detail. It does not provide equivalent detailed card lists for all five two-color themes, so this first pass does not invent those relationships.
- General removal/threat examples and curve-only examples are not assigned archetype relationships by this pass.
- This is not a complete set card database. It is a source-backed starting catalog for review and enrichment.

## Source guides

- HOB: [Magic: The Gathering | The Hobbit Prerelease Guide](https://magic.wizards.com/en/news/feature/the-hobbit-prerelease-guide)
- ECL: [Lorwyn Eclipsed Prerelease Guide](https://magic.wizards.com/en/news/feature/lorwyn-eclipsed-prerelease-guide)
- TDM: [Tarkir: Dragonstorm Prerelease Guide](https://magic.wizards.com/en/news/feature/tarkir-dragonstorm-prerelease-guide)

## Current reviewed catalog status (2026-11-22)

The catalog currently contains 62 cards: HOB 26, ECL 19, and TDM 17. All 62 have Scryfall identities and card metadata/image URIs. Enrichment is a separate metadata operation; it does not infer, add, or modify archetype relationships. Relationship role totals are HOB: 8 enablers, 6 payoffs, 12 supporting; ECL: 8 enablers, 3 payoffs, 8 supporting; TDM: 4 enablers, 9 payoffs, 4 supporting. These roles are Oculus editorial classifications.

The canonical reviewed catalog is `scripts/data/reviewed_cards.json`; website and native app catalogs are synchronized from it. The promotion workflow promotes a specific enrichment artifact rather than editing the human-reviewed relationship source. See [promotion workflow](promoting-scryfall-enrichment.md).

## Enrich Scryfall metadata

After reviewing the names, resolve exact identities and fetch image/card metadata:

```sh
python3 scripts/enrich_reviewed_cards.py --set-code HOB --output /tmp/hob-card-catalog.json
python3 scripts/enrich_reviewed_cards.py --set-code ECL --output /tmp/ecl-card-catalog.json
python3 scripts/enrich_reviewed_cards.py --set-code TDM --output /tmp/tdm-card-catalog.json
```

The resolver validates exact name and set, then extracts Scryfall metadata. It does not alter relationship roles or evidence.

## Limitations

These guides are written primarily for Sealed/Prerelease instruction, even where they describe draft archetypes. They establish documented design intent and card roles, not Arena Draft pick order, card strength, or win-rate contribution. Empirical performance should be joined separately from 17Lands.
