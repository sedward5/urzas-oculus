# Prediction and Card Evaluation Model v1

**Model version:** `prediction-v1`  
**Result schema:** `1`  
**Status:** Initial model specification; the structural role suggester is implemented, while full set review, rating, and calibration workflows remain in progress.

## Purpose

Oculus must be able to evaluate a Limited set before performance data exists. This model records that pre-release prediction as a durable, explainable artifact. Later pick behavior, game performance, and 17Lands public datasets add observations that can test the prediction; they do not replace it.

The model has two related but distinct jobs:

1. **Classification:** describe what a card does and which jobs it can fill.
2. **Evaluation:** assess how well it performs those jobs, how strong it is in isolation, and how context changes its value.

A classification is not a grade. A card can fill several roles, and each role can have different confidence and evidence.

## Evaluation dimensions

Each dimension is assessed independently on an ordinal 1–5 scale. The scale is not a percentage, percentile, probability, or grade. A missing value means not assessed; it never means zero.

| Value | Meaning |
|---:|---|
| 1 | Weak: materially below the expected contribution for this dimension |
| 2 | Limited: useful but meaningfully constrained |
| 3 | Functional: meets a normal Limited expectation |
| 4 | Strong: meaningfully above the normal expectation |
| 5 | Exceptional: unusually powerful or efficient in this dimension |

The five dimensions are:

- **Baseline power:** contribution without requiring a particular synergy package or narrow board state.
- **Role value:** quality and reliability in the jobs the card performs (for example removal, card advantage, fixing, or early defense).
- **Synergy potential:** how well the card enables, rewards, or participates in interactions with other cards.
- **Archetype fit:** how strongly the card advances an explicitly identified set strategy. The review schema stores a separate 1–5 assessment for each named archetype, because a card can be an excellent fit in one lane and a poor fit in another. Fit is not inferred from color identity alone.
- **Context sensitivity:** how much the card's value changes with board state, format speed, deck composition, or matchup. This is a descriptive dimension: a high value means the card is especially context-dependent, not especially strong.

Every dimension assessment includes rationale, evidence, and confidence. Do not average the five dimensions into one number in v1. The dimensions answer different questions and have no validated exchange rate.

## Role taxonomy

Roles are multi-label. A card can be an enabler and a payoff, or removal and card advantage, at the same time.

Core roles:

- **Removal:** permanently or temporarily answers an opposing permanent or threat.
- **Interaction:** disrupts spells, abilities, combat, or an opponent's plan; includes removal but is broader.
- **Enabler:** supplies a resource, condition, or action that makes another card/strategy work.
- **Payoff:** rewards the player for executing a strategy or assembling a condition.
- **Build-around:** asks for deliberate deck construction or a meaningful density of support.
- **Card advantage:** generates access to additional cards or resources beyond a simple one-for-one exchange.
- **Two-for-one:** can reasonably exchange one card for two or more opposing cards, or generate two relevant cards/permanents from one card. Record the mechanism and assumptions; token creation alone is not automatically a two-for-one.
- **Modal:** offers a meaningful choice among modes or outcomes. Record the mode count, timing, restrictions, and whether modes are mutually exclusive.
- **Ramp:** accelerates mana availability or reduces the time needed to deploy resources.
- **Fixing:** improves access to colors or required mana.
- **Curve filler:** contributes a relevant body or effect at a point on the mana curve.
- **Evasion:** makes combat damage more reliable.
- **Combat trick:** changes combat math or combat outcomes, usually temporarily.
- **Resilient threat:** is unusually difficult to remove or replace.
- **Finisher:** closes a game or converts an established advantage into a win.
- **Sweeper:** affects multiple creatures or permanents, often across both sides.
- **Recursion:** reuses cards or resources from a graveyard or other zone.
- **Token maker:** creates one or more tokens.
- **Sacrifice outlet:** lets the player sacrifice a permanent as a cost or repeatable action.
- **Graveyard hate / artifact hate:** meaningfully disrupts the relevant resource or permanent type.
- **Lifegain:** gains life as a meaningful part of the card's function.

Roles describe function, not strength. A card may be classified as removal even if its removal is too conditional to be a good Limited pick.

## Rate assessment

The separate rate field is one of:

