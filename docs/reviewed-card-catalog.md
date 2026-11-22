# Reviewed card guide relationships

This catalog is a first reviewed pass over cards explicitly named in the official Wizards of the Coast Limited/prerelease guides for HOB, ECL, and TDM.

## Scope and evidence

- Every card has a source reference to the guide and archetype subsection where it is named.
- Archetype relationships are recorded only where the guide explicitly connects the card to that archetype's plan.
- The role labels (`signpost`, `enabler`, `payoff`, `supporting`) are Oculus editorial classifications of those explicit descriptions, not Wizards terminology except where the guide itself calls out signpost uncommons.
- A featured card under an archetype heading is recorded as `signpost` only when it is the guide's highlighted archetype card; this is not a claim about rarity or actual draft performance.
- TDM's guide discusses the five three-color clans in detail. It does not provide equivalent detailed card lists for all five two-color themes, so this first pass does not invent those relationships.
- General removal/threat examples and curve-only examples are not assigned archetype relationships by this pass.
- This is not a complete set card database. It is a source-backed starting catalog for review and enrichment.

## Source guides

- HOB: [Magic: The Gathering | The Hobbit Prerelease Guide](https://magic.wizards.com/en/news/feature/the-hobbit-prerelease-guide)
- ECL: [Lorwyn Eclipsed Prerelease Guide](https://magic.wizards.com/en/news/feature/lorwyn-eclipsed-prerelease-guide)
- TDM: [Tarkir: Dragonstorm Prerelease Guide](https://magic.wizards.com/en/news/feature/tarkir-dragonstorm-prerelease-guide)

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
