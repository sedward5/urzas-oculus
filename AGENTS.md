# Instructions for coding agents

## Project authority

Before architectural changes, read:
- docs/PROJECT_STEERING.md
- docs/ARCHITECTURE.md
- docs/DECISIONS.md
- docs/ROADMAP.md
- CONTRIBUTING.md

These documents define project constraints and current implementation status.

## Current implementation reality

The app is a Phase 0 ScreenCaptureKit feasibility prototype. It can enumerate windows, suggest likely iPhone Mirroring windows, capture a selected still frame, and sample a bounded three-second sequence. Real-world capture validation remains pending.

Do not claim OCR, card recognition, integrated draft tracking, persistence, or live recommendations are shipped. Draft-event, data-import, readiness, and baseline-scoring foundations exist, but are not integrated into the capture workflow.

## Core constraints

- Target native macOS 14 or newer; use Swift and SwiftUI.
- Keep processing local, deterministic, and explainable.
- Do not introduce runtime AI inference, cloud inference, paid APIs, or a server dependency for the active-draft workflow.
- Never automate clicks, keyboard/touch input, selections, or overlays in MTG Arena.
- Never transmit captured screen contents or commit private recordings.
- Keep recognition observations separate from authoritative append-only draft events.
- Keep recommendation logic in the shared platform-independent Swift core. The website may display published artifacts but must not reimplement scoring.
- Preserve dataset scope, snapshot identity, provenance, and freshness. Missing values are not zero.
- Do not claim exact 17Lands parity; whole-game eligibility for inconsistent source games remains unresolved.
- Treat iPhone Mirroring as the initial capture source. Keep draft, data, and scoring domains independent of capture-source details.
- Update tests and documentation with meaningful behavior changes. Record significant decisions in docs/DECISIONS.md.

## Validation

- Swift changes: run swift test and package on macOS where applicable.
- Python scripts: run python3 -m unittest discover -s scripts -p 'test_*.py'.
- Website: use Hugo Extended 0.147.9 and run hugo --minify --panicOnWarning from website/.
- Do not claim a check passed without a result.
- Do not merge pull requests without explicit maintainer approval.
