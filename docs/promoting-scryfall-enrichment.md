# Promoting Scryfall card enrichment

The enrichment workflow deliberately uploads a candidate artifact without changing the reviewed catalog. After reviewing a successful run, promote it through the **Promote Scryfall Card Enrichment** workflow.

1. Open the successful **Scryfall Card Catalog Enrichment** run and copy its run ID.
2. Open **Actions → Promote Scryfall Card Enrichment**.
3. Select the branch containing the promotion PR (not `main`).
4. Enter the enrichment run ID and run the workflow.
5. The workflow downloads that run's artifact, validates exact set/card coverage and Scryfall identity, then merges only Scryfall metadata into the human-reviewed catalog.
6. It regenerates the website and native app copies and commits the result to the selected branch.

The promotion never changes archetype relationships, evidence, or source references. It rejects missing/extra cards, set mismatches, unresolved identities, and missing image metadata. Re-running the same promotion is safe and produces no extra commit when nothing changed.

The native app already decodes the normal/large image URLs and Scryfall URI. The website already renders the normal image URL and Scryfall link. Updating the three catalog copies is therefore sufficient to expose the enrichment in both presentation layers.
