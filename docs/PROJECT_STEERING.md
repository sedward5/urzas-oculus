# Urza's Oculus — Project Steering

Last reviewed: 2026-11-21

This document defines product goals, constraints, and architectural guardrails. The current implementation status and milestone sequence live in [ROADMAP.md](ROADMAP.md).

## Product summary and current reality

Urza's Oculus is an independent native macOS companion intended to help players understand and navigate Magic: The Gathering Arena drafts. The long-term product combines local observation, explicit draft history, versioned reference data, and deterministic, explainable recommendations.

The current macOS app is a **Phase 0 ScreenCaptureKit feasibility prototype**. It enumerates visible windows, suggests likely iPhone Mirroring targets, allows manual selection, captures a still frame, and samples a bounded three-second frame sequence. Real-world capture validation and a representative draft recording remain outstanding. OCR, card recognition, and an integrated draft workflow are not implemented.

Foundational components already exist independently: an append-only draft-event model; SQLite/Scryfall reference data; official 17Lands archive acquisition, parsing, and metric aggregation; dataset provenance/readiness; and a shared Swift evaluator for a regularized standalone GIH WR baseline. These components are not integrated into a complete draft companion.

## Draft experience direction

The intended user experience is a persistent **draft cockpit** with three coordinated areas: the current pack, the evolving drafted pool/deck, and strategic context. The pack is primary during a pick; deck shape and archetype/color signals remain visible alongside it.

The intended journey is: refresh/check local Scryfall and 17Lands data at launch; choose event type and set (newest release first) before joining Arena; start a local session; optionally review set archetypes; capture and progressively recognize the first pack; explicitly confirm picks; retain collapsible pack history and wheel updates; and continuously update deck composition and strategic context.

Recognition is never authoritative. Unresolved cards remain visibly unresolved, picks require explicit confirmation, and the drafted pool is derived from append-only events. Strategic guidance must expose evidence and uncertainty. In particular, archetype openness is not the same as the user's own color direction, and splash advice must account for fixing and mana requirements.

Published archetype guidance and signpost cards are contextual metadata, not ground truth about draft strength or lane availability. Keep published design intent, historical pick behavior, observed card performance, and live-pack evidence separate and traceable. A signpost can contribute an early lane signal, but must never establish an open lane or produce a supported confidence state on its own. Require corroborating supporting-card depth, independent pack observations, or meaningful wheel evidence. A weak signpost does not invalidate a strategy whose supporting cards are arriving unusually late. Treat discrepancies between intended archetype, player valuation, and actual performance as evidence to investigate rather than silently resolving them in scoring.

The detailed interaction hierarchy, states, acceptance scenarios, and open design questions are in [DRAFT_COCKPIT_UX.md](DRAFT_COCKPIT_UX.md). This is accepted product direction, not implemented functionality.

## Core philosophy

- **Local first:** capture, recognition, draft tracking, and scoring are intended to run locally. Network access is for explicit reference-data updates, not active picks.
- **Deterministic:** the same explicit state, data snapshots, and scoring configuration produce the same result.
- **Explainable:** recommendations expose evidence, exclusions, provenance, and limitations.
- **Player controlled:** Oculus observes and advises. It never interacts with Arena or makes selections.
- **Honest about uncertainty:** missing data is not zero; recognition uncertainty, sample size, freshness, and readiness are explicit.
- **Incremental:** validate risky assumptions with real evidence before building dependent systems.

## Platform and technology

- Native macOS application; minimum supported version macOS 14.
- Swift and SwiftUI, managed with Swift Package Manager.
- ScreenCaptureKit for window discovery and capture.
- Vision is the planned local OCR framework; recognition is currently a placeholder.
- SQLite for local reference data.
- Hugo Extended for the website under website/; Cloudflare Pages handles deployment.
- GitHub Actions validates the website on Ubuntu and native app code on macOS.

iPhone Mirroring is the initial capture target. Native macOS Arena capture may be a later capture source, not a separate product. Keep recognition, draft history, data, and scoring independent of capture-source details. A capture-source abstraction and desktop layout profile are future work.

## Non-negotiable constraints

