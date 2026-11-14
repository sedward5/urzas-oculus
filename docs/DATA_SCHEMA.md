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
draft archive and a separate aggregation pass. Therefore a game snapshot
alone is not recommendation-ready.
