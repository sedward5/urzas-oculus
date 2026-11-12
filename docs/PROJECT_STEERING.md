# Urza's Oculus — Project Steering Document

## 1. Executive Summary

Urza's Oculus is a native macOS companion application that assists players drafting Magic: The Gathering Arena on an iPhone through macOS iPhone Mirroring.

The application captures the mirrored iPhone window, identifies the active draft pack and its cards, tracks the player's drafted pool, and provides real-time algorithmic pick recommendations.

The application is designed around local processing, deterministic algorithms, and explainable recommendations.

The player remains in complete control of the game. Urza's Oculus observes and advises. It does not interact with Arena.

### Primary objectives

1. Capture the macOS iPhone Mirroring window reliably.
2. Identify visible Magic cards using local computer vision and OCR.
3. Maintain an accurate representation of the current draft.
4. Evaluate available picks using card data and draft context.
5. Provide useful, explainable recommendations.
6. Operate without paid services, cloud inference, or runtime AI dependencies.

---

## 2. Core Philosophy

### Local first

Screen capture, image processing, OCR, card identification, draft tracking, and recommendation calculations happen locally.

External datasets may be downloaded or imported as versioned reference data. Individual pick decisions must not require network access.

### Deterministic

Given the same draft state, card data, and scoring configuration, the recommendation engine must produce the same results.

Avoid opaque or nondeterministic recommendation systems.

### Explainable

Recommendations should communicate why a card is preferred.

A recommendation should be decomposable into meaningful factors such as:

- Individual card strength.
- Set-specific card performance.
- Archetype alignment.
- Synergy with drafted cards.
- Mana curve.
- Color commitment.
- Removal and interaction.
- Deck composition.
- Remaining draft opportunities.

### Player controlled

The application never makes selections or interacts with Arena.

Recognition errors must be recoverable through user correction.

### Incremental development

Validate the most significant technical risks before investing in dependent systems.

Prefer small, testable milestones over large speculative implementations.

---

## 3. Platform and Technology

### Target platform

- Native macOS application.
- Minimum supported version: macOS 14.
- Primary language: Swift.
- UI framework: SwiftUI.
- Initial build system: Swift Package Manager.

### Apple frameworks

| Framework | Purpose |
|---|---|
| ScreenCaptureKit | Window discovery and screen capture |
| Vision | OCR and image recognition |
| CoreGraphics | Image and coordinate processing |
| SwiftUI | Application interface |
| AppKit | macOS application integration |

Additional frameworks may be introduced when justified by a concrete requirement.

### Application identity

- Product name: Urza's Oculus
- Bundle identifier: `com.local.urzas-oculus`
- Minimum macOS version: 14.0

The bundle identifier may change before public distribution if a more appropriate namespace is established.

---

## 4. Explicit Constraints

The following constraints are architectural requirements, not optional preferences.

### Prohibited dependencies

- No runtime AI inference.
- No cloud inference.
- No required paid APIs.
- No required subscription services.
- No server dependency for the core drafting workflow.
- No requirement for an internet connection during an active draft.

### Prohibited game interaction

- No automated clicks.
- No automated keyboard input.
- No simulated touch input.
- No interaction with the Arena game client.
- No overlays placed over the mirrored iPhone window.
- No attempt to automate draft selections.

### Privacy and permissions

- Do not transmit captured screen contents.
- Do not collect unrelated desktop content.
- Request only the permissions required for the application's functionality.
- Do not require administrator privileges.
- Keep captured images and observations local.

### External data

Public datasets may be downloaded or imported as explicit, versioned updates.

Potential sources include:

- Scryfall.
- 17Lands.
- Other reputable public Magic card and draft datasets.

External data must have documented provenance and version information.

The application must remain functional using previously downloaded data.

---

## 5. Core User Workflow

The intended workflow is:

1. User launches Urza's Oculus.
2. User opens MTG Arena on an iPhone.
3. User mirrors the iPhone to macOS.
4. Urza's Oculus identifies the mirrored window.
5. The application captures the active draft screen.
6. Recognition identifies the visible pack and card candidates.
7. The application associates candidates with authoritative card records.
8. Uncertain recognition results are presented for user correction.
9. The application evaluates available picks.
10. Recommendations are displayed with supporting explanations.
11. The user makes their selection in Arena.
12. The application observes the next draft state and updates its history.

The application must support recovery from missed frames, uncertain recognition, and user corrections.

The authoritative draft history must not depend on successfully recognizing every frame.

---

## 6. Architecture

The application is divided into independently testable engines.

Each engine should have a clear responsibility and limited dependencies.

### 6.1 CaptureEngine

Responsible for discovering and capturing the iPhone Mirroring window.

Responsibilities:

