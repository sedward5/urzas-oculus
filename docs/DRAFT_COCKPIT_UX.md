# Draft Cockpit — Product UX Specification

Status: product direction accepted; interactive visual mockup available; production behavior not implemented
Last updated: 2026-11-20

## Product intent

Urza's Oculus is a draft cockpit, not merely a card-ranking list. During a draft it should keep three questions easy to answer:

1. **The pack:** What can I pick now? What have I seen? Which choices are strongest?
2. **The deck:** What have I drafted? What is my curve, color balance, and creature/noncreature mix?
3. **The strategy:** Which archetypes and colors appear open? How should my current direction affect this pick?

The current pack is the primary focus. Deck and strategy context remain visible without competing with the pick decision.

## End-to-end user journey

### 1. Launch and data readiness

When Oculus opens, it checks its local data catalog against the current 17Lands and Scryfall catalogs.

- Determine which set, event, and format datasets are available locally.
- Compare upstream update metadata with locally stored snapshots.
- Acquire only missing or changed data, subject to the user's network/data settings.
- Show progress, last-updated timestamps, source provenance, and any failures.
- Do not block opening the app when an optional source is unavailable.
- Do not imply recommendations are ready until required compatible snapshots pass the shared readiness checks.

The user should be able to inspect data status and trigger a refresh. Avoid silently replacing a dataset snapshot during an active draft; pin the session to explicit snapshots.

### 2. Configure a draft before joining

The user selects the draft configuration in Oculus before joining the event in Arena.

- **Format/event type** is an explicit choice (for example Premier Draft, Traditional Draft, or Quick Draft when supported).
- **Set** is a searchable/selectable list ordered by release date, newest first. The likely current set should be easy to choose.
- Show a compact data-readiness indicator for the selected set and event.
- Enable Start only when the selection is valid. If data is incomplete, explain what is missing and whether the session can start in observation-only mode.
- The user then starts the corresponding draft in Arena.

Starting in Oculus creates a local session and pins its set, format, data snapshots, and configuration. It does not launch or control Arena.

### 3. Archetype briefing

After Start and before the first pack, show a short set briefing when reviewed Wizards archetype information is available.

- Present archetype names, colors, and concise themes.
- Clearly label source and version/date.
- Treat this as optional context, not a requirement for starting a draft.
- If unavailable, skip the briefing gracefully.
- The user can revisit it during the draft.

This briefing is reference material, not a prediction that any archetype will be open at the table.

### 4. Detect and interpret the first pack

ScreenCaptureKit samples the selected Arena window. Recognition looks for the transition into an active draft pack, then accumulates visible card observations as the user scrolls.

The pack view should distinguish three states:

- **Recognized card:** card identity is sufficiently clear to show its name and evaluation.
- **Unresolved slot:** a card is expected/visible but has not yet been identified; show a neutral gray placeholder or outline.
- **Needs review:** one or more possible identities exist; show uncertainty and provide a correction path.

Do not silently fill uncertain slots with a guessed card. Preserve source-frame references and confidence for correction.

A pack is a collection of card instances, not just unique names. Duplicate copies must remain distinct in pack state even if the UI groups or visually annotates them.

### 5. Make a pick

Each card appears as a compact row inspired by the deck-list visual language:

- Card name.
- Recommendation score or rank, with a clear explanation affordance.
- Mana value.
- Color identity/color treatment.
- Optional concise role or type hint where it helps.

Rows are ordered by recommendation by default, with the ability to change to original pack order or alphabetical order. Recommendation rank must not obscure that the player owns the decision.

The player selects a card and explicitly confirms the pick. Confirmation creates the authoritative pick event, removes that card instance from the active pack, and adds it to the drafted pool.

If Arena's actual selection is not yet confirmed by observation, show the action as pending rather than claiming the pick is complete. The player can correct a mistaken selection; corrections append events and preserve history.

### 6. Navigate packs and picks

The current pack is expanded and prominent. Completed packs collapse into a compact history list.

- Pack headers identify pack number and pick number.
- Expand any previous pack to inspect what was observed.
- Historical pack contents reflect known picks and known wheel returns.
- A selected card is visibly marked as picked, not silently erased from history.
- When a pack wheels back, update the original pack's remaining-card view with new observations.
- Distinguish cards known to have been selected by other drafters from cards simply no longer observed. Do not infer a specific cause unless the data supports it.
- Preserve incomplete observations; a partially scanned pack must not appear complete.

