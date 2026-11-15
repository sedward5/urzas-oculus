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


## Baseline evaluator contract

`ScoringEngine.evaluate` is a pure Swift-core API. It accepts a dataset
request, the shared readiness result, explicit card/performance candidates,
and a versioned scoring configuration. It returns a deterministic ranking,
excluded-candidate reasons, explanations, dataset snapshot identity, engine
version, scoring-configuration version, and result schema version.

The initial score is regularized GIH WR. The caller must provide the overall
win-rate baseline for the same set/event/user-group dataset and a versioned
prior weight. The configuration carries the baseline dataset key, and the
engine rejects a key that differs from the evaluation request. The prior
weight is a tuning parameter, not an independent sample count. The complete
configuration is included in the Codable result for artifact provenance.
ALSA and ATA are returned as context but do not affect ranking in this first
version.

The evaluator rejects unready data, a readiness scope mismatch, candidates
from another set/event/user-group/color scope, metrics from another snapshot,
and candidates without a usable GIH count/rate. It does not silently fall back
to a different dataset or score missing metrics as zero.

The macOS app and CI must call this same API. The web app consumes published
results and must not reproduce this calculation in JavaScript or TypeScript.