- Enumerate available shareable windows.
- Identify the iPhone Mirroring window.
- Configure ScreenCaptureKit.
- Capture still frames and frame sequences.
- Track capture metadata.
- Report permission and capture errors.
- Manage capture lifecycle and resource cleanup.

CaptureEngine must not make card identity or draft-state decisions.

The initial implementation should prioritize reliable still-frame capture before continuous capture.

### 6.2 RecognitionEngine

Responsible for interpreting captured images.

Responsibilities:

- OCR using Vision.
- Image preprocessing.
- Card candidate identification.
- Card layout interpretation.
- Coordinate and region analysis.
- Confidence scoring.
- Ambiguity reporting.

Recognition results must preserve their relationship to the original observation.

The engine must not silently convert uncertain recognition into authoritative draft state.

Recognition should support multiple independent signals where practical.

### 6.3 DraftEngine

Owns the authoritative draft history and state.

Responsibilities:

- Track draft sessions.
- Track packs and picks.
- Record player selections.
- Maintain the drafted pool.
- Track pick and pack progression.
- Apply user corrections.
- Recover from missed or uncertain observations.
- Reconstruct the current state from draft history.

DraftEngine should use explicit events or equivalent immutable history records.

Recognition results are inputs to the draft state machine, not its authority.

### 6.4 ScoringEngine

Evaluates available cards against the current draft context.

Responsibilities:

- Individual card evaluation.
- Archetype and color analysis.
- Card synergy.
- Mana curve analysis.
- Interaction and removal assessment.
- Deck composition.
- Pick recommendations.
- Recommendation explanations.

Scoring must be deterministic for a given draft state, scoring configuration, and reference-data version.

ScoringEngine must not mutate draft state.

### 6.5 DataEngine

Owns reference data and normalization.

Responsibilities:

- Import card records.
- Normalize card identities.
- Maintain card metadata.
- Import draft performance data.
- Track dataset versions.
- Preserve source provenance.
- Provide efficient local lookup.

Potential data sources include Scryfall and 17Lands.

The engine should support offline operation.

Data updates must be explicit and must not silently change the interpretation of an existing draft.

### 6.6 CollectionEngine

Provides optional collection context.

Potential responsibilities:

- Track owned cards.
- Import collection data.
- Provide ownership information.
- Support collection-aware recommendations where appropriate.

CollectionEngine must remain optional.

The core draft workflow must not depend on collection data.

---

## 7. Data Model Principles

### Card identity

Cards must be associated with authoritative records rather than relying exclusively on OCR text.

Use stable identifiers where available.

Scryfall identifiers are a potential source of canonical card identity.

### Recognition observations

An observation should preserve:

- Source image or frame reference.
- Capture timestamp.
- Window metadata.
- Image dimensions.
- OCR output.
- Candidate card identities.
- Confidence values.
- Recognition metadata.

### Draft history

Draft history should preserve:

- Draft session identity.
- Pack number.
- Pick number.
- Observed pack contents.
- Player selection.
- Recognition confidence.
- User corrections.
- Reference-data version.

### Data versioning

Recommendations should be traceable to:

- Card-data version.
- Draft-performance dataset version.
- Scoring configuration version.
- Application version.

A historical draft should remain interpretable even when reference datasets are updated.

---

## 8. Recommendation Philosophy

Recommendations should reflect the realities of Limited play.

A card's value is contextual.

Individual card ratings are useful inputs, but they should not be the entire recommendation system.

Potential evaluation dimensions include:

### Baseline card strength

Use set-specific performance data where available.

17Lands provides useful Limited statistics, but those statistics must be interpreted carefully.

Metrics may include:

- Game-in-hand win rate.
- Improvement when drawn.
- Improvement when played.
- Games played.
- Games seen.
- Available pick data.

Avoid treating raw win rate as a universal card rating.

Account for sample size and format context.

### Draft context

Evaluate the card against the current pool.

Consider:

- Existing colors.
- Archetype direction.
- Synergies.
- Curve requirements.
- Removal density.
- Creature count.
- Combat tricks.
- Evasion.
- Fixing.
- Splash potential.

### Explainability

Recommendations should expose the important contributing factors.

For example:

- Strong standalone card.
- Supports the current archetype.
- Fills a missing curve position.
- Provides needed interaction.
- Competes with an already crowded role.

The goal is to help the player make better decisions, not simply output a card name.

---

## 9. Initial Development Milestones

Development should follow this sequence unless evidence justifies a change.

### Phase 0 — Screen Capture Feasibility

**Current priority.**

Determine whether ScreenCaptureKit can reliably capture the macOS iPhone Mirroring window.

Tasks:

1. Enumerate shareable windows.
2. Identify the iPhone Mirroring window.
3. Capture a still frame.
4. Display the captured frame.
5. Capture a short sequence of frames.
6. Inspect image dimensions and quality.
7. Evaluate screen-recording permissions.
8. Document reliability and limitations.