The user should be able to revisit history without losing focus on the current pack.

### 7. Track the evolving deck

A persistent deck panel updates after each confirmed pick.

At minimum show:
- Drafted card list, grouped or filterable by color.
- Total picks and card count.
- Color distribution.
- Mana curve by mana value.
- Creature versus noncreature counts.
- A compact visual summary of the deck's current shape.

Later refinements may include card roles, removal, fixing, interaction, creature curve, and sideboard-like categories. Do not imply a drafted pool is a finished deck.

### 8. Show archetype and color signals

As picks accumulate, Oculus evaluates the user's developing direction and available evidence.

- Show likely archetypes with confidence or evidence strength, not a single unexplained label.
- Explain contributing picks, colors, and available set-specific signals.
- Distinguish the user's current direction from evidence that an archetype is open at the table.
- Avoid overreacting to one early pick; communicate when evidence is weak or conflicting.
- Update recommendations as the draft evolves.
- Surface splash considerations: fixing availability, color requirements, mana curve, and the opportunity cost of adding a color.
- Explain when a card is attractive in isolation but poor for the current pool, and when a speculative pick may keep options open.

Archetype openness and splash advice are future scoring capabilities. The current standalone GIH WR evaluator does not provide them.

## Interactive visual mockup

The macOS app includes a **Draft Cockpit** tab alongside the existing **Capture Lab**. The cockpit tab is a static-data SwiftUI prototype for reviewing hierarchy, visual density, and interaction concepts. It is not connected to ScreenCaptureKit, card recognition, the draft event store, or recommendation scoring.

The mockup includes a pre-draft setup view, illustrative card rows, unresolved-card treatment, a secondary wheel-watch indicator, explicit pick confirmation, a drafted-pool summary, early strategy context, a dual-source score comparison panel, and a missed-pick recovery sheet. Its controls and example score values demonstrate intended interaction only; no changes are persisted or connected to the scoring engines.

## Presenting predictive and empirical scores

A card may have two independent score sources. Show them as distinct evidence, never as a combined grade:

- **Oculus predictive:** the pre-17L feature model's baseline power, role value, synergy potential, archetype-specific fit, and context sensitivity. Show model version, confidence, and concise rationale on selection/details. A high context-sensitivity value means the card's value varies more with conditions; it does not mean the card is stronger.
- **17Lands empirical:** the regularized GIH score from the selected compatible dataset, alongside raw GIH win rate, copy-weighted observation count, event/user-group/color scope, and snapshot identity. Do not present the regularized value as the raw win rate or as an independent-game confidence estimate.
- **Availability:** show whichever source exists. Missing values stay unavailable; do not use zero, borrow a value from another source, or hide the source's scope.
- **No blended ranking:** the five predictive dimensions are not interchangeable and have no validated weights. Do not average them with each other or with 17Lands. A future pick-ordering function needs its own explicit inputs, validation, version, and explanation.

The current SwiftUI cockpit displays an illustrative example of this hierarchy. The website's archetype card detail displays published score artifacts only; it never runs scoring in the browser. Neither surface is yet connected to a live draft session.

## Main draft workspace

Recommended hierarchy:

```text
┌────────────────────────────────────────────────────────────────────┐
│ Set · Format · Draft session · P2P4 · Data status · Capture status  │
├──────────────────────────────────────┬─────────────────────────────┤
│ CURRENT PACK                         │ YOUR DECK                   │
│                                      │                             │
│ 01  Card name             Score      │ Color counts                 │
│ 02  Card name             Score      │ Mana curve                   │
│ 03  Unresolved card       —          │ Creatures / noncreatures     │
│ 04  Card name             Score      │ Drafted cards                │
│                                      │                             │
│ [Confirm selected pick]              ├─────────────────────────────┤
│                                      │ STRATEGY                    │
│ Pack history                         │ Likely archetypes            │
│  P1  P1P1 … P1P8                     │ Color direction              │
│  P2  Current                         │ Splash / fixing context      │
└──────────────────────────────────────┴─────────────────────────────┘
```

This is a conceptual hierarchy, not a fixed pixel layout. The workspace must adapt to window resizing and remain useful at narrower widths. The pack remains primary; deck and strategy panels may collapse into tabs or drawers on smaller windows.

## Interaction and state rules