### Dependencies
- No runtime AI inference or cloud inference.
- No required paid APIs, subscriptions, or server for the core drafting workflow.
- No network dependency during an active draft.
- No duplicate recommendation implementation in browser JavaScript/TypeScript.

### Arena interaction
- No automated clicks, keyboard input, simulated touch, or draft selections.
- No interaction with the Arena client.
- No overlays over the mirrored game window.

### Privacy and permissions
- Capture only the explicitly selected target window.
- Do not transmit captured screen contents.
- Keep captures and observations local.
- Request only necessary permissions; do not require administrator privileges.
- Do not commit private recordings or personal screen contents.

### External data
- Preserve source, dataset key, upstream update time, local acquisition/import time, and snapshot identity.
- Keep Scryfall printing ID, Oracle ID, and Arena ID distinct.
- Preserve missing values as missing, not zero.
- Respect third-party attribution and licensing.
- Existing drafts and results must remain interpretable when datasets are refreshed.

## Domain boundaries

### CaptureEngine
Discovers visible shareable windows and captures still frames or bounded sequences. It reports permission and lifecycle errors. It does not identify cards or mutate draft state. The iPhone Mirroring heuristic is advisory; the user selects the target.

### RecognitionEngine
Planned responsibility: local OCR, image preprocessing, card candidate identification, layout interpretation, confidence, and ambiguity reporting. Currently a placeholder. Recognition must preserve its source observation and must never silently turn uncertain candidates into authoritative draft state.

### DraftEngine
Owns authoritative draft history. The current core model supports session start, pack observations, player picks, corrections, validation, and deterministic replay. Persistence, UI, recognition integration, and a complete capture-to-draft workflow remain future work. Corrections append events; they do not rewrite history.

### DataEngine
Owns card identity, local reference records, importers, dataset snapshots, provenance, freshness, and readiness. 17Lands metrics are scoped by set, event, user group, color filter where applicable, and snapshot.

### ScoringEngine
Owns the one maintained recommendation implementation in the platform-independent Swift core. The current baseline regularizes standalone GIH WR toward an explicit overall baseline from the same dataset scope and snapshot. ALSA and ATA are available as context but do not affect ranking. Pool synergy, archetype, curve, and deck-needs scoring are not implemented.

The evaluator must not depend on SwiftUI, app lifecycle, filesystem layout, CI, web hosting, or network services. Adapters acquire inputs or publish results but call the same evaluator. The website may display versioned artifacts; it must not reproduce scoring.

### CollectionEngine
Optional future collection context. The core draft workflow must not depend on it.

## Recommendation data contract

A recommendation is not ready unless the required draft and game datasets are present, compatible, and within configured freshness limits. A game-only or draft-only snapshot is insufficient. The evaluator rejects unready data, scope/snapshot mismatches, missing or unusable GIH samples, and missing or mismatched same-scope baselines.

GIH counts are copy-weighted observations, not independent game samples. Do not use them to claim confidence intervals. The prior weight is a versioned tuning parameter, not a sample count.

**Known correctness gap:** the public 17Lands game archive does not expose a documented whole-game validity/deck-linkage flag. The current importer aggregates rows with valid win outcomes and does not implement 17Lands' exclusion of inconsistent games. Do not claim exact 17Lands parity until a defensible eligibility rule is established.

## Development and quality

- Keep engines independently testable and use deterministic fixtures.
- Ordinary tests must not require live network services or current upstream archives.
- Archive validation is a separate explicit workflow; preserve reports and artifacts.
- Native Swift functionality must be validated on macOS.
- Website-only changes should use Ubuntu Hugo CI, not the macOS app runner.
- Update documentation when implementation or architecture changes.
- Significant architectural choices belong in docs/DECISIONS.md.

Before architectural work, read this document, [ARCHITECTURE.md](ARCHITECTURE.md), [DECISIONS.md](DECISIONS.md), and [ROADMAP.md](ROADMAP.md).

## Definition of done

A feature is complete when behavior is implemented, relevant tests pass, uncertain/error states are handled, documentation is current, and the implementation respects project constraints. A scaffold, prototype, or unvalidated implementation must be labeled accordingly.
