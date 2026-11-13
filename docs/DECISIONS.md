# Architecture Decision Records

## ADR-001: Native macOS application

**Status:** Accepted

Urza's Oculus is a native macOS companion application. Swift and SwiftUI
provide the application foundation, with ScreenCaptureKit and Vision
used for local capture and recognition.

## ADR-002: Local deterministic processing

**Status:** Accepted

The core workflow must not depend on runtime AI inference, cloud
inference, paid APIs, or a server.

The same draft state and data versions should produce repeatable
recommendations.

## ADR-003: Draft history is authoritative

**Status:** Accepted

Draft state is reconstructed from explicit draft events and user
corrections. Recognition is an input to the state machine, not the
authority on what the player selected.

## ADR-004: Validate capture before building dependent systems

**Status:** Accepted

ScreenCaptureKit compatibility with the iPhone Mirroring window is a
critical technical risk. Validate capture quality and permissions before
investing heavily in OCR, recognition, and scoring.

## ADR-005: Append-only draft events and deterministic replay

**Status:** Accepted

Draft history is an append-only sequence of typed events. The current
draft state is a deterministic projection of those events. A correction
is recorded as a new event that references the original pick event;
historical events are not rewritten.

A pack observation records the candidates at a specific pack/pick
position. A player pick must reference that observation and select one
of its candidates. Recognition is not connected directly to this
foundation; upstream code must explicitly submit observations, and the
player's selection remains a separate event.

The reducer validates event ordering and references. It does not assume
a fixed booster size or format-specific pack length. This keeps the
foundation suitable for multiple draft formats while enforcing that a
new observation cannot replace an unresolved pick.

Consequences:
- State can be reconstructed and audited by replaying history.
- Failed events do not partially mutate the engine.
- User corrections preserve the original record and their own reason.
- Persistence and recognition integration remain separate future work.
