# Urza's Oculus — Project Steering

## 1. Purpose

Urza's Oculus is a native macOS companion application that assists a
player drafting Magic: The Gathering Arena on an iPhone through macOS
iPhone Mirroring.

The application observes the mirrored draft, identifies the current
pack and its cards, tracks the player's selections, and provides
algorithmic pick recommendations.

The player remains in control. The application advises; it does not
play the game.

## 2. Product principles

1. Local first: capture, OCR, recognition, state tracking, and scoring
   happen locally.
2. Deterministic: given the same observations, draft state, and data
   versions, scoring should produce the same result.
3. Explainable: recommendations should expose the factors that
   contributed to a pick.
4. Non-invasive: the application is a companion window, not an
   overlay or input automation tool.
5. Resilient: uncertain recognition must not silently corrupt draft
   state.
6. Incremental: validate difficult technical assumptions before
   building dependent systems.

## 3. Platform and technology

- Native macOS application.
- Minimum target: macOS 14.
- Swift and SwiftUI.
- ScreenCaptureKit for screen capture.
- Vision and local image processing for OCR and recognition.
- Swift Package Manager as the initial build system.
- XcodeGen may be introduced when application packaging or project
  organization warrants it.
- Bundle identifier: com.local.urzas-oculus.

## 4. Explicit constraints

- No runtime AI or cloud inference.
- No paid APIs or required subscriptions.
- No server dependency for the core drafting workflow.
- No automated clicks, keyboard input, or game interaction.
- No overlays on top of the mirrored iPhone window.
- No administrator privileges.
- No collection or transmission of screen contents.

Public reference datasets may be downloaded or imported as explicit,
versioned data updates. Individual pick decisions must not depend on
live API calls.

## 5. Core workflow

1. Locate and capture the iPhone Mirroring window.
2. Observe the current draft screen.
3. Identify the pack and visible card candidates.
4. Associate recognized cards with authoritative card records.
5. Present uncertain recognition for user correction.
6. Record the selected card and advance draft state.
7. Evaluate remaining cards using the current draft context.
8. Present recommendations with useful explanations.

## 6. Architectural boundaries

- Capture produces observations, not card identities.
- Recognition interprets observations and reports confidence.
- DraftEngine owns the authoritative draft history and state.
- ScoringEngine consumes draft state and reference data. It does not
  mutate the draft.
- DataEngine owns reference data normalization, versioning, and
  provenance.
- CollectionEngine provides collection context without becoming the
  source of truth for draft history.

## 7. Initial milestone

The first milestone is a technical feasibility spike:

Can ScreenCaptureKit reliably capture the macOS iPhone Mirroring window
while preserving enough visual information for local OCR and card
recognition?

Do not build a large recognition or scoring system before answering
that question.

## 8. Definition of done

A change should include:

- A clear description of behavior.
- Tests for meaningful logic.
- Updated documentation where appropriate.
- No violation of the platform or privacy constraints.
- A successful macOS CI build and test run.
