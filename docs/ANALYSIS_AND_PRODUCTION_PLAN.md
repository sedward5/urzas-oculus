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
- Use pooled game wins divided by pooled games as the primary win-rate estimate, matching the familiar game-level win-rate measure.
- Show both distinct deck count and game count; do not present an unweighted mean of deck win rates as the headline metric. The first HOB run showed why: 48.2% unweighted mean deck win rate versus 56.2% pooled game win rate.
- Compare each color pair with the rest of the field, excluding that pair from its comparison baseline, rather than comparing it with a baseline that includes itself.
- Calculate deterministic 95% bootstrap intervals by resampling whole decks and recomputing pooled game win rates. Also bootstrap the pair-versus-rest difference. This preserves game weighting while avoiding treating games from the same deck as independent observations.
- The public archive does not expose a stable player identifier for clustering multiple decks from the same drafter, so repeated decks by one player may remain correlated.
- Keep mono-color and three-or-more-color decks in the overall baseline, but outside the two-color comparison table.
- Exclude and report deck identities whose main-color assignment conflicts or that contain any incomplete game rows; do not estimate their performance from only a valid subset of games.
- Keep splash colors separate from the main-color pair; do not silently convert a splash into a third archetype color.
- Do not call the ten color pairs ten distinct strategies. They can contain materially different archetypes.
- Do not rank noisy results as strong/weak or feed them into live recommendations.
- If a documented official archetype field becomes available, validate its semantics before replacing or supplementing these proxy buckets.

Cockpit use:
- Set briefing: archetype performance and confidence.
- During draft: current colors/likely archetype compared with the set baseline.
- Post-draft: deck context, not a guarantee of expected win rate.

Wizards-published archetype guidance is a separate future enrichment task. Revisit acquisition, licensing/availability, provenance, and update cadence after the data-to-repo artifact pipeline is established. Do not block the initial meta report on it.

#### Recorded baseline: HOB PremierDraft

