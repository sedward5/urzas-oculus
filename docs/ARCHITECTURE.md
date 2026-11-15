# Architecture

## Processing pipeline

    ScreenCaptureKit
           |
           v
      Observation
           |
           v
     Recognition Engine
           |
           v
      Interpreted Pack
           |
           v
       Draft Engine <---- User correction / selection
           |
           v
        Draft State
           |
           v
       Scoring Engine
           |
           v
      Recommendation

## CaptureEngine

Responsible for discovering and capturing the iPhone Mirroring window.

Responsibilities:
- ScreenCaptureKit integration.
- Window selection and capture lifecycle.
- Frame delivery and capture metadata.
- Permission and capture error reporting.

It must not make card identity or draft-state decisions.

## RecognitionEngine

Responsible for interpreting captured frames.

Responsibilities:
- OCR and visual feature extraction.
- Card candidate identification.
- Pack layout interpretation.
- Confidence and ambiguity reporting.

Recognition results should retain their relationship to the source
observation.

## DraftEngine

Owns the authoritative draft history.

Responsibilities:
- Pack and pick sequencing.
- Player selections.
- Drafted pool.
- State transitions and recovery.
- User corrections to recognized information.

Draft history should be sufficient to reconstruct the current state.

## ScoringEngine

Evaluates available picks against the current draft context.

Responsibilities:
- Card evaluation.
- Synergy and archetype context.
- Curve and color considerations.
- Pick recommendations and explanations.

Scoring must be deterministic for a given state and data version.

## DataEngine

Owns reference data and normalization.

Potential sources:
- Scryfall card records.
- 17Lands card and game data.

Data must be versioned, locally available, and traceable to its source.
Avoid making a live network request during a pick.

## CollectionEngine

Provides optional collection context. It must not be required for the
core draft workflow.

## Data flow rules

- Raw observations are immutable inputs to recognition.
- Recognition output is not automatically trusted.
- User corrections become explicit draft events.
- Draft history is the source of truth.
- Scoring consumes state; it does not mutate it.
- Reference data versions should be recorded with scoring results.


## Shared recommendation execution

Recommendation evaluation belongs in the platform-independent Swift core. The macOS
application and headless batch/CI execution are adapters around that core, not separate
implementations. The evaluator accepts explicit draft context, normalized card data,
validated 17Lands metrics, and a versioned scoring configuration. It returns a
deterministic, schema-versioned result with explanations and provenance.

The core must not read environment variables, access the network, write publication
files, or depend on SwiftUI. A CI runner may acquire and validate datasets, invoke the
same evaluator for configured set/event combinations, and publish static JSON artifacts
for the web app. Publication is allowed only when the shared readiness evaluator reports
a complete compatible dataset. Local pick evaluation remains offline.
