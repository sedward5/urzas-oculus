# Urza's Oculus

**An arcane instrument for seeing the shape of a draft.**

Urza's Oculus is an independent native macOS companion project for Magic: The Gathering Arena drafting. The long-term goal is to combine reliable draft observation, explicit draft history, versioned reference data, and explainable recommendations.

The current app is a **Phase 0 ScreenCaptureKit feasibility prototype**, not a complete draft tracker or recommendation companion.

![Urza's Oculus app icon](Resources/AppIcon.png)

## Current status

The app can enumerate visible, shareable macOS windows; suggest likely iPhone Mirroring windows using an advisory heuristic; let you select a target; capture a still image; and capture a bounded three-second sequence (up to four frames per second, maximum twenty frames).

**The next milestone is real-world validation on the target Mac.** Use Capture Lab during a representative Arena draft. Review window selection, scrolling, pack transitions, frame dimensions/cadence, permission behavior, and card-text legibility before beginning substantial OCR work. CI can now capture a deterministic Draft Cockpit screenshot for visual review, but that screenshot validates the static prototype—not a live draft workflow.

**Not implemented or integrated:** OCR, card recognition, automatic draft observation, persistent user-facing draft tracking, and live pick recommendations. A static Draft Cockpit UI prototype exists to review product hierarchy and interaction concepts; it is not connected to capture, recognition, persistence, or scoring.

## What exists today

| Area | Status |
|---|---|
| macOS app and ScreenCaptureKit prototype | Implemented; real-world validation pending |
| Draft Cockpit UI | Static-data interaction prototype; not connected to domain services |
| RecognitionEngine | Placeholder; OCR/card recognition not implemented |
| DraftEngine | Append-only event model, validation, and replay tests; no persistence or capture integration |
| Scryfall reference data | SQLite schema, importer, and reviewed card catalog implemented |
| Wizards archetype catalog | Reviewed HOB/ECL/TDM taxonomies and 62 source-backed card relationships |
| 17Lands acquisition and parsing | Public archive discovery, download, and CSV parsing implemented |
| 17Lands metric aggregation | Game/draft aggregation with fixtures and HOB archive validation |
| 17Lands game eligibility | Open correctness question; exact parity is not claimed |
| Recommendation readiness | Implemented; requires compatible draft and game snapshots |
| Recommendation evaluator | Deterministic standalone GIH WR baseline in shared Swift core |
| Synergy, archetype, curve, deck-needs scoring | Not implemented |
| Website | Hugo site deployed via Cloudflare Pages |
| Capture-to-recommendation workflow | Not integrated |

GIH observations are copy-weighted, not independent game samples. ALSA and ATA are context only and do not affect baseline ranking. See [17Lands metric semantics](docs/17lands-metric-semantics.md) and [project state](docs/PROJECT_STATE.md).

## Principles

- **Local first:** captured frames and draft observations stay local. No cloud inference or runtime AI dependency.
- **Player controlled:** Oculus does not click, type, select cards, or automate Arena.
- **Deterministic and explainable:** recommendation logic lives in one testable Swift core.
- **Draft history is authoritative:** the drafted pool is reconstructed from explicit events and corrections.
- **Honest about evidence:** provenance, sample sizes, missing data, readiness, and limitations remain visible.
- **Incremental:** validate risky assumptions before building dependent features.

## Install the prototype

Download the [latest macOS DMG](https://github.com/sedward5/urzas-oculus/releases/latest/download/UrzasOculus.dmg) or browse [all releases](https://github.com/sedward5/urzas-oculus/releases).

Open the DMG and drag **Urza's Oculus.app** to Applications. The app requires macOS 14 or later. Current builds are ad-hoc signed, not Developer ID signed or notarized, so macOS may display an unidentified-developer warning on first launch. See [distribution details](docs/DISTRIBUTION.md).

## Repository layout

```text
Sources/                 Swift app and core engines
Tests/                   Swift unit tests
scripts/                 Archive validation, enrichment, and packaging
docs/                    Architecture, decisions, data, steering, and roadmap
website/                 Hugo website
.github/workflows/       CI and explicit data/acquisition workflows
```

## Development

Requirements: macOS 14+ for the native app, a compatible Swift toolchain, Python 3 for scripts, and Hugo Extended 0.147.9 for the website.

On a compatible Mac, from the repository root:

```sh
swift test
swift run
./scripts/package-app.sh
```

The package script creates `dist/UrzasOculus-macos.zip` and `dist/UrzasOculus.dmg`.

Python tests:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Website:

```sh
cd website
hugo server
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [website setup](website/README.md).

## Data sources and attribution

- [Scryfall](https://scryfall.com) provides card metadata and printing identifiers. Respect its data and image policies.
- [17Lands](https://www.17lands.com) provides public Limited datasets and metric definitions. Preserve provenance and attribution; public datasets are generally CC BY 4.0 unless otherwise noted.
- Magic: The Gathering and MTG Arena are trademarks of Wizards of the Coast. Urza's Oculus is independent and is not affiliated with or endorsed by Wizards of the Coast.

Third-party datasets, card images, and trademarks are not relicensed by this repository's software license.

## Documentation

- [Project state and accumulated decisions](docs/PROJECT_STATE.md)
- [Roadmap and implementation status](docs/ROADMAP.md)
- [Project steering](docs/PROJECT_STEERING.md)
- [Draft Cockpit UX specification](docs/DRAFT_COCKPIT_UX.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Architecture decision records](docs/DECISIONS.md)
- [Technical capture spike](docs/TECHNICAL_SPIKE.md)
- [Data schema](docs/DATA_SCHEMA.md)
- [17Lands metric semantics audit](docs/17lands-metric-semantics.md)
- [Reviewed card catalog and methodology](docs/reviewed-card-catalog.md)
- [Data analysis and production plan](docs/ANALYSIS_AND_PRODUCTION_PLAN.md)
- [macOS distribution](docs/DISTRIBUTION.md)
- [Set discovery and acquisition](docs/SET_DISCOVERY_AND_ACQUISITION.md)
- [Brand and visual style guide](docs/BRANDING.md)

## License

Source code is licensed under GNU GPL v3.0 only. See [LICENSE](LICENSE).