Acceptance criteria:

- The mirrored window can be identified consistently.
- Captured images exclude unrelated desktop content.
- Captured images preserve sufficient detail for OCR.
- Permission failures are understandable.
- No administrator privileges are required.
- Capture does not interact with Arena.

Deliverable:

A working capture prototype and a documented feasibility assessment.

Do not begin substantial recognition implementation until this phase is evaluated.

### Phase 1 — Recognition Prototype

After capture feasibility is established:

1. Define the draft-screen regions.
2. Implement local OCR.
3. Identify candidate card names.
4. Associate candidates with card records.
5. Evaluate recognition confidence.
6. Display uncertain results for correction.

Acceptance criteria:

- Recognition works against representative draft screens.
- Uncertainty is explicit.
- Incorrect results can be corrected.
- Recognition does not silently modify authoritative draft history.

### Phase 2 — Draft State

Implement:

- Draft sessions.
- Pack tracking.
- Pick tracking.
- Player selections.
- Drafted pool.
- User corrections.
- Recovery and reconstruction.

Acceptance criteria:

The application can accurately maintain a draft using recognized observations and user corrections.

### Phase 3 — Reference Data

Implement local data import and normalization.

Prioritize:

- Card identities.
- Set metadata.
- Color identity.
- Mana costs.
- Types and keywords.
- 17Lands performance metrics.

Acceptance criteria:

The application can retrieve the relevant data without making live requests during a pick.

### Phase 4 — Recommendation Engine

Implement baseline card evaluation.

Start with understandable, testable scoring components.

Add contextual evaluation incrementally.

Acceptance criteria:

- Recommendations are deterministic.
- Results are explainable.
- Individual scoring factors can be inspected.
- Scoring can be tested independently of the UI.

### Phase 5 — Integrated Draft Companion

Integrate capture, recognition, draft state, data, and scoring.

Prioritize:

- Clear current-pack display.
- Drafted-pool visibility.
- Recommendation ranking.
- Explanation of recommendations.
- Recognition correction.
- Recovery from missed observations.

---

## 10. Testing and Quality

Testing is required for meaningful application behavior.

### Unit tests

Prioritize tests for:

- Card identity normalization.
- OCR result interpretation.
- Recognition confidence.
- Draft state transitions.
- Pack and pick sequencing.
- User corrections.
- Data import.
- Scoring calculations.
- Recommendation determinism.

### Integration tests

Where practical, test:

- Capture to observation.
- Observation to recognition.
- Recognition to draft state.
- Draft state to recommendation.

Use representative local fixtures.

### Test data

Do not require live API access for ordinary tests.

Use small, versioned fixtures that make tests reproducible.

Avoid committing private screen captures or personal data.

### CI

GitHub Actions should use macOS runners for native builds and tests.

Linux development environments may be used for editing, documentation, and Git operations.

Native macOS functionality must be validated on macOS.

---

## 11. Development Workflow

### Repository structure

The initial structure uses Swift Package Manager.

Keep the repository organized around the engine boundaries.

Avoid introducing additional frameworks or project-generation tools without a concrete need.

### Pull requests

Pull requests should:

- Have a focused purpose.
- Explain the behavior being introduced.
- Include tests where appropriate.
- Update documentation when architecture or behavior changes.
- Identify known limitations.
- Preserve all explicit project constraints.

### Coding agent instructions

Before making architectural changes, coding agents should read:

- `docs/PROJECT_STEERING.md`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`

Do not invent implementation details or claim functionality exists when it is only scaffolded.

Prefer small changes that can be independently reviewed.

---

## 12. Architecture Decision Records

Significant architectural choices should be recorded in `docs/DECISIONS.md`.

Each decision should include:

- Decision identifier.
- Title.
- Status.
- Context.
- Decision.
- Consequences.

Revisit decisions when new evidence justifies doing so.

Do not silently change established architectural constraints.

---

## 13. Definition of Done

A feature is complete when:

- Its intended behavior is implemented.
- Relevant tests pass.
- Errors and uncertain states are handled.
- Documentation is updated where necessary.
- The implementation respects project constraints.
- Native macOS CI succeeds when applicable.
- The feature is accurately represented in project documentation.

A placeholder, prototype, or unverified implementation must be labeled accordingly.

---

## 14. Long-Term Vision

Urza's Oculus should become a dependable drafting companion that helps players make better Limited decisions.

It should combine accurate observation, reliable draft tracking, useful statistical data, and contextual recommendations.

The application should remain:

- Local.
- Private.
- Deterministic.
- Explainable.
- Affordable.
- Player controlled.

The goal is not to replace player judgment.

The goal is to make better information available at the moment it matters.
