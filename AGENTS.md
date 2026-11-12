# Instructions for coding agents

## Project authority

Read `docs/PROJECT_STEERING.md` and `docs/ARCHITECTURE.md` before making
architectural changes. These documents are the project's source of truth.

## Core constraints

- Target native macOS 14 or newer.
- Use Swift and SwiftUI.
- Keep OCR, recognition, draft state, and scoring deterministic and local.
- Do not introduce runtime AI inference, cloud inference, or paid APIs.
- Do not automate clicks or input into MTG Arena.
- Do not introduce overlays or require administrator privileges.
- Keep the user in control of all draft decisions.

## Engineering expectations

- Prefer small, independently testable components.
- Separate raw observations from interpreted card identities.
- Treat draft history as the authoritative record of state.
- Make uncertainty explicit; do not silently guess card identities.
- Preserve provenance and version information for reference datasets.
- Add or update tests with behavior changes.
- Avoid speculative abstractions before a real requirement exists.
- Document significant architectural decisions.

## Workflow

- Run `swift test` on a compatible macOS environment.
- Keep pull requests focused.
- Explain assumptions and known limitations.
- Never claim a feature is implemented when it is only scaffolded.
