# Local Reference Data Schema

## Goals

DataEngine stores versioned card identity and Limited performance data.
SQLite is the local query store. Network access is reserved for explicit
dataset updates and is never required to make a pick.

## Card identity

A Scryfall printing has three distinct identifiers:

- Scryfall ID identifies one printing and is the local primary key.
- Oracle ID groups printings of the same Oracle card.
- Arena ID bridges a Scryfall printing to the MTG Arena client identifier.

Do not substitute one identifier for another. Draft observations should
retain the Arena identifier seen by recognition and resolve it to a
Scryfall printing record. Oracle ID is useful for grouping reprints.

The cards table stores one row per Scryfall printing. Indexed columns
support Arena ID, Oracle ID, and normalized name + set lookups. The
Codable payload retains mana cost/value, rules text, colors, color
identity, keywords, faces, image reference, rarity, layout, and printing
metadata. Display names are never replaced by normalized lookup names.

## Dataset snapshots

dataset_snapshots records source, dataset key, source update time,
local import time, record count, and attribution. Imported rows refer to
a snapshot. Refreshes create new snapshots so provenance is explicit.

Scryfall default_cards is preferred because it contains printings and
Arena IDs. The importer streams newline-delimited JSON in bounded memory.
Use jsonl_download_uri from the bulk manifest when available.

## 17Lands performance

Metrics are scoped by set code, event type, user group, optional color
filter, and source snapshot. Stored metrics include game count, pick
count, play rate, GIH win rate, opening-hand win rate, drawn win rate,
improvement when drawn, average last seen (ALSA), and average taken at
(ATA).

Rates are stored as fractions: 0.57 means 57%. Missing values remain
null and are never coerced to zero.

The card-ratings response identifies cards by name, not a Scryfall ID.
An imported metric links to a Scryfall printing only when exactly one
card matches that name within the requested set. Ambiguous and unmatched
records are retained without an identity link.

The interactive 17Lands card-ratings endpoint is community-used but not
formally documented, and 17Lands discourages scraping its API. The existing
JSON adapter remains useful for importing a previously acquired snapshot,
but it is not the planned default acquisition mechanism.

The supported acquisition direction is the official public dataset page:
https://www.17lands.com/public_datasets

17Lands publishes aggregated draft and game datasets as gzip-compressed
CSV archives. Draft data supports pick/seen-derived metrics such as ALSA
and ATA; game data supports in-game performance metrics. Both are needed
to reproduce the full recommendation feature set from public data.

The ingestion branch introduces descriptors and a downloader for the
official S3 archive naming convention, plus explicit local acquisition
timestamps. The remaining pipeline work is catalog discovery, streaming
gzip/CSV parsing, aggregation into card-performance records, and validation
against known 17Lands card-rating results. Do not treat a downloaded raw
archive as recommendation-ready until those steps have completed.

17Lands publishes updates as the meta develops. Its FAQ describes draft
data becoming available around two weeks into a set, game data around three
weeks in, and older datasets being refreshed when new ones are released.
The public listing's per-dataset "Last Updated" date must be captured as
sourceUpdatedAt; the local download/import time must be captured separately
as importedAt. See https://www.17lands.com/faq.

## SQLite tables and indexes

- dataset_snapshots: source/version metadata and attribution.
- dataset_baselines: unweighted overall game counts and win rate, keyed by
  dataset scope and exact game snapshot.
- cards: one row per Scryfall printing, with indexes for Arena ID,
  Oracle ID, and normalized name + set.
- card_performance: set/format/user-group/color-scoped observations,
  indexed for card lookup.

## Attribution

Card data © Scryfall: https://scryfall.com

17Lands data: https://www.17lands.com

17Lands public datasets are generally published under CC BY 4.0 unless
otherwise noted. Preserve attribution when displaying or exporting data.


## Public CSV acquisition and parsing

The catalog client reads the official 17Lands public dataset listing and
retains the exact draft/game archive URLs and each row's Last Updated date.
This avoids treating the URL naming convention as proof that a dataset
exists for a particular set and event type.

The gzip CSV reader uses zlib incrementally and emits one CSV row at a time.
It supports quoted fields, escaped quotes, commas, CRLF, and embedded
newlines. The first row becomes a dynamic header; card-facet columns must be
looked up by name because the column set changes between expansions.

The reader validates UTF-8, duplicate header names, malformed quoting, and
row-width mismatches. It does not yet interpret 17Lands metrics or write
performance records. Raw CSV parsing is a transport/format layer only.


## Game-level metric aggregation

The game CSV aggregator discovers the set-specific card columns by the
`opening_hand_`, `drawn_`, `tutored_`, `deck_`, and `sideboard_`
prefixes. It processes one game row at a time and retains only per-card
counters, so memory use does not grow with the number of games.

Copy-weighted statistics follow the 17Lands metric definitions:

- Games played and GP win rate weight each maindeck copy.
- Play rate is maindeck copies divided by maindeck plus sideboard copies.
- Opening-hand, drawn, and games-in-hand rates weight each corresponding
  card copy.
- Games not seen are maindeck copies minus opening-hand, drawn, and tutored
  copies, clamped at zero.
