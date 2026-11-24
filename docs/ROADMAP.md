# Roadmap and implementation status

Last reviewed: 2026-11-22

This page distinguishes implemented foundations from an integrated, user-ready feature. Code and tests existing does not mean a feature is connected to the macOS workflow or validated with real users.

## Current milestone: Phase 0 real-world capture validation

The macOS app is distributed through automated GitHub Releases as a DMG and ZIP. Builds are ad-hoc signed, not Developer ID signed or notarized; macOS may warn on first launch. See [distribution](DISTRIBUTION.md). The immediate action is maintainer-led testing of the installed app during a representative Arena draft. See [the project-state handoff](PROJECT_STATE.md) for accumulated data findings and durable product decisions.

**In progress.** The ScreenCaptureKit prototype is merged. The next step is a representative Arena draft recording from the target Mac.

- [x] Enumerate visible, shareable windows.
- [x] Suggest likely iPhone Mirroring windows using an advisory heuristic.
- [x] Allow manual target selection.
- [x] Capture a still frame of the selected window.
- [x] Capture a bounded three-second sequence (up to 4 fps, maximum 20 frames).
- [ ] Confirm window identification on the target Mac.
- [ ] Review recording with pack changes and scrolling.
- [ ] Confirm frames contain only the selected window and preserve card text/detail.
- [ ] Record dimensions, frame cadence, repeated/dropped frames, and permission behavior.
- [ ] Decide whether capture is suitable for OCR and whether continuous capture is needed.

**Exit decision:** begin recognition only after reviewing actual captured frames. Compilation and unit tests do not establish real-world capture quality.

## Implemented foundations

### Local card and dataset storage
- [x] SQLite reference store and dataset snapshot/provenance model.
- [x] Scryfall default-cards importer with streaming JSONL ingestion.
- [x] Distinct Scryfall printing, Oracle, and Arena identifiers.
- [x] 17Lands public dataset catalog discovery and archive metadata.
- [x] Official gzip CSV downloading and streaming parsing.
- [x] Game-level metric aggregation, including copy-weighted facets and overall baseline.
- [x] Draft-level ALSA/ATA aggregation, including pack-wheel handling and secondary picks.
- [x] Dataset freshness and recommendation-readiness evaluation.

### Metric verification
- [x] Independent Python reference implementation and Swift/Python comparison tooling.
- [x] HOB PremierDraft archive validation workflow and successful validation artifact.
- [x] Manual review of physical pack return, last-seen behavior, ALSA averaging, secondary picks, duplicate copies, and incomplete pack handling.
- [x] Replay schema audit script and manually triggerable workflow.
- [x] Reviewed HOB replay audit: all 323,114 game keys matched replay keys one-to-one.
- [ ] Run replay-backed deck/sideboard/opening-hand consistency audit.
- [ ] Establish a defensible whole-game eligibility rule consistent with 17Lands definitions.

**Important limitation:** the game importer currently aggregates rows with valid win outcomes; it does not exclude inconsistent games as a whole. The public wide CSV has no documented game-valid/deck-linked flag. Do not claim exact 17Lands parity. Replay key matching does not itself establish upstream eligibility. See [metric semantics](17lands-metric-semantics.md).

### Draft domain foundation
- [x] Append-only event model.
- [x] Pack observations and player pick events.
- [x] Corrections as new events referencing original picks.
- [x] Event validation and deterministic replay tests.
- [ ] Persistence and session recovery.
- [ ] Recognition and UI integration.
- [ ] Real-draft usability testing.

### Recommendation foundation
- [x] Shared platform-independent Swift evaluator.
- [x] Dataset readiness and snapshot compatibility checks.
- [x] Regularized standalone GIH WR baseline using a same-scope overall baseline.
- [x] Explicit exclusions for missing or incompatible candidate data.
- [x] Deterministic results with scoring configuration, engine/schema versions, and explanations.
- [ ] Review/tune prior weight against held-out data.
- [ ] Integrate recognized pack candidates and draft state into the app.
- [x] Document prediction model v1: five independent dimensions, multi-label roles, evidence/confidence, rate assessment, immutable predictions, and later calibration.
- [x] Add deterministic structural role suggestions in the shared Swift core and a local batch CLI.
- [ ] Build the reviewed set catalog and reviewer workflow for accepting/rejecting suggestions and recording dimension/rate assessments.
- [ ] Review TRK as the first pre-release prediction set and publish a reproducible prediction snapshot.
- [ ] Add prediction-versus-observation calibration reports when permitted 17Lands public datasets are available.
- [ ] Integrate pool synergy, archetype, curve, and deck-needs factors only after explicit input contracts and tests.

The current 17Lands evaluator is a baseline, not a complete Limited strategy model. The new prediction model is documented in [PREDICTION_SCORING_MODEL.md](PREDICTION_SCORING_MODEL.md); its initial structural role suggester and batch CLI are implemented, but set review, card ratings, and calibration are not yet complete. ALSA and ATA are carried as context but do not affect ranking. GIH observations are copy-weighted and are not independent game samples.

## Product UX design

