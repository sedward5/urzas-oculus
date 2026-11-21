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

### 1. Replay-backed game-data quality — completed for HOB PremierDraft

The HOB audit joined game and replay archives using `draft_id`, `build_index`, `match_number`, and `game_number`.

Recorded result from workflow run [44857461613](https://github.com/sedward5/urzas-oculus/actions/runs/44857461613):
- 323,114 game rows and 323,114 replay rows; all keys matched one-to-one.
- No duplicate keys, missing identities, game-only keys, or replay-only keys.
- No main-deck or sideboard count mismatches.
- No opening-hand count exceeded the corresponding main-deck count.

This is strong evidence that the two exports agree on deck composition for this sample. It does not prove the upstream eligibility decision. The public game archive still lacks a documented whole-game validity flag, and the audit does not validate every in-game hand against deck/sideboard. Do not infer eligibility from drawn/tutored totals or undocumented candidate-hand fields.

### 2. Set speed and format texture — HOB PremierDraft baseline recorded

Question: Does a set tend to reward fast starts, or does it support longer games?

The first reproducible audit is `scripts/analyze_17lands_set_speed.py`, run by the manually triggered workflow `17lands-set-speed-audit.yml`. It streams the official game archive and emits a Markdown report plus a versioned JSON summary.

#### Recorded baseline: HOB PremierDraft

Workflow run [44861481947](https://github.com/sedward5/urzas-oculus/actions/runs/44861481947), artifact `14689985681`:

- 323,114 source rows and included games; no missing/invalid turn counts, results, or identity fields.
- Draft-time range: 2026-08-11 15:43:42 through 2026-09-22 23:31:56.
- Median 9 turns; P25 7, P75 10, P90 12.
- 6.4% ended by turn 5; 16.9% by turn 6; 32.5% by turn 7; 35.0% reached turn 10+.
- Overall tracked-user game win rate: 56.2%.
- On the play: 161,736 games, median 8 turns, 60.8% tracked-user win rate.
- On the draw: 161,378 games, median 9 turns, 51.5% tracked-user win rate.
- The historical `user_game_win_rate_bucket` field was present on 322,944 games; 170 included games lacked it. It is a fine-grained historical user win-rate bucket, not the official Top/Middle/Bottom performance grouping.

These are descriptive archive statistics, not causal findings. The play/draw win-rate gap and win-rate-by-game-length relationship should not be interpreted as causal effects. The baseline is a single set/event sample, not a comparative speed classification.

It measures:
- Turn-count distribution, median, and P25/P75/P90.
- Shares ending by turns 5, 6, and 7, plus games reaching turn 10+.
- First-player versus second-player splits when the `on_play` field is available.
- Optional historical user win-rate bucket breakdown, explicitly distinguished from 17Lands' official Top/Middle/Bottom performance groups.
- Descriptive win rate by game-length bucket and overall.
- Source coverage, missing/invalid fields, and draft-time range.

Guardrails:
- Treat the archive's `num_turns` value as supplied; do not reinterpret it as match length or a player-turn count without authoritative semantics.
- Win rate by game length is descriptive, not causal.
- Do not classify a set as faster/balanced/slower from one median. Compare compatible event types, populations, and overlapping date windows first.
- `user_game_win_rate_bucket` is not the official Top/Middle/Bottom performance group. Report it only as a historical user win-rate bucket and count missing values.
- The public game archive may omit inconsistent games. This audit does not reproduce 17Lands' eligibility filter.
- Per-turn creature/spell/land activity is deferred until the raw replay-turn schema is independently verified.

Cockpit use after analysis: a compact faster/balanced/slower profile with median and distribution, plus a short explanation of curve pressure and defensive-pick implications. No hard-coded labels based on community hearsay.

### 3. Archetype performance in the meta — first reproducible audit implemented

Question: Which archetypes are performing above or below the format baseline?

First pass: use transparent two-color buckets from the game archive's `main_colors` field. This is a color-pair proxy, not a refined archetype taxonomy.

- Identify a deck by `(draft_id, build_index)`; do not treat every game as an independent deck sample.
- Calculate each deck's game win rate, then report the unweighted mean across decks for each color pair.
- Show both distinct deck count and game count.
- Compare against the all-deck baseline from the same archive, event type, and date coverage.
- Include a deterministic 95% bootstrap interval over deck-level win rates. The public archive does not expose a stable player identifier for clustering multiple decks from the same drafter, so describe this as deck-level uncertainty rather than a fully player-clustered population interval.
- Keep mono-color and three-or-more-color decks in the overall baseline, but outside the two-color comparison table.
- Exclude and report deck identities whose main-color assignment conflicts across their game rows.
- Keep splash colors separate from the main-color pair; do not silently convert a splash into a third archetype color.
- Do not call the ten color pairs ten distinct strategies. They can contain materially different archetypes.
- Do not rank noisy results as strong/weak or feed them into live recommendations.
- If a documented official archetype field becomes available, validate its semantics before replacing or supplementing these proxy buckets.

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
