# Set discovery and acquisition

## Which workflow should I run?

**For normal use, run “Acquire Set Data (Recommended)”.** It selects available 17Lands sources automatically, downloads Scryfall metadata, and captures supplemental snapshots. You do not need to run discovery first.

“Optional - Discover Limited Sets (Read-only)” is an inventory report for checking which sets and archives are published. It does not acquire data and is not a prerequisite.


Two workflows keep set inventory current while separating acquisition from reviewed-data promotion.

## Optional - Discover Limited Sets (Read-only)

Run Actions → Optional - Discover Limited Sets (Read-only) → Run workflow, or let the weekly schedule run. The read-only workflow compares Scryfall set releases, the public 17Lands archive inventory, and Oculus's local reviewed archetype/card catalogs. It uploads JSON and Markdown reports for 30 days.

17Lands' FAQ describes intended publication windows of roughly two weeks for draft data, three weeks for game data, and five weeks for replay data. These are expectations, not guarantees. The report distinguishes available, awaiting_expected_publication, and not_listed. A recent set without data is not automatically an error.

## Acquire Set Data (Recommended)

Run Actions → Acquire Set Data (Recommended) → Run workflow. Supply a Scryfall set code, event type, and optionally an official Wizards guide URL.

The workflow retrieves English Scryfall card records and image URIs, probes the deterministic public S3 object keys for draft, game, and replay archives, and optionally preserves Wizards guide evidence. It does not scrape the 17Lands HTML listing. When both draft and game archives are accessible, they are preferred and the Card Analytics API is skipped. If either is unavailable, GitHub requests one ALL_TIME Card Analytics snapshot as a fallback. A 403 response from S3 is ambiguous (the key may be missing or bucket listing may be restricted), so it is recorded as such and treated as unavailable for this acquisition. Trophy Decks are supplemental and requested once per run because they are not included in the public CSV archives. The Trophy Decks endpoint and payload are community-observed, not an official 17Lands API contract. API failures are recorded without discarding successfully acquired sources. The workflow runs weekly for TRK by default and can be manually dispatched for another set/event.

Acquisition creates a candidate artifact. It does not infer archetypes, assign card roles, promote reviewed catalogs, calculate recommendation metrics, or claim 17Lands eligibility parity. Human review and promotion remain separate.

## TRK example

TRK is the Scryfall code for Magic: The Gathering | Star Trek. Official guide:
https://magic.wizards.com/en/news/feature/star-trek-prerelease-guide

Use that URL in the optional guide field. Re-run acquisition after 17Lands publishes new archives; no canonical data is overwritten.

## Sources

- https://scryfall.com/docs/api
- https://www.17lands.com/public_datasets
- https://www.17lands.com/faq


## 17Lands request policy

- The native app never calls the 17Lands web API.
- GitHub Actions is the only component that requests web API data.
- Bulk S3 archives are preferred independently for draft and game data.
- Card analytics uses /api/card_data with time_period=ALL_TIME only when one or both bulk archives are absent.
- Trophy decks use one supplemental request per acquisition run; they are not present in the public CSV archive set.
- The scheduled acquisition runs weekly, not continuously. Raw responses are timestamped and checksummed for downstream proxying.
- 17Lands states that its API is unsupported for third-party use and discourages scraping. This deliberately low-frequency, cached snapshot approach limits requests, but does not imply endorsement or a stability guarantee.

The API response is preserved as raw JSON because its schema and availability may change. Trophy decks are a selected sample of successful runs, not population-wide performance data. The workflow publishes the API JSON snapshots under website/static/data/17lands/{SET}/{EVENT}/, making them available through the Cloudflare Pages website feed. The native app should consume that repository-published snapshot and display its retrieval time and source; it should not make direct API requests. Raw S3 archives remain available for direct native-app acquisition.