- Improvement in hand is games-in-hand win rate minus games-not-seen win rate.

Rates are fractions, not percentages. A missing denominator produces nil,
not zero. The existing `winRate` field represents games-in-hand win rate
for CSV-derived records. Additional count and GP/GNS fields are preserved
in the Codable payload.

This first aggregation step supports the public all-user game dataset.
Non-`all` user groups are rejected rather than silently mislabeled. Draft
metrics (ALSA/ATA) are not populated by this importer; they require the
draft archive and a separate aggregation pass. The game and draft passes
for one catalog entry share a snapshot ID and dataset key so their metrics
can be combined without losing the common upstream update date or local
acquisition time. A game-only snapshot is not recommendation-ready.


## Draft-level metric aggregation

The draft CSV contains one row per pick. Its set-specific
`pack_card_<card name>` columns describe the cards still present in the
current pack; `pick` identifies the primary selected card and `pick_2`
is included when the archive records a secondary selection. The importer
also requires `draft_id`, `pack_number`, and `pick_number`.

The importer streams the archive and retains sightings for only the
current draft round. It tracks the eight circulating pack lanes separately:
pick 9 revisits the pack seen at pick 1, pick 10 revisits pick 2, and so on.
At a round boundary, each card's last observed pick number within its own
pack is folded into its ALSA total. This matters when a card wheels: the last
observation on the second pass, not the first pass, determines ALSA.
A selected card is counted as seen even when the P1P1 pack contents are
missing from the Arena log.

ATA averages the pick number at which a card was selected. Both `pick`
and a non-empty `pick_2` contribute to picked count and ATA. `seenCount`
and `pickCount` are retained as sample sizes; averages remain nil when
their denominator is zero. These are card-instance counts, not unique
draft counts.

The official public draft archive is ordered by draft and pack round; the
streaming accumulator finalizes the eight pack lanes when that key changes. Draft
statistics use the all-user archive and are not filtered by deck colors.
The draft and game importers use the same snapshot ID and dataset key.
Performance upserts merge non-nil facets for that snapshot/card identity,
so importing one archive does not erase metrics already imported from the
other. A single archive still does not make the dataset recommendation-ready.


## Recommendation baseline contract

The first shared evaluator uses Games in Hand Win Rate (GIH WR) as its
standalone strength signal. GIH count is the number of card copies seen in
opening hands or drawn later, not a count of independent games. A game can
contribute multiple copies, and repeated draws can contribute more than one
observation. Do not interpret this count as an independent Bernoulli sample
or use it to claim a confidence interval.

The evaluator regularizes observed GIH WR toward an explicitly supplied
overall format baseline:

`score = (GIH_WR * GIH_count + baseline_WR * prior_weight) / (GIH_count + prior_weight)`

The baseline must come from the same set, event type, and user group. Its
dataset key is included in the scoring configuration and the evaluator
rejects a baseline whose key does not match the requested dataset. The prior
weight is a versioned tuning parameter, not a claim about the number of
independent observations. Both values are explicit configuration; the
evaluator does not invent a default baseline.

ALSA and ATA are carried through as draft-context signals for display and
future scoring work. This baseline version does not use them to change the
ranking. Synergy, archetype, curve, and deck-needs adjustments are deferred
until those inputs have explicit, tested contracts.

Current importer tests use small compressed fixtures. They validate parser
and aggregation behavior but do not replace a production validation pass
against current official archives, including actual headers and independently
recomputed metric totals. That archive-level comparison remains a release
gate before recommendations are treated as production-ready.


## Overall game baseline

The game archive contains one row per game. The importer counts those rows
and their winning outcomes separately from the per-card copy-weighted
statistics. The overall win rate is the number of winning game rows divided
by all included game rows. For color-filtered datasets, only rows matching
the requested main-color cohort contribute. The result is persisted in
`dataset_baselines` with the exact dataset key and game snapshot ID.

The local recommendation adapter requires this persisted baseline and
rejects a scoring configuration whose dataset key, snapshot ID, or baseline
rate differs. This prevents a manually supplied or stale baseline from
being used with otherwise compatible card metrics. The baseline is an
unweighted game-level rate; it is not derived from summing card-copy counts.


## Reproducible archive validation

The repository includes an independent reference implementation in
`scripts/validate-17lands-archives.py` and a small Swift executable that
runs the production CSV reader and game/draft accumulators over the same
archives. The validator downloads the exact draft and game URLs from the
official public dataset catalog, records the catalog update date, and
compares per-card counts and rates between the two implementations.

Run it locally from the repository root:

```sh
python3 scripts/validate-17lands-archives.py --set-code HOB --event-type PremierDraft
```

The GitHub Actions workflow is manually triggerable for supported draft
formats and runs weekly. It uploads the source-independent metrics output
and a Markdown discrepancy report. Archive downloads are deliberately not
part of ordinary pull-request CI, so an upstream outage cannot block
unrelated code changes.

A clean comparison proves that the two implementations agree on the
documented aggregation rules and actual archive shape. It does not, by
itself, prove that every interpretation matches 17Lands' displayed
card-ratings calculations. Any differences from official metric
definitions or published figures must be investigated before the
recommendation pipeline is considered production-ready.
