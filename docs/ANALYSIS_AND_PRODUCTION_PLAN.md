# Data Analysis and Production Plan

## Product goal

Ship a useful first production draft assistant without waiting for perfect statistical parity. Keep the scoring engine honest about uncertainty, version every output, and improve the evidence in small, bounded steps.

The work is split into release-enabling work and analytical enhancements. No analysis should become an indefinite blocker unless it reveals a correctness issue that would make recommendations misleading.

## Release principle: useful, transparent v1

The first production release may use the current 17Lands-derived metrics and scoring model while the game-eligibility question remains under investigation.

Requirements:
- Keep one Swift scoring core as the source of truth for app and CI artifacts.
- Version the scoring configuration, engine, and artifact schema.
- Preserve dataset provenance, event type, set, source coverage, and import timestamps.
- Label scores as provisional where unresolved source eligibility could affect interpretation.
- Do not claim exact 17Lands parity.
- Do not silently discard games using an unvalidated heuristic.
- Make recommendations useful even when contextual analyses are unavailable.
- Add explicit readiness states: ready, ready-with-caveats, and unavailable. A caveat should not disable the core draft workflow.

A future evidence-based eligibility rule can increment the engine/config version and regenerate artifacts. It should not require redesigning the cockpit.

## Analysis workstreams

### 1. Replay-backed game-data quality (next task)

Question: Can replay records independently validate deck composition and opening-hand observations in the game archive?

Inputs:
- Official 17Lands game archive.
- Official 17Lands replay archive.
- Join key: draft_id, build_index, match_number, game_number.

Checks:
- Key coverage, duplicates, and missing identity.
- Per-card main-deck count agreement between deck_ columns.
- Per-card sideboard count agreement between sideboard_ columns.
- Opening-hand card counts do not exceed corresponding main-deck counts.
- Report unmatched and discrepant records separately.
- Preserve representative examples, but do not dump unnecessary raw data.
- Treat candidate-hand fields as opaque until their encoding and semantics are independently established.
- Do not use total drawn/tutored counts as a deck-validity check; game effects can change how often a card is drawn or tutored.

Deliverable: a reproducible audit report with denominators, mismatch rates, representative examples, and explicit interpretation limits.

Exit decision:
- If fields agree, record replay evidence and retain the unresolved 17Lands eligibility question unless official semantics establish that this is the relevant validation.
- If they disagree, characterize mismatch patterns and seek authoritative field definitions before proposing an exclusion rule.
- Missing replay rows are not evidence that a game is invalid.

### 2. Set speed and format texture

Question: Does a set tend to reward fast starts, or does it support longer games?

Build set-level indicators from replay/game data:
- Turn-count distribution and median, not just a single average.
- Share of games ending by turns 5/6/7 and games reaching turns 10+.
- First-player versus second-player splits where supported.
- Win rate by game length, interpreted descriptively rather than causally.
- Creature/spell/land activity by turn as supporting context.
- Compare sets only within compatible event types, user groups, and comparable date/coverage windows.

Cockpit use:
- A compact set-speed profile (faster / balanced / slower) with the underlying median and distribution.
- A short explanation of what the profile means for curve pressure and defensive picks.
- No hard-coded labels based on community hearsay. TRK and Reality Fracture are hypotheses to test against measured data.

Guardrails:
- Avoid calling a set aggro from median game length alone.
- Account for format changes, player skill, event type, and sample size.
- Recompute when data coverage changes.

### 3. Archetype performance in the meta

Question: Which archetypes are performing above or below the format baseline?

Start with archetypes that can be assigned consistently from available data:
- Use official 17Lands archetype/color labels when present and documented.
- If unavailable, begin with transparent color-pair buckets; do not pretend these are refined archetypes.
- Compare win rate to the format baseline, with sample counts and uncertainty intervals.
- Show game count and deck count separately where the data supports both.
- Segment by event type and date window before comparing.
- Flag small samples and avoid ranking noisy archetypes as strong/weak.

Cockpit use:
- Set briefing: archetype performance and confidence.
- During draft: current colors/likely archetype compared with the set baseline.
- Post-draft: deck context, not a guarantee of expected win rate.

### 4. Open and closed lanes during a draft

Question: When is there enough evidence that a color or archetype is underdrafted at this table?

Signals to combine:
- Cards seen late relative to their pick distributions (ALSA and pick-position evidence).
- Wheel observations from the same physical pack.
- Repeated signals across multiple packs, not one attractive late card.
- Density and quality of playable cards in the user's current colors.
- Signals that contradict the hypothesis (strong cards missing early, low-quality late cards).
- Draft stage and pack direction.

Output should be a confidence-rated hypothesis, not a binary truth:
- Emerging signal: one or two weak indicators.
- Supported: multiple independent signals across packs.
- Strong: repeated wheel/late-pick evidence with coherent card quality.
- Insufficient evidence: default state.

Do not call a lane open solely because a card wheels. Some cards are low-demand, narrow, or weak. Do not call a lane closed solely because one premium card is absent.

Cockpit use:
- Explain the evidence and uncertainty.
- Distinguish open lane from your seat receiving playable cards.
- Update as the draft progresses; avoid false certainty in early picks.

### 5. Draft-time recommendation context

Combine the above only after each underlying analysis is independently validated:
- Base card score and role fit.
- Deck curve and role needs.
- Archetype synergy.
- Lane evidence.
- Set speed / format texture.
- Splash and mana consistency costs.

Keep the base card score visible. Context may adjust ranking, but should not hide why a card is recommended.

## Execution order and release checkpoints

| Stage | Work | Release impact |
|---|---|---|
| A | Replay-backed quality audit | Inform scoring caveat; not a release blocker |
| B | Freeze and label provisional v1 scoring | Enables production |
| C | Set-speed profile | Cockpit enhancement |
| D | Archetype meta report | Cockpit enhancement |
| E | Lane confidence model | Cockpit enhancement |
| F | Contextual ranking integration | Later improvement |

### Production checkpoint

Once the current scoring pipeline has repeatable imports, defensible metric calculations and fixtures, versioned artifacts, provenance and caveat metadata, and clear unavailable/insufficient-data behavior, we should ship v1 even if replay eligibility, set-speed classification, archetype strength, and lane inference are still being improved.

The analysis workstreams should produce bounded reports and decisions. If a question cannot be answered from available evidence, document the limitation and move to the next useful deliverable rather than endlessly expanding the investigation.