Workflow run [44949303784](https://github.com/sedward5/urzas-oculus/actions/runs/44949303784), artifact `14724829292`:

- 323,114 source game rows; 70,362 valid deck identities; 323,111 valid games.
- One conflicting deck identity excluded (3 otherwise-valid game rows); no incomplete deck identities.
- 4,790 valid non-two-color decks remain in the overall baseline but are not in the exact two-color comparison table.
- Overall pooled game win rate: 56.2% (95% deck-cluster bootstrap interval 56.0–56.3%).
- BR: 17,476 decks / 85,459 games; 57.6%, +1.9 percentage points versus the rest of the field (95% delta interval +1.5 to +2.3).
- BG: 12,225 decks / 57,277 games; 56.9%, +0.9 pp (+0.4 to +1.3).
- UB: 2,959 decks / 12,745 games; 53.2%, -3.1 pp (-4.0 to -2.2).
- UG: 5,404 decks / 22,250 games; 52.5%, -3.9 pp (-4.6 to -3.3).
- The other pair comparisons' intervals include zero. WG had the lowest observed win rate (49.7%) but only 326 decks, so its exact rank is uncertain.

Interpretation: BR and BG were above the field in this sample; UB and UG were below it. These are descriptive color-pair proxy results, not official archetype evaluations. The intervals are nominal across ten comparisons and are not multiple-comparison adjusted. Results are not adjusted for player skill, rank, date, or event subgroup. The public archive has no stable player ID for clustering multiple decks from the same drafter.

**Taxonomy caveat:** Do not assume every set has ten two-color archetypes. Sets may feature five two-color archetypes, a subset of pairs, five three-color factions with overlapping two-color strategies, or other structures. A missing color pair is not a missing-data defect. Keep the full color-pair performance audit separate from the set's published archetype catalog. Never synthesize absent archetypes from the ten possible pairs.
 
### 3a. Published archetype catalog — acquisition investigation

Published archetype definitions are a separate, set-specific source layer that should contextualize (not replace) empirical color-pair performance.

Initial source investigation found that Wizards' Prerelease Guide pages expose an archetype section in HTML, with a labeled overview image and, in many cases, individual archetype headings, mana-symbol image alt text, descriptive prose, and card references. This is promising for repeatable acquisition, but not all information is duplicated in the HTML. For example, the Tarkir: Dragonstorm guide describes five three-color clans in prose while its labeled overview image also presents five overlapping two-color strategies. A heading-only scraper would miss those additional strategies.

#### Proposed acquisition pipeline

1. Discover the official Wizards Prerelease Guide URL for a set. Keep discovery separate from extraction so source changes are observable.
2. Fetch the article HTML and extract the archetype-section boundary, article title/date, section headings, text, mana-symbol image alt text, card references, and the image explicitly labeled as the archetype overview.
3. Download and preserve the overview image as source evidence. Run OCR on it for names and strategy descriptions that do not appear in article text. Treat mana-symbol recognition as a separate extraction problem; OCR text alone does not reliably identify the colors represented by symbol artwork.
4. Reconcile HTML and image candidates. Match by normalized name and colors only when evidence supports the match. Record extraction method and confidence per field.
5. Emit unresolved candidates for manual review. Never infer missing colors, invent archetypes from the ten possible pairs, or mark a set complete solely because extraction returned some rows.
6. Persist a normalized, versioned set catalog with source URL, article publication date, retrieval time, overview-image URL and checksum, extraction version, evidence references, and review status.

The catalog must support two-, three-, and potentially other-color identities. It must also support overlapping archetypes (for example, clan archetypes and two-color themes), distinguish an archetype's published name from its color identity, and allow the source to describe only a subset of the full Limited environment.

#### Signpost metadata and interpretation

Where the published guide identifies signpost cards, preserve those associations as catalog metadata rather than treating the cards as authoritative evidence that an archetype is strong or open.

For each signpost association, retain the evidence and, when available, join these independent attributes:
- Published archetype association and source evidence.
- Rarity and card identity.
- Historical ATA and ALSA for the same set/event scope.
- Game win rate when drawn, deck win rate when included, and inclusion rate in successful decks, with sample counts and scope.
- Explicit supporting-card or mechanical relationships when the source documents them; do not invent a support graph from color identity alone.

Keep four evidence layers distinct: published association describes intended strategy identity; historical pick behavior describes how players value the card; performance data describes observed outcomes; live pack observations describe what is arriving unusually late in this draft. A published signpost can be weak, unpopular, or simply passed by a drafter committed elsewhere. Its performance may also depend on being played in the intended shell.

Do not let a signpost alone establish that a lane is open or move lane confidence from insufficient evidence to supported. It can contribute an early signal. Stronger interpretation requires corroboration from other cards supporting the same strategy, repeated depth across independent packs, or meaningful wheel evidence. A weak signpost must not invalidate otherwise strong supporting-card evidence. Treat disagreement between design intent, pick behavior, and performance as a useful finding to investigate, not as a reason to discard the archetype.

#### Initial validation fixtures

- HOB: five published two-color archetypes, useful for validating the common case.
- Lorwyn Eclipsed: five featured two-color typal archetypes plus five other color-pair mechanical themes; useful for checking that a guide can explicitly distinguish featured and non-featured themes.
- Tarkir: Dragonstorm: five three-color clan archetypes plus five overlapping two-color strategies; useful for validating image-only or image-primary definitions.

Do not feed published definitions into scoring yet. First establish extraction coverage and manual-review accuracy across these contrasting layouts. The published catalog should later join to performance results by set and color identity, while preserving the distinction between a broad color-pair proxy and a named archetype.

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
- Signpost arrivals: when a published signpost is present later than its historical pick/ALSA expectations, record that as one archetype-specific observation. Compare actual arrival with the card's historical behavior and performance; do not use a fixed pick cutoff or treat gold rarity as proof of openness.
- Signpost corroboration: look for supporting cards from the same published strategy arriving later than expected, and for repeated evidence across independent packs. A signpost by itself is only an early clue; it is not sufficient to label a lane supported.
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
