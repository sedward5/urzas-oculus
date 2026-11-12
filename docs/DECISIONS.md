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