- `belowRate`
- `onRate`
- `aboveRate`
- `exceptional`
- `contextDependent`
- `insufficientEvidence`
- `notApplicable`

"On rate" is a comparison against the expected Limited cost for the effect, body, timing, restrictions, and set environment. It is not a keyword lookup or a generic mana-value formula.

Reviewers must consider at least:

- Mana and color requirements, including how difficult the card is to cast on curve.
- Effect magnitude, targets, restrictions, timing, and speed.
- For creatures: stats, relevant keywords, ETB/death/attack triggers, and combat role.
- Whether the card replaces itself, creates material, or incurs card disadvantage.
- Whether alternate modes or costs materially change the effective rate.
- Format speed and the expected threats it must answer.

A removal spell is not automatically efficient because it destroys a creature. Compare what it answers, what it costs, when it can be used, and what it gives up. A modal spell is not automatically flexible in practice if one mode is rarely relevant or the modes compete for timing/resources.

Set-specific benchmarks should be documented and versioned. Do not create a universal numeric mana-to-effect conversion without evidence.

## Structural suggestions versus reviewed truth

The engine may produce deterministic **suggestions** from card type and rules text. These are review prompts, not confirmed classifications. The current structural suggester detects obvious textual patterns such as targeted destroy/exile/bounce, damage to targets, mana production, land search, draw, token creation, explicit modal choices, graveyard return, sacrifice costs, evasion, and power/toughness modification.

These rules intentionally do not infer card strength, two-for-one status, archetype fit, or on-rate status. A matched phrase may be conditional, costly, symmetrical, narrow, or strategically irrelevant. Human review must confirm, reject, or refine every suggested role before it appears as a reviewed classification.

A missing suggestion is not proof that a role is absent. Oracle text parsing is not a rules engine; alternate faces, reminder text, replacement effects, and unusual wording require review.

## Evidence and confidence

Evidence classes:

- **Structural:** card text, mana cost, type line, stats, keywords, face/layout data, and explicit mechanics.
- **Official:** Wizards set guides, mechanics articles, and official format material.
- **Expert:** attributed limited reviews or analysis with author and publication.
- **Observational:** draft pick behavior, game outcomes, and other measured format data.
- **Inferred:** Oculus reasoning derived from other evidence.

Confidence is recorded separately as low, medium, or high. Confidence describes certainty in the claim, not the card's strength. Evidence type does not mechanically determine confidence. Every nontrivial classification and dimension score needs a concise rationale and traceable evidence. Inferred claims should identify the evidence they depend on.

## Predictions, observations, and calibration

Keep three layers distinct:

1. **Card identity:** Scryfall printing ID, Oracle ID, set, faces, and immutable source facts.
2. **Card understanding/prediction:** versioned role annotations, five dimension assessments, rate assessment, rationale, reviewer, and evidence.
3. **Observed performance:** independently sourced pick/game metrics, exact scope, snapshot, sample counts, and source update/acquisition timestamps.

A new review creates a new version; it must not overwrite the historical prediction used for a prior evaluation. A correction should preserve the prior record and explain what changed.

Lifecycle:

- **Pre-release:** structural, official, and expert evidence. This is the primary prediction stage and must work with no 17Lands data.
- **Early format:** add observational evidence when permitted data exists. Report sample size and limitations. Do not silently rewrite the pre-release prediction.
- **Mature format:** compare predictions with sufficiently supported observations; identify systematic misses and candidate rubric changes.

17Lands is an external observation and calibration source, not the definition of card intelligence. Preserve dataset scope and snapshot. Never infer zero from missing data. Current 17Lands metric caveats and licensing constraints remain in force; use only permitted public datasets.

For public transparency, the website may show the dated prediction/model version alongside later observed data, clearly labeled as separate layers. It should be possible to answer: "What did Oculus predict before the format, what evidence supported it, what did later data show, and what changed in the next model version?"

## Versioning and reproducibility

Every result records:

- Model version and result schema version.
- Scryfall printing ID and Oracle ID where available.
- Set code and card identity metadata.
- Structural suggestion engine version and matched rule IDs.
- Confirmed review record, if one exists.
- Evidence references, reviewer, and review timestamp.
- Source data snapshot IDs and source update dates when observations are attached.

