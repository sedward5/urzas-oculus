# Set discovery and acquisition

Two workflows keep set inventory current while separating acquisition from reviewed-data promotion.

## Discover Limited Sets

Run Actions → Discover Limited Sets → Run workflow, or let the weekly schedule run. The read-only workflow compares Scryfall set releases, the official 17Lands public archive listing, and Oculus's local reviewed archetype/card catalogs. It uploads JSON and Markdown reports for 30 days.

17Lands' FAQ describes intended publication windows of roughly two weeks for draft data, three weeks for game data, and five weeks for replay data. These are expectations, not guarantees. The report distinguishes available, awaiting_expected_publication, and not_listed. A recent set without data is not automatically an error.

## Acquire Set Data Bundle

Run Actions → Acquire Set Data Bundle → Run workflow. Supply a Scryfall set code, event type, and optionally an official Wizards guide URL.

The workflow retrieves English Scryfall card records and image URIs, downloads only 17Lands archives actually linked for that set/event, and optionally preserves Wizards guide HTML, headings, paragraphs, and explicitly labeled archetype/draft images with checksums. If 17Lands has not published the selected event, it records not_yet_published and continues.

Acquisition creates a candidate artifact. It does not infer archetypes, assign card roles, promote reviewed catalogs, calculate recommendation metrics, or claim 17Lands eligibility parity. Human review and promotion remain separate.

## TRK example

TRK is the Scryfall code for Magic: The Gathering | Star Trek. Official guide:
https://magic.wizards.com/en/news/feature/star-trek-prerelease-guide

Use that URL in the optional guide field. Re-run acquisition after 17Lands publishes new archives; no canonical data is overwritten.

## Sources

- https://scryfall.com/docs/api
- https://www.17lands.com/public_datasets
- https://www.17lands.com/faq
