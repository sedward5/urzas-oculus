# Promoting Scryfall card enrichment

The enrichment workflow deliberately uploads a candidate artifact without changing the reviewed catalog. Promote a successful run through **Promote Scryfall Card Enrichment**. The initial catalog promotion uses successful enrichment run [45059767031](https://github.com/sedward5/urzas-oculus/actions/runs/45059767031), which resolved 62 reviewed cards across HOB, ECL, and TDM.

For this initial promotion, opening or updating the promotion PR automatically downloads run `45059767031`, validates it, and commits the result to the PR branch. This lets the full catalog diff be reviewed before merging.

For future promotions, after this workflow is present on the default branch, run it manually:

1. Open **Actions → Promote Scryfall Card Enrichment**.
2. Select the target branch.
3. Enter the successful enrichment run ID.
4. Run the workflow.

The workflow downloads that run's artifact, validates exact set/card coverage and Scryfall identity, then merges only Scryfall metadata into the human-reviewed catalog. It regenerates the website and native app copies.

The promotion never changes archetype relationships, evidence, or source references. It rejects missing/extra cards, set mismatches, unresolved identities, and missing image metadata. Re-running the same promotion is safe and produces no extra commit when nothing changed.

The native app already decodes the normal/large image URLs and Scryfall URI. The website already renders the normal image URL and Scryfall link. Updating the three catalog copies is therefore sufficient to expose the enrichment in both presentation layers.
