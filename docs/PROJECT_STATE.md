# Project state and accumulated decisions

Last reviewed: 2026-11-22

This is the durable project handoff, consolidating decisions and findings previously spread across PRs, workflow artifacts, and planning discussions. It complements [steering](PROJECT_STEERING.md), [architecture](ARCHITECTURE.md), [roadmap](ROADMAP.md), [decision records](DECISIONS.md), and the [Draft Cockpit UX specification](DRAFT_COCKPIT_UX.md).

## Product and current reality

Urza's Oculus is an independent native macOS companion for Magic: The Gathering Arena drafting. The intended product combines local observation, explicit/correctable draft history, versioned card and format data, and deterministic recommendations with visible evidence. It is a player aid, not an autopicker.

**Current milestone: Phase 0 — real-world capture validation.** The distributed app can enumerate visible/shareable macOS windows, suggest likely iPhone Mirroring windows using an advisory heuristic, let the user select a target, capture a still frame, and collect a bounded three-second sequence (up to 4 fps, maximum 20 frames). It does not provide continuous capture. The immediate action is to install the app and use Capture Lab during a representative Arena draft. Review scrolling, pack transitions, frame isolation, dimensions/cadence, repeated/dropped frames, permissions, and card-text legibility. Do not begin substantial OCR work until these frames are reviewed.

**Not implemented or integrated:** OCR, card recognition, automatic pack tracking, persistent user-facing draft sessions, and live pick recommendations. A static Draft Cockpit UI prototype exists, but is not connected to capture, recognition, persistence, or scoring.

Independent foundations already exist:
- Append-only draft-event model with pack observations, confirmed picks, corrections, validation, and deterministic replay tests; persistence/integration remain future work.
- SQLite card-reference store and Scryfall importer.
- 17Lands public archive acquisition, CSV parsing, game/draft metric aggregation, snapshots, provenance, freshness, and recommendation readiness.
- Shared platform-independent Swift evaluator for a regularized standalone GIH WR baseline.
- Reviewed Wizards archetype taxonomy and 62 reviewed card relationships across HOB/ECL/TDM, enriched with Scryfall identities and presentation metadata.
- Reproducible HOB set-speed and two-color performance-proxy audits.
- Hugo website and automated macOS DMG/ZIP releases.

Do not describe independent foundations as a complete connected workflow.

## Architecture and hard boundaries

1. **CaptureEngine** obtains local, window-scoped observations. The user selects the target; capture does not identify cards or mutate draft state.
2. **RecognitionEngine** will perform local OCR and card/layout interpretation, retaining source observations, coordinates, confidence, and ambiguity. It is currently a placeholder.
3. **DraftEngine** owns authoritative append-only events. Recognition proposes observations; explicit confirmation creates picks; corrections append events. The drafted pool is a projection of event history.
4. **DataEngine** owns card identity, imports, snapshots, provenance, freshness, and readiness.
5. **ScoringEngine** owns the only recommendation implementation, in the platform-independent Swift core. App and batch/CI adapters call the same evaluator. The website may display published artifacts but must never reimplement scoring.
6. **CollectionEngine** is optional future context and must not be required by the core draft workflow.

Non-negotiable constraints:
- Local, deterministic, explainable active-draft processing. No runtime AI inference, cloud inference, paid API, or server dependency.
- No network dependency during an active draft; network is for explicit data acquisition/refresh.
- No automated Arena clicks, keyboard/touch input, selection, or interaction. No overlay over the mirrored game.
- Captured screen contents remain local; never transmit or commit them.
- Keep capture, recognition hypotheses, confirmed picks, corrections, data, and scoring distinct and testable.
- Missing data is missing, never zero. Preserve set/event/user-group/color scope, snapshot identity, source update time, local acquisition time, and provenance.
- Do not claim exact 17Lands parity while whole-game eligibility remains unresolved.
- iPhone Mirroring is the initial capture source. Domain logic must remain independent of capture-source details.

## Data and recommendation methodology

### 17Lands baseline

The current evaluator regularizes GIH WR toward an explicit overall game win-rate baseline from the same set/event/user-group scope and exact game snapshot:

`score = (GIH_WR × GIH_count + baseline_WR × prior_weight) / (GIH_count + prior_weight)`

GIH count is a count of card-copy observations, not independent games. Do not use it as a binomial sample size or claim confidence intervals from it. Prior weight is a versioned tuning parameter. ALSA and ATA are context only and do not affect this baseline ranking. Synergy, archetype, curve, and deck-needs adjustments are not implemented.

The public game archive lacks a documented whole-game validity/deck-linkage flag equivalent to 17Lands' exclusion of inconsistent games. Oculus currently aggregates rows with valid win outcomes and does not reproduce that whole-game exclusion. Exact parity is not claimed. The HOB replay-backed audit matched all 323,114 game keys to replay keys one-to-one, with no deck/sideboard count mismatches or opening-hand counts exceeding main-deck counts. This supports export consistency for that sample; it does not establish upstream eligibility or validate every in-game hand.

### HOB PremierDraft analysis baselines

These are descriptive results for one archive, not universal set truths or live scoring inputs.

- **Set speed:** 323,114 games; median 9 turns; P25/P75 7/10; P90 12. 6.4% ended by turn 5, 16.9% by turn 6, 32.5% by turn 7, and 35.0% reached turn 10+. Overall tracked-user win rate was 56.2%. On-play/on-draw win rates were 60.8%/51.5%, descriptive only.
- **Two-color proxy performance:** 323,114 source rows; 70,362 valid deck identities; 323,111 included games; one conflicting deck identity excluded. Overall pooled win rate 56.2% (deck-cluster bootstrap 95% interval 56.0–56.3%). BR 57.6% (+1.9 percentage points versus the rest); BG 56.9% (+0.9 pp); UB 53.2% (-3.1 pp); UG 52.5% (-3.9 pp). WG was 49.7% with only 326 decks. These are main-color-pair proxies, not official archetypes; not adjusted for skill, rank, date, or multiple comparisons. They must not alter live recommendations without a separate decision.