Changes to role definitions, ordinal anchors, heuristics, or evaluation semantics require a model-version change and a documented decision. Schema migrations must be explicit. Historical artifacts remain readable under their original model version.

The shared Swift core is authoritative for classification suggestions and evaluation. The app and batch/CI tools call the same implementation. The website displays published artifacts only; it must not reimplement scoring.

## V1 limitations and next work

The initial Swift engine emits structural role suggestions and carries a reviewer-authored record. It does not yet automatically score cards, infer two-for-ones, determine on-rate status, identify archetype fit, or calibrate against 17Lands. Those require explicit review inputs and tested contracts.

Next implementation steps:

1. Define the review catalog format and set-level batch tool.
2. Add reviewer workflow for accepting/rejecting role suggestions and filling the five dimensions and rate assessment.
3. Review TRK as the pre-release test set, keeping Wizards' official highlights distinct from Oculus judgments.
4. Add a prediction snapshot and immutable publication artifact.
5. Add a comparison/calibration report that joins predictions to later 17Lands observations without modifying predictions.


## Local batch tool

The `CardEvaluationTool` executable runs the same Swift-core structural suggester used by the app. It accepts an array of normalized `CardRecord` JSON objects and an optional array of reviewer-authored `CardEvaluationReview` records:

```sh
swift run CardEvaluationTool --database /path/to/local-oculus.sqlite --set TRK --template > trk-review-template.json
# Edit the template: confirm/reject roles and add evidence-backed assessments.
swift run CardEvaluationTool --database /path/to/local-oculus.sqlite --set TRK --reviews trk-reviewed.json > trk-evaluation.json
```

The JSON input is the core Codable card-record format, not raw Scryfall bulk JSON. For normal use, point the tool at the local Oculus SQLite database and select a set; it reads the already-imported normalized card records directly. The JSON option is intended for fixtures and reproducible tests. Do not build a second Scryfall parser in the CLI. The output is deterministic JSON, sorted by the input card order and with each card's role suggestions sorted by role identifier.

The CLI can read directly from the local database or from a normalized JSON fixture. The `--template` option emits one editable review record per card; after review, pass that file with `--reviews` to validate and combine the human assessments with the structural suggestions. It rejects duplicate printing IDs and reviews whose printing ID, set code, or Oracle ID do not match the supplied card. It never modifies the review file. Review updates are authored as a new versioned input file and should be retained as immutable snapshots.

The CLI is a batch analysis aid, not yet a graphical review interface. Its current rules are intentionally conservative and produce candidate labels only. Reviewers must inspect the complete card, including all faces and costs, before confirming roles or making a rate/dimension assessment.


## Deterministic model and closed-loop evaluation contract

The ordinal review schema above is a human-readable evidence layer, not itself the prediction algorithm. The model implementation must produce reproducible per-card outputs from normalized structural facts and explicitly versioned rules/configuration. Human and LLM inputs are investigation annotations and candidate model hypotheses; they are not runtime scoring dependencies and do not write directly into model outputs.

A prediction run records model, engine, configuration, and output-schema versions; set code; run timestamp; declared source cutoff; exact input snapshot IDs and content hashes; per-card output, contributing features/rules, exclusions, and explanation; and whether the run is pre-release or retrospective. The same model version, configuration, and input snapshots must yield canonical identical output. A rerun is a new artifact, never an overwrite.

Historical runs are retrospective experiments. The evaluator must reject or clearly label any source published after the declared cutoff. Rarity remains visible source metadata and is prohibited as a feature or proxy for card strength, archetype fit, or pick preference.

### Observation and calibration layer

17Lands public bulk archives are acquired independently after publication. They are never retroactively included in the prediction input manifest. Comparison joins only on stable card identity and preserves set/event/user-group/color scope and source snapshot. It reports distinct outcome families (pick behavior, play rate, and game performance) with their own sample counts and limitations. Missing values remain missing; copy-weighted observations are not represented as independent games.

The calibration report identifies residuals, rank disagreement, coverage, and outliers. Outlier review may use humans and LLMs to suggest explanations such as a missing mechanic, incorrect rules interpretation, archetype interaction, format-speed assumption, or data-quality issue. Every accepted change becomes a new model version and is regression-tested across historical sets. Reports show both gains and regressions. Avoid tuning and evaluating solely on the same observations; use held-out sets or time slices where possible.