- Capture observations, recognition hypotheses, user-confirmed picks, and corrections are distinct concepts.
- Recognition never directly mutates the authoritative drafted pool.
- A pick is not final merely because a card row was clicked; require an explicit confirmation action.
- The local draft event log is the source of truth. The visible deck is a projection of that log.
- Every recommendation is tied to the current pack, draft state, dataset snapshots, and scoring configuration.
- A new upstream dataset does not silently change recommendations midway through a session.
- Capture loss, permission loss, uncertain recognition, missing data, and stale data must have visible, recoverable states.
- Never automate Arena input or selection. The user makes every pick in Arena.

## Accessibility and visual behavior

- Use the Urza's Oculus brand guide and native macOS conventions.
- Use color as a secondary cue, never the only identifier.
- Maintain legible text and strong selected/unresolved/confirmed states.
- Avoid dense tables of tiny numbers; show a score with optional explanation rather than exposing every metric by default.
- Support keyboard navigation and VoiceOver labels for card rows and confirmation controls.
- Keep status messages concise and persistent enough to notice without being disruptive.

## Product acceptance scenarios

1. A returning user launches Oculus and can tell whether Scryfall and 17Lands data are current.
2. The user selects an event type and a set sorted newest release first, starts a session, and receives an optional archetype briefing.
3. A pack is opened and scanned across multiple scroll positions; recognized cards accumulate while unresolved slots remain visibly unresolved.
4. The user confirms a pick; the selected instance leaves the available pack and appears in the drafted pool.
5. The user can reopen a previous pack and see the best-known historical contents, including updated wheel observations.
6. The deck panel updates its list, colors, curve, and creature/noncreature counts after every confirmed pick.
7. Archetype and splash guidance explains its evidence and uncertainty and does not overstate table openness.
8. A recognition error can be corrected without rewriting the original observation or silently corrupting the draft history.
9. A capture interruption or app restart does not lose confirmed picks once session persistence is implemented.

## Wheel likelihood indicator

A compact wheel-watch icon may appear on a card row when available evidence suggests the card has a meaningful chance to return. It is a decision aid, not a guarantee or a substitute for the recommendation score.

- Show the indicator only when the estimate has a defensible basis, such as pick position and compatible historical pick/wheel data.
- Keep the indicator secondary to the card name and recommendation.
- Provide a short explanation on hover or selection, including the evidence basis and uncertainty.
- Do not show a numeric probability until the model is calibrated and its meaning can be explained.
- Absence of the indicator means "no useful estimate," not "will not wheel."

## Recovering a pick that Oculus did not observe

A missed capture must not force the player to reconstruct the whole deck manually. Use the following recovery order:

1. **Resolve from the last observed pack.** If the pack contents and current pick are known, ask which card instance the player selected. Preserve the original observations and append a user-confirmed recovery/correction event.
2. **Reconcile against Arena's deck view.** If the relevant pack is unavailable or too incomplete, offer a guided deck-review flow. Capture multiple scroll positions, accumulate the visible deck entries, and compare the resulting pool with the event log. The deck view is a reconciliation source, not the authoritative history of what happened at each pick.
3. **Manual card search as a last resort.** If neither pack evidence nor a complete deck review can resolve the discrepancy, allow the player to search/select the card and clearly mark the event as manually recovered.

The recovery UI should explain what is known and what is uncertain. Never silently infer a pick merely because a card disappeared from a later pack frame. If multiple copies or identical card instances are possible, retain instance-level identity where available and ask for clarification only when it changes the resulting pool.

## Delivery sequence

This specification does not change the current Phase 0 gate. Validate real capture first. Then implement recognition and pack accumulation, followed by the confirmed-pick workflow and persistent draft history. Deck analytics and strategic recommendations build on reliable draft state.

## Open design questions for later validation

- Should the user confirm picks only in Oculus, or should Arena selection be independently observed before the event is committed? The intended behavior is explicit user confirmation plus a separate observation of Arena state where feasible.
- Should card rows default to pack order or a separately validated pick-ordering model? Until a pick-ordering function is validated, do not sort by an average of predictive dimensions and 17Lands metrics.
- How should the layout adapt to compact windows and different display sizes?
- Which exact archetype source and licensing/attribution requirements apply to each set?
- Which deck analytics are essential during the draft versus useful only after it?
- What evidence is sufficient to say an archetype is open, rather than merely that the user is drafting toward it?
