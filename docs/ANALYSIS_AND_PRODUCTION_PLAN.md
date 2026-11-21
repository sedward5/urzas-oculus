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

Wizards-published archetype guidance is a separate future enrichment task. Revisit acquisition, licensing/availability, provenance, and update cadence after the data-to-repo artifact pipeline is established. Do not block the initial meta report on it.

### 4. Within-draft lane reading (priority cockpit analysis)

Question: During this draft, what are the players passing to us likely *not* taking, and how confident should we be?

This is not the same as set-level archetype performance. Historical pick data supplies expectations; the live draft supplies evidence. The cockpit should help the drafter notice unusual signals early, including before the first wheel, without presenting a premature verdict.

#### Direction matters

- Pack 1 travels left, so each pack reaches us from the player on our right. The cards arriving to us are evidence about the seats on our right.
- Pack 2 travels right, so packs reach us from the player on our left. It gives us a different view of those seats.
- Pack 3 travels left again, returning to the right-side signal.
- Keep evidence separated by pack and direction. Do not average Pack 1 and Pack 2 into one undifferentiated table signal.
- A signal from Pack 1 may be confirmed, weakened, or contradicted when the direction reverses.

#### Signals available before the wheel

Use the current pick and pack contents to compare what arrived with what would ordinarily be expected at that pick:
- Premium-card arrivals: a high-impact rare or mythic still present later than expected is a meaningful *observation*, but one card alone is not proof of an open color.
- Quality-weighted color supply: count and weight the cards in the pack by color using set-specific card strength and pick-position/ALSA expectations. The question is not merely “are there good blue cards?” but “is the quality and depth of a color unusually high for this pick?”
- Unexpected depth: multiple playable cards in the same color, or multiple strong cards across a coherent strategy, can be more informative than a single standout.
- Missing expected cards: cards that would commonly survive to this pick but are absent can be weak contrary evidence. Absence is ambiguous because we do not know exactly what each seat saw or chose.
- Compare against the historical distribution for the same set and event type, not a universal pick threshold.

The early read should be phrased as an observation such as “unusually strong white cards are reaching you” or “white is showing repeated late depth,” not “white is open.” It should be possible to show a rare/bomb signal even before enough evidence exists to infer a lane.

#### Wheel and multi-pack evidence

- Track physical-pack identity and whether cards from that same pack return.
- A wheel is useful evidence about the seats that saw the pack, but a low-demand card wheeling is not equivalent to a premium card wheeling.
- Look for repeated signals across different packs, not just repeated cards from one pack.
- Track positive and negative evidence: late quality, repeated color depth, premium cards missing early, and weak/noisy cards arriving late.
- Do not equate “playables are arriving in my colors” with “the lane is open.” The former may simply be a good pack.

#### Confidence and UI

Use a small, explainable status above the archetype/meta section:
- **Early signal** — one notable arrival or an unusual quality/depth observation. Useful to notice, not enough to move in.
- **Developing** — more than one independent observation supports the same color/strategy during the pack.
- **Supported** — repeated evidence across packs or a meaningful wheel, with card quality consistent with the hypothesis.
- **Conflicting** — evidence points in different directions or reverses after a pack-direction change.
- **Insufficient evidence** — default when the sample is too small or the signal cannot be calculated.

Show only the strongest one or two signals, with concise evidence (“premium white rare at P5; two additional above-baseline white cards”) and a direction/pack marker. Allow a tap/expand for detail. Avoid a large color heatmap or a numeric probability in v1.

The UI must distinguish:
- what was directly observed,
- what historical data says would be unusual,
- the current interpretation,
- and the confidence/limitations.

Do not tell the user to abandon a color, force a color, or take a card solely because of a lane indicator. Lane evidence is context for a human pick, not a replacement for card evaluation.

#### Validation plan

- Build a replayable draft timeline from observed pack contents and pick sequence.
- Use historical 17Lands pick/ALSA distributions as the baseline, segmented by set and event type.
- Start with transparent, interpretable features: card quality percentile at observed pick, color quality/depth relative to expectation, premium-card late arrivals, and same-pack wheel outcomes.
- Evaluate signal timing: how early it appears, whether it persists, and how often it is contradicted after the direction changes.
- Review complete draft examples manually, including false positives and drafts where a lane genuinely becomes clearer before the wheel.
- Calibrate labels against evidence; do not hard-code “P5 means open” or a fixed count of cards.
- If historical baselines or live observations are insufficient, show “insufficient evidence” rather than inventing a read.

First deliverable: a bounded analysis report and a small set of replay fixtures demonstrating early signal, supported signal, conflicting direction, and insufficient evidence. Then implement the compact cockpit indicator. Do not wait for perfect lane prediction before shipping a useful observational v1.

### 5. Draft-time recommendation context

Combine the above only after each underlying analysis is independently validated:
- Base card score and role fit.
- Deck curve and role needs.
- Archetype synergy.
- Lane evidence.
- Set speed / format texture.
- Splash and mana consistency costs.

Keep the base card score visible. Context may adjust ranking, but should not hide why a card is recommended. Lane signals should initially be informational; do not let an uncalibrated lane score silently change card rankings.

## Future data delivery

A near-term follow-on should make the analysis workflows publish versioned, machine-readable set artifacts into the repository (or a dedicated data branch/path) consumed by both the macOS app and the website. The website should be able to display set metrics from the same generated data the app uses; avoid separate calculations or duplicated definitions.

Artifacts should include schema/engine version, set and event identity, source coverage, generated/import timestamps, sample counts, caveats, and readiness. This is intentionally not part of the current replay-audit task, but should be scheduled soon after the first analyses establish stable schemas.

## Execution order and release checkpoints

| Stage | Work | Release impact |
|---|---|---|
| A | Replay-backed quality audit | Inform scoring caveat; not a release blocker |
| B | Freeze and label provisional v1 scoring | Enables production |
| C | Set-speed profile | Cockpit enhancement |
| D | Archetype meta report | Cockpit enhancement |
| E | Within-draft lane-reading analysis and observational UI | High-value cockpit enhancement; v1 can show explainable early signals |
| F | Shared set-metric artifacts for app and website | Follow-on data delivery milestone |
| G | Contextual ranking integration | Later improvement |

### Production checkpoint

Once the current scoring pipeline has repeatable imports, defensible metric calculations and fixtures, versioned artifacts, provenance and caveat metadata, and clear unavailable/insufficient-data behavior, we should ship v1 even if replay eligibility, set-speed classification, archetype strength, and lane inference are still being improved.

The analysis workstreams should produce bounded reports and decisions. If a question cannot be answered from available evidence, document the limitation and move to the next useful deliverable rather than endlessly expanding the investigation.