- [x] Define draft cockpit product direction: current pack, evolving deck, and strategic context.
- [x] Define pre-draft set/event selection, data readiness, and optional archetype briefing.
- [x] Define progressive pack observation, unresolved-card states, explicit pick confirmation, and pack history/wheel behavior.
- [x] Define deck summary and future archetype/splash guidance expectations.
- [ ] Validate the proposed workspace hierarchy against real capture dimensions and a complete recorded draft.
- [ ] Implement the draft-session shell and state projections after Phase 0 capture validation.
- [ ] Usability-test card scanning, pick confirmation, pack history, and deck visibility.

The accepted product UX direction is documented in [DRAFT_COCKPIT_UX.md](DRAFT_COCKPIT_UX.md). Design definition is complete; implementation is not.

## Analysis and production plan

The bounded data-analysis sequence and production checkpoint are documented in [ANALYSIS_AND_PRODUCTION_PLAN.md](ANALYSIS_AND_PRODUCTION_PLAN.md).

The reviewed published archetype catalog records HOB, ECL, and TDM taxonomies from official Wizards overview images. HOB has five two-color archetypes; ECL has five featured two-color typal archetypes plus five overlapping two-color mechanical themes; TDM has five three-color clans plus five overlapping two-color themes. The reviewed card catalog contains 62 source-backed relationships (HOB 26, ECL 19, TDM 17), all enriched with Scryfall identity and display metadata. These are reviewed design-intent relationships, not empirical pick or performance claims, and do not currently affect recommendations. The HOB PremierDraft set-speed baseline is recorded in [ANALYSIS_AND_PRODUCTION_PLAN.md](ANALYSIS_AND_PRODUCTION_PLAN.md) from successful workflow run [44861481947](https://github.com/sedward5/urzas-oculus/actions/runs/44861481947). The historical user win-rate bucket terminology and missing-value count are corrected. A first reproducible two-color archetype-proxy audit is implemented in `scripts/analyze_17lands_archetypes.py`, with manual workflow `17lands-archetype-audit.yml`. Run it for HOB PremierDraft and review its artifact before drawing conclusions. Lane inference remains a separate follow-on analysis. These are cockpit enhancements, not reasons to hold the first useful production release indefinitely.

## Next phases

### Phase 1 — Recognition prototype
After capture review: define pack/card regions; run local Vision OCR while preserving text, coordinates, and confidence; resolve card candidates using local Scryfall metadata; and expose ambiguous results for correction.

Exit criteria: representative pack contents can be collected across scrolling, uncertainty is visible, and recognition never changes authoritative draft history by itself.

### Phase 2 — Draft tracking workflow
Persist append-only events and recover sessions; connect recognition observations to pack events; capture player selections separately; support correction and replay; derive the drafted pool from event history; and test complete drafts against reviewed recordings.

The core event model exists; persistence and end-to-end integration do not.

### Phase 3 — Data readiness and recommendation integration
Resolve or bound the 17Lands game-eligibility gap; validate current upstream archive shapes and freshness; connect exact card IDs from draft state to local records; make readiness failures understandable; and test reproducible recommendations from recorded draft state and pinned snapshots.

### Phase 4 — Integrated draft companion
Integrate capture, recognition, draft tracking, data readiness, and recommendations. Validate with real drafts before calling it release-ready.

### Phase 5 — Public data views
The Hugo site is deployed at [urzas-oculus.pages.dev](https://urzas-oculus.pages.dev/). It currently introduces the project. Later it may present versioned static statistics or recommendation artifacts generated by the shared Swift evaluator. The website must not duplicate scoring logic.

## Future platform expansion

iPhone Mirroring is the initial capture target. Native macOS Arena capture is a possible later capture source, not a separate product. Keep recognition, draft events, data, and scoring independent of capture-source details. Desktop layout profiles and capture-source abstraction require their own implementation and validation.

## Release readiness

Do not describe Oculus as a complete draft companion until capture is validated with representative real drafts; OCR/card recognition works across pack scrolling and has a correction path; draft history persists and reconstructs the correct pool; recommendations consume the current pack and compatible local snapshots; readiness and metric limitations are visible; a complete draft has been tested by a real user; and documentation matches shipped behavior.


## Predictive model and operations console (new priority)

- [ ] Publish a static, unlinked `/ops` inventory with set acquisition, archetype image, Wizards guide, public 17Lands freshness, prediction artifact, and GitHub Actions status.
- [ ] Add immutable, cutoff-aware prediction-run artifacts and deterministic canonical output.
- [ ] Implement the first algorithmic card feature model in the shared Swift core; normal set runs must not require manual per-card ordinal ratings.
- [ ] Generate predictions for TRK and the three existing historical sets, clearly labeling retrospective runs and cutoffs.
- [ ] Add comparison reports for pick behavior, play rate, and game performance separately, including sample sizes and coverage.
- [ ] Surface outliers and review annotations without allowing LLM/human analysis to mutate predictions.
- [ ] Establish model-version regression tests across historical sets and held-out observations.

The closed learning loop is a primary product direction. 17Lands is the observation/evaluation layer, not a source of pre-release prediction features. Model changes are deterministic, versioned, and replayable. See [PROJECT_STEERING.md](PROJECT_STEERING.md) and [PREDICTION_SCORING_MODEL.md](PREDICTION_SCORING_MODEL.md).