### Wizards archetypes and reviewed card relationships

Reviewed taxonomy from official Wizards overview images:
- HOB: five two-color archetypes.
- ECL: five featured two-color typal archetypes plus five overlapping two-color mechanical themes.
- TDM: five three-color clans plus five overlapping two-color themes.

The manually reviewed card catalog has 62 cards explicitly associated with archetype plans: HOB 26, ECL 19, TDM 17. All 62 have Scryfall identities and display metadata. Roles are Oculus editorial classifications (enabler/payoff/supporting): HOB 8/6/12, ECL 8/3/8, TDM 4/9/4. Scryfall enrichment adds identity/display metadata; it does not create or change relationships.

The guides primarily teach Sealed/Prerelease and describe design intent, not Draft pick order, strength, or win-rate contribution. TDM does not provide equivalent card lists for all five two-color themes; do not invent them. Published archetypes, historical pick behavior, empirical performance, and live-pack evidence are separate layers.

### Mana curve guidance

Wizards' reviewed generic 40-card Sealed template across HOB, ECL, and TDM is 1 mana: 1–2; 2 mana: 7–8; 3 mana: 5–6; 4 mana: 3–4; 5 mana: 2–3; 6 mana: 0–1; 17 lands. This is a Sealed baseline, not a validated Draft recommendation or fixed target. HOB Adventures should be counted by the mode expected to be cast; ECL UR Elementals is expected to curve higher due to MV4+ spells and ramp; TDM Omens should be counted by the mode actually used. Keep printed mana value, effective casting cost, alternate modes, early utility, ramp, and cost reduction distinct.

## Lane-reading guardrails

Pack direction changes: Pack 1 travels left (incoming packs from the right), Pack 2 travels right (from the left), Pack 3 travels left again. Keep evidence separated by pack and direction. Potential signals include premium cards passed later than expected, signposts relative to historical pick/ALSA expectations, quality-weighted color depth, repeated supporting-card arrivals, and wheel returns.

A late signpost is an early clue, not proof of an open lane. A signpost alone cannot move confidence from insufficient to supported. Corroboration should come from supporting-card depth, independent packs, or meaningful wheel evidence. A weak signpost does not invalidate strong supporting-card evidence. Use qualitative states: Early signal, Developing, Supported, Conflicting, Insufficient evidence. Show the strongest one or two observations and pack/direction. Missing expected cards are weak contrary evidence because absence is ambiguous. No numeric probabilities or force/abandon-color instructions without calibration. Lane analysis should initially be informational, not silently change rankings.

## Draft Cockpit UX contract

The accepted workspace has three coordinated areas: **current pack** (primary), **drafted pool/deck** (confirmed picks, color counts, curve, creature/noncreature mix), and **strategic context** (evidence-backed archetype/color hypotheses and splash/fixing). Before joining Arena, the user selects set/event in Oculus and checks local data readiness. A session pins its data snapshots; refreshes must not silently change recommendations mid-draft. Archetype briefing is optional. Pack observations accumulate across scrolling; unresolved/ambiguous cards remain visible. Picks require explicit confirmation. Pack history distinguishes known picks, wheel observations, and cards merely absent from later frames. Missed-pick recovery order: last observed pack, Arena deck view, then manual search. See [DRAFT_COCKPIT_UX.md](DRAFT_COCKPIT_UX.md). This is accepted design, not implemented behavior.

## Delivery sequence

1. **Phase 0 — Capture validation:** maintainer tests the installed app during a representative Arena draft and records window selection, frame isolation, dimensions/cadence, scrolling, pack transitions, permissions, and OCR suitability.
2. **Phase 1 — Recognition:** only after capture passes, implement local Vision OCR, pack/card regions, local Scryfall matching, and explicit ambiguity states.
3. **Phase 2 — Draft tracking:** persist sessions/events; integrate observations, explicit pick confirmation, corrections, replay, and missed-pick recovery.
4. **Phase 3 — Recommendation integration:** connect exact recognized IDs and confirmed draft state to compatible snapshots and the shared evaluator. Resolve or bound readiness/eligibility caveats. Add contextual scoring only behind explicit contracts/tests.
5. **Phase 4 — Integrated companion:** validate full capture-to-recommendation workflow with real drafts.
6. **Phase 5 — Public data views:** publish versioned artifacts generated by the shared Swift core; website remains presentation only.

Do not let further data analysis delay capture validation unless it identifies a material correctness issue.

## Set discovery and acquisition

The repository now has a weekly read-only discovery workflow comparing Scryfall Limited set releases, 17Lands public archive availability/freshness, and local reviewed archetype/card coverage. A separate manual acquisition workflow downloads Scryfall card metadata, only 17Lands archives actually published for the selected event, and optional official Wizards guide evidence. Outputs are immutable candidate artifacts; human review and promotion remain separate. See [SET_DISCOVERY_AND_ACQUISITION.md](SET_DISCOVERY_AND_ACQUISITION.md).

## Releases and repository workflow

The macOS app is distributed as a DMG and ZIP through GitHub Releases after successful macOS CI on main. Stable DMG: `https://github.com/sedward5/urzas-oculus/releases/latest/download/UrzasOculus.dmg`. Website-only and Python-only changes do not publish app releases. Current builds are ad-hoc signed, not Developer ID signed or notarized; macOS may warn on first launch. Hugo deploys through Cloudflare Pages; GitHub Actions validates builds. Keep PRs bounded; the maintainer reviews and merges. Never merge without explicit approval.
