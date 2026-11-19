# 17Lands metric semantics audit

This document is the implementation contract for Oculus's 17Lands-derived metrics.
It distinguishes published definitions from implementation assumptions that still
need independent verification.

Primary source: https://www.17lands.com/metrics_definitions
Dataset source: https://www.17lands.com/public_datasets

## Scope and grain

- Game statistics are calculated per game, not per match. A Traditional Draft
  player can change the maindeck between games.
- Game statistics are copy-weighted where the definition counts card instances.
- Draft statistics are derived from one row per pick. Each player's draft is
  treated independently; pack observations are not reconstructed from other
  players in the pod.
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
| `improvementInHand` | IIH | GIH WR minus GNS WR; a simple difference, not a sample-size-weighted comparison. |

### Eligibility rule: unresolved source-data boundary

17Lands states that a game is excluded from **all** in-game statistics when its
game data is inconsistent (for example, a card in hand that is absent from the
deck/sideboard, or no deck linked to the game).

The public wide CSV exposes per-card `opening_hand_`, `drawn_`, `tutored_`,
`deck_`, and `sideboard_` facets plus game metadata. It does not expose a
documented, explicit `game_valid` or `deck_linked` flag.

Oculus currently accepts every row with a valid `won` value and aggregates it.
It does **not** yet implement a whole-game consistency exclusion. Do not silently
infer a complete eligibility rule from one card's counts: later draws can exceed
maindeck copies when a card is shuffled back and drawn again, and tutors are a
separate observation. Before changing production eligibility, establish exactly
which source facets and identity fields 17Lands uses to detect an unlinked or
inconsistent game.

Observed HOB PremierDraft archive (2026-11-19 validation artifact):
- 323,114 game rows.
- No row had zero total maindeck copies.
- No row had zero total maindeck plus sideboard copies.
- No card had opening-hand copies greater than that card's maindeck plus
  sideboard copies.
- 6,753 rows had at least one card where opening-hand + drawn + tutored
  instances exceeded maindeck plus sideboard copies. This is **not** by itself
  evidence of invalid data because repeated draws are explicitly possible.

These observations are diagnostics, not proof that the archive has no invalid
games. The eligibility rule remains an open audit item.

## Draft metrics

| Oculus field | Published metric | Contract |
| --- | --- | --- |
| `seenCount` | Number Seen | Count card instances in packs, once per physical pack; if duplicate copies exist in one pack, count each copy. A picked card is known to have been seen even when P1P1 pack contents are missing. |
| `averageLastSeen` | ALSA | Average pick number at which each observed card instance was last seen in its pack. A wheel appearance replaces the earlier pick for that pack. |
| `pickCount` | Number Picked | Count card instances selected by 17Lands drafters. |
| `averageTakenAt` | ATA | Average human-facing, one-based pick number for selected card instances. |

### Draft implementation assumptions requiring independent verification

- The public archive uses zero-based `pack_number` and `pick_number`; Oculus
  converts pick positions to one-based values for ALSA and ATA.
- Oculus groups rows by `(draft_id, pack_number)` and uses eight circulation
  lanes (`raw_pick_number % 8`) so pick 9 revisits the pack observed at pick 1.
- The maximum observed copy count for a card in a lane is retained, preventing
  a wheel observation from being counted as a second pack appearance.
- `pick` and nonempty `pick_2` are each counted as selected card instances.
  The latter is relevant to Pick-Two draft formats.

The official definitions establish the metric outcomes but do not, by themselves,
prove these archive-ordering and lane-reconstruction assumptions. Validate them
against manually reconstructed real drafts and independent fixtures before
treating them as fully verified.

## Validation principles

1. Swift/Python parity is an implementation regression check, not independent
   proof of semantic correctness when both implementations encode the same rule.
2. Every semantic test should have a hand-calculated expected result derived from
   the published definition.
3. Keep production behavior unchanged until an observed discrepancy and its
   source-data interpretation are established.
4. Preserve the archive, source update timestamp, and validation report used
   for any future semantic comparison.