## Experimental feature-rule implementation (PR 99)

The shared core now contains `PredictiveScoringEngine` version `predictive-rules-0.1.0`. It emits independent ordinal dimensions for baseline power, role value, synergy potential, archetype fit, and context sensitivity. It does not calculate a weighted average or a pick score. Each dimension includes a rationale, feature identifiers, and low confidence while the rule set remains experimental.

The first rules use normalized Scryfall card facts: mana value, top-level and face power/toughness, type lines, Oracle text, keywords, and explicitly supplied reviewed archetype relationships. Rarity is never read by the engine. Unreviewed relationships are ignored. Archetype-fit values are omitted unless a reviewed relationship is explicitly supplied. This is a starting heuristic, not a trained model or validated card grade; its creature-body benchmark is intentionally simple and set-speed, curve, matchup, and deck context are not yet modeled.

Generate local per-card output with:

```sh
swift run CardEvaluationTool --database /path/to/local-oculus.sqlite --set TRK --predictions > trk-predictions.json
```

An optional `--relationships relationships.json` input accepts a flat array of `{ "scryfallID": "...", "relationship": { "archetypeID": "...", "role": "payoff", "reviewStatus": "reviewed", "evidence": "..." } }` records. This keeps archetype knowledge explicit and review-gated. The current CLI output is a reproducible local batch result, not yet an immutable publication artifact: it does not yet carry a declared historical source cutoff, full input manifest, or content hashes. Do not call a run pre-release until those are implemented and verified.

## Dual-source score presentation contract

Predictive and empirical scores are separate evidence streams and must never be averaged together:

- **Oculus predictive:** show the five independent 1–5 dimensions, model version, and archetype-specific fit only when reviewed relationships exist. Context sensitivity describes variability, not strength.
- **17Lands empirical:** show the existing regularized GIH score from `ScoredRecommendation.score`, raw GIH win rate from `observedGamesInHandWinRate`, copy-weighted sample count, and exact event/scope/snapshot. Do not label the regularized score as a raw win rate.
- **Missing source:** show the available source only; do not fill missing values with zero or infer one source from the other.
- **No aggregate:** do not create a combined predictive/17Lands grade or sort by an invented average.

The macOS cockpit mockup demonstrates both sources with clearly labeled illustrative values; it is not live-connected. The Hugo archetype page has a shared partial that reads only published `website/data/card_scores.json` data and renders a source when present. The normalized website artifact shape is:

```json
{
  "schema_version": 1,
  "sets": {
    "HOB": {
      "model_version": "predictive-rules-0.1.0",
      "cards": [{
        "scryfall_id": "Scryfall printing UUID",
        "predictive": {
          "baseline_power": { "value": 3 },
          "role_value": { "value": 4 },
          "synergy_potential": { "value": 3 },
          "context_sensitivity": { "value": 2 },
          "archetype_fits": [{ "archetype_id": "goblins", "value": 4 }]
        },
        "observed": {
          "event_type": "PremierDraft",
          "regularized_gih_score": 0.56,
          "observed_gih_win_rate": 0.57,
          "games_in_hand_count": 243,
          "snapshot_id": "source-snapshot-id"
        }
      }]
    }
  }
}
```

The website is presentation-only. A future publisher must create this artifact from the shared Swift evaluator and validated 17Lands result; Hugo must not implement either scoring algorithm. The macOS production adapter must consume the same core result types and preserve source availability independently.

## Remaining validation gates

1. Review the experimental rules against TRK and improve feature extraction before treating ordinal values as useful predictions.
2. Convert the reviewed-card catalog into explicit per-card relationship inputs; do not infer missing TDM theme relationships.
3. Add cutoff-aware immutable prediction artifacts, source manifests, hashes, and canonical output.
4. Freeze TRK predictions before comparing with permitted 17Lands observations. Label HOB/ECL/TDM as retrospective and enforce their historical cutoffs.
5. Compare pick behavior, play rate, and game performance separately; investigate outliers and preserve held-out evaluation.
6. Add regression suites and report both improvements and regressions for every model version.
7. Wire both independent score streams into live pack recommendations only after draft-state integration and data-readiness contracts exist.
