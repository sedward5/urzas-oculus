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
prior weight. The configuration carries the baseline dataset key and game snapshot ID;
the engine rejects a baseline from another scope or snapshot. The prior
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

## Local recommendation adapter

`RecommendationService.evaluate` is the local DataEngine-to-ScoringEngine
adapter. Callers provide the exact candidate Scryfall printing IDs, dataset
scope, and explicit scoring configuration. The service:

- Checks game/draft dataset readiness before looking up candidates.
- Loads each printing from the local card store.
- Loads performance records using the requested set, event, user group,
  color filter, and card name.
- Rejects duplicate candidate IDs and unknown card IDs explicitly.
- Passes the assembled request to `ScoringEngine.evaluate`; it contains
  no ranking or scoring logic of its own.

The service does not invent or infer the format baseline. The game importer
persists an unweighted overall win rate from the same filtered game rows,
keyed by dataset and exact snapshot. The adapter requires the caller's
versioned scoring configuration to match that persisted value, dataset key,
and game snapshot; it rejects missing or mismatched baselines before card
lookup. Recognition and draft-state adapters will provide candidate IDs once
their integration is implemented. This service is independently testable
without screen capture, OCR, SwiftUI, or network access.



## Draft cockpit presentation and state

The user-facing workspace is organized around three projections of explicit domain state:

- **Current pack:** card instances observed from captured frames, recognition hypotheses/confidence, unresolved slots, and the current recommendation result.
- **Drafted pool:** cards derived only from confirmed pick events and subsequent corrections. Deck statistics are projections of this pool.
- **Strategic context:** archetype/color hypotheses and splash considerations, each with evidence, confidence, and the data/configuration version that produced it.

A separate pack-history projection retains prior pack observations and known wheel updates. It must distinguish cards explicitly picked by the player, cards observed on later wheel returns, and cards merely absent from a later frame. Absence is not proof of a particular selection by another drafter.

The session coordinator will orchestrate capture, recognition, user confirmation, event persistence, and scoring, but domain boundaries remain intact. Recognition hypotheses cannot directly add cards to the drafted pool. The user-confirmed pick becomes an append-only draft event; corrections append a compensating/correction event. The deck panel is a deterministic projection of the event history.

The intended workspace hierarchy and interaction contracts are specified in [DRAFT_COCKPIT_UX.md](DRAFT_COCKPIT_UX.md). The document describes desired behavior; it does not imply those UI features exist today.


## Prediction and card evaluation

The shared Swift core owns two separate scoring paths. `PredictiveScoringEngine` computes experimental pre-release dimensions from Scryfall card facts and explicit reviewed archetype relationships; it does not read 17Lands or rarity. `ScoringEngine` computes the empirical regularized GIH baseline from compatible 17Lands observations. Card identity, prediction, and observed performance remain separate. Structural role suggestions are review prompts, not confirmed classifications. Human review records remain an evidence layer and do not silently overwrite algorithmic outputs.

The `CardEvaluationTool` executable is a local batch adapter around this core. It accepts normalized `CardRecord` JSON and optional reviewed records, validates identity and evidence requirements, and emits deterministic suggestion/review JSON. It does not parse raw Scryfall bulk data or implement a second scoring engine. Future app and CI workflows must call the same core. Website pages may display immutable prediction and calibration artifacts but must not reproduce classification or evaluation logic.


## Predictive evaluation and calibration pipeline

The predictive model is a separate ScoringEngine mode from the live-draft GIH baseline. It must be deterministic, versioned, and runnable against current and historical sets. Inputs are normalized card facts, explicitly reviewed official set context, and a cutoff-bounded source manifest. Rarity is metadata only and must never enter a feature, rule, score, or recommendation path.

Prediction artifacts are immutable and identify model/configuration/engine/schema versions, set, evaluation timestamp, source cutoff, source snapshot IDs/hashes, and per-card explanations. Observed performance is stored separately and joined only by stable card identity and explicit set/event/user-group/color scope. Calibration reports compare distinct outcome families, including coverage, sample sizes, missingness, limitations, residuals, and outliers. Historical replay uses only inputs available by the declared cutoff. Model changes require a version bump and regression replay across historical sets.

The static website's archetype pages may display a published card-score artifact with the predictive dimensions and the separately scoped 17Lands regularized GIH score/raw rate/sample count. Missing sources are omitted, not set to zero. The macOS cockpit uses the same distinction. Neither presentation surface computes scores or combines them. The `/ops` surface remains an operations view over published inventory and prediction artifacts; it is not authenticated, contains no secrets, and delegates workflow execution to GitHub Actions.
