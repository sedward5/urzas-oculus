# 17Lands metric semantics audit

This document records the metric contract and distinguishes published definitions from implementation assumptions.

Primary source: https://www.17lands.com/metrics_definitions
Dataset source: https://www.17lands.com/public_datasets

## Scope and grain

- Game statistics are per game, not per match.
- Game statistics are copy-weighted where the definition counts card instances.
- Draft statistics are derived from one row per pick; pack observations are reconstructed within each player's draft.
- Missing P1P1 pack contents do not imply that the selected card was absent.

## Game metrics

| Oculus field | Published metric | Contract |
| --- | --- | --- |
| `gamesPlayedCount` / `gameCount` | #GP | Sum maindeck copies across eligible games. |
| `gamesPlayedWinRate` | GP WR | Wins weighted by maindeck copies, divided by #GP. |
| `playRate` | %GP | Maindeck copies divided by maindeck plus sideboard copies, across game rows. |
| `openingHandCount` | #OH | Opening-hand instances, copy-weighted. |
| `openingHandWinRate` | OH WR | Wins weighted by opening-hand instances. |
| `drawnCount` | #GD | Later draw instances only; excludes opening hand, tutoring, bounce-to-hand, and exile casts. A physical copy may count more than once if shuffled back and drawn again. |
| `drawnWinRate` | GD WR | Wins weighted by later-drawn instances. |
| `gamesInHandCount` | #GIH | Opening-hand plus later-drawn instances. |
| `gamesInHandWinRate` | GIH WR | Wins weighted by GIH instances. |
| `gamesNotSeenCount` | #GNS | max(0, maindeck copies - opening-hand copies - later-drawn copies - tutored copies). |
| `gamesNotSeenWinRate` | GNS WR | Wins weighted by unseen maindeck copies. |
| `improvementInHand` | IIH | GIH WR minus GNS WR. |

### Eligibility rule: unresolved source-data boundary

17Lands states that a game is excluded from **all** in-game statistics when its game data is inconsistent (for example, a card in hand absent from the deck/sideboard, or no deck linked to the game).

The public wide CSV exposes per-card opening-hand, drawn, tutored, deck, and sideboard facets plus game metadata. It does not expose a documented, explicit game-valid or deck-linked flag.

Oculus currently accepts every row with a valid `won` value and aggregates it. It does **not** implement a whole-game consistency exclusion. Do not infer a complete eligibility rule from one card's counts: later draws can exceed maindeck copies when a card is shuffled back and drawn again, and tutors are separate observations.

Observed HOB PremierDraft archive ([workflow run 44536292267](https://github.com/sedward5/urzas-oculus/actions/runs/44536292267)):
- 323,114 game rows.
- No row had zero total maindeck copies.
- No row had zero total maindeck plus sideboard copies.
- No card had opening-hand copies greater than that card's maindeck plus sideboard copies.
- 6,753 rows had at least one card where opening-hand + drawn + tutored instances exceeded maindeck plus sideboard copies. This is not by itself evidence of invalid data because repeated draws are possible.

These are diagnostics, not proof that the archive has no invalid games. The eligibility rule remains open. Until resolved, Oculus should not claim exact parity with 17Lands for game metrics.

## Draft metrics

| Oculus field | Published metric | Contract |
| --- | --- | --- |
| `seenCount` | Number Seen | Count card instances in packs once per physical pack; duplicate copies count separately. A picked card is known to have been seen even when P1P1 pack contents are missing. |
| `averageLastSeen` | ALSA | Average pick number at which each observed card instance was last seen in its pack. A wheel appearance replaces the earlier pick for that pack. |
| `pickCount` | Number Picked | Count card instances selected by 17Lands drafters. |
| `averageTakenAt` | ATA | Average one-based pick number for selected card instances. |

### Draft implementation assumptions

- The archive uses zero-based pack and pick numbers; Oculus converts pick positions to one-based values for ALSA and ATA.
- Oculus groups rows by (draft_id, pack_number) and uses eight circulation lanes (raw_pick_number % 8), so pick 9 revisits the pack observed at pick 1.
- The maximum observed copy count for a card in a lane is retained, avoiding double-counting a wheel appearance.
- Both pick and nonempty pick_2 are counted as selected card instances.

Official definitions establish metric outcomes but do not alone prove archive-ordering and lane-reconstruction assumptions.

### Manual review: HOB PremierDraft archive

The validation artifact contained 2,436,691 draft rows and 323,114 game rows. The draft CSV was streamed from gzip.

**Physical pack return.** Draft 5d9123f82d8d4573b03345fb369dc5d6, pack 0, was inspected at raw picks 0 and 8 (human picks 1 and 9). The first observation contained 14 card instances; the later observation contained six. All six later-observed cards were present in the first observation. Eight cards were no longer present. This supports the same-physical-pack/eight-pick lane model, but one example does not prove it universally.

**Last-seen and wheel behavior.** In that pack, Confusticate and Bebother was present at picks 1 and 9, so last seen was 9. Rhovanion Rampager was present at pick 1 and absent at pick 9, so last seen was 1. Long-Bodied Grey Dog was present at both observations and selected at pick 9, so last seen was 9.

**Averaging and duplicate copies.** ALSA uses one last-seen position per observed card instance per physical pack, then takes the arithmetic average across instances. A wheel updates the last-seen position; it does not add another observation. Duplicate copies count separately. When copy counts differ across observations of one lane, the maximum is retained rather than summing across the wheel.

**Secondary picks.** Draft 06e744ef58734bda81fd7236eeb428ad, pack 0, human pick 6, had Gollum, Silent Slinker as primary pick and Warg Tactics as pick_2. Both were in pack contents. Oculus counts both as selected instances at the same one-based pick position for Number Picked and ATA.

**Missing or incomplete contents.** The HOB scan found no P1P1 row with a known primary pick and zero reported pack-card counts, and no P1P1 row with fewer than 14 reported cards. It also found no nonempty selected card absent from its reported pack-card columns. Thus the archive supplied no real-world example for either recovery case.

The implementation explicitly marks known primary and secondary picks as seen, even if pack-card columns omit them. A controlled regression fixture should cover a P1P1 row with no reported contents and a known pick. For genuinely incomplete observations, count reported card instances plus known selected cards; do not infer unreported cards. This defensive behavior is supported by code inspection and fixture, not an independent archive example.

## Validation principles

1. Swift/Python parity is a regression check, not independent semantic proof when both implementations encode the same rule.
2. Semantic tests should have hand-calculated expected results from published definitions.
3. Keep production behavior unchanged until a discrepancy and source-data interpretation are established.
4. Preserve the archive, source update timestamp, and validation report for future comparisons.
