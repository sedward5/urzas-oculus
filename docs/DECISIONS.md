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

## ADR-006: SQLite reference store with source snapshots

**Status:** Accepted

Scryfall printing records and 17Lands performance observations are stored
in a local SQLite database. Scryfall ID, Oracle ID, and Arena ID remain
distinct. 17Lands observations are scoped to set, event type, user group,
color filter, and dataset snapshot.

Imported records preserve source attribution and snapshot metadata.
A 17Lands metric links to a Scryfall printing only when the card name maps
unambiguously within the requested set. Arena ID lookups likewise expose
ambiguity rather than choosing an arbitrary printing.

Reference data is updated explicitly. Draft recommendations never depend
on a live Scryfall or 17Lands request.


## ADR-007: One shared recommendation implementation

**Status:** Accepted

All recommendation domain logic lives in one platform-independent Swift
core. The macOS app and headless CI invoke the same evaluator. CI may publish
versioned static artifacts, and the web app may present those artifacts, but
neither delivery surface may maintain its own normalization, scoring, or
ranking implementation.

The evaluator is deterministic and accepts explicit data, readiness, and
versioned scoring configuration. Adapters acquire inputs and distribute
outputs; they do not duplicate recommendation rules.

Consequences:
- The macOS app and web experience cannot drift through separate scoring code.
- CI and local app results can be compared using the same evaluator version.
- Browser-side evaluation is not introduced unless a future requirement
  justifies compiling the shared core for that environment.


## ADR-008: Draft cockpit interaction model

**Status:** Accepted product direction; implementation pending

The primary draft workspace presents three coordinated views: the current pack, the evolving drafted pool/deck, and strategic context. The current pack is the primary focus during a pick. Deck composition and strategy remain visible as supporting context.

Before joining a draft, the player selects event type and set in Oculus. Sets are ordered by release date, newest first. Oculus checks local data freshness/readiness and may present reviewed set archetypes as an optional briefing. Oculus does not launch or control Arena.

Pack recognition accumulates observations across scrolling. Unresolved card slots remain visible and are not guessed. The player explicitly confirms a pick; confirmed picks enter the append-only draft history and update the drafted pool. Prior packs remain inspectable and can be updated with wheel observations. The interface must not infer that a card was picked by another drafter merely because it is absent from a later observation.

The deck view summarizes drafted cards, colors, mana curve, and creature/noncreature counts. Future strategic guidance may identify archetype direction, table openness, and splash considerations, but must explain evidence and uncertainty. These strategic capabilities are not present in the current standalone GIH WR evaluator.

Consequences:
- Recognition, confirmed selection, and Arena state observation remain separate.
- The event log remains authoritative; the UI displays projections of it.
- Dataset snapshots and scoring configuration are pinned to a draft session.
- The detailed UX specification is maintained in docs/DRAFT_COCKPIT_UX.md.
- This ADR defines product behavior, not a claim that the interface is implemented.
