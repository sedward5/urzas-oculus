# Contributing

Thanks for your interest. Oculus is an early-stage project; careful validation is more valuable than adding features quickly.

## Before starting

Read [AGENTS.md](AGENTS.md), [project steering](docs/PROJECT_STEERING.md), [architecture](docs/ARCHITECTURE.md), [decisions](docs/DECISIONS.md), and the [roadmap](docs/ROADMAP.md). Check existing issues and pull requests before starting overlapping work.

## Development requirements

- Native app: macOS 14+ and a compatible Swift toolchain.
- Website: Hugo Extended 0.147.9 (see [website/README.md](website/README.md)).
- Scripts: Python 3.

Run relevant checks from the repository root:

```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py'
./scripts/package-app.sh
```

For website changes:

```sh
cd website
hugo --minify --panicOnWarning
```

Only run checks relevant to your change locally. CI applies path-based validation. Native Swift behavior must be validated on macOS.

## Engineering expectations

- Keep capture, recognition, draft history, reference data, and scoring independently testable.
- Recognition results are proposals, not authoritative draft events.
- Draft history is append-only; corrections are new events.
- Keep recommendation logic in the shared Swift core; do not duplicate it in website JavaScript or TypeScript.
- Preserve dataset scope, snapshot identity, source update time, and local acquisition time.
- Missing values remain missing, never zero.
- Do not claim exact 17Lands parity while whole-game eligibility remains unresolved.
- Do not add runtime AI, cloud inference, paid APIs, or network dependencies to the active-draft workflow.
- Never automate Arena interactions or selections.
- Do not commit private screen recordings, personal screen contents, credentials, or local database files.

## Pull request checklist

- [ ] Explain the problem and intended behavior.
- [ ] Identify whether the change is implemented, experimental, or documentation-only.
- [ ] Add or update deterministic tests/fixtures where appropriate.
- [ ] Run relevant checks, or explain why they could not be run.
- [ ] Update roadmap/architecture/decisions when behavior or plans change.
- [ ] Document known limitations and data provenance.
- [ ] Confirm no private captures, secrets, or generated build artifacts are included.

## Data and intellectual property

Respect Scryfall's data/image policies and 17Lands attribution and license terms. The repository's GPL does not relicense third-party card data, card art, or trademarks. Do not add Magic card artwork as generic project branding.

For substantial architecture changes, open an issue or draft PR first and explain the evidence and trade-offs. Record significant decisions in docs/DECISIONS.md.
