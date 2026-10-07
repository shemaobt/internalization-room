---
status: accepted
date: 2026-10-07
amends: 0053
---

# The small effects leave the host, and the lifecycle hand-offs share one callback

This amends ADR 0053 without editing its decision; it adds "amended by 0066" to its status
line. The Definer settled the shape on 7 October, while the remaining small effects left
the `EffectHost` (ENG-1456).

## Context

After ENG-1453, ENG-1454 and ENG-1476 the host still held one method per effect for twelve
effects: the silence, the replay, the opening let go, the Outbox drain, the Pending
resend, the discard, the Choice, the reply the look found, the turn let go, the fall, the
refusal count and the passage that cannot open. The machine's effect lists, and the
`Machine` values tests compare, are pinned by assertions, so no effect could leave the
machine's output and no field could move into `Machine`.

## Decision

- **Every effect stays in the machine's output; only who executes it changes.**
- **Port work is the runner's.** `DrainTheOutbox` is the Store port's flush. The Station
  then hears the names to adopt when it lands, and the count of what is unsent whether it
  landed or failed. The chain stays unawaited, so a failed flush surfaces as before.
- **A machine event the notifier dispatched from inside an effect is the runner's
  answer.** `SilenceTheRoom` is handed over, then the runner answers
  `GestureSilenced(keepingTheHold: false)`. `LetTheTurnGo` asks the Station which gestures
  await the turn, answers `GestureEnded` for each, then the Station hears the turn let go
  and watches for a stuck wait. Both answer where asked; the turn's gestures are not ended
  after the runner is disposed, as before.
- **State the Station owns is heard.** The replay (its decision stays the Station's, ADR
  0055), the opening let go, the reply the look found, the fall, the refusal count and the
  passage that cannot open each reach a `hear*` member with the body they had.
- **The four lifecycle hand-offs are one sealed effect type.** `OpenTheChoice`,
  `DiscardTheSession`, `SilenceTheRoom` and `ResendPending` extend `LifecycleHandOff`, a
  sealed subtype of `Effect`, and reach the Station through one host member, `handOver`.
  Their values and equality are unchanged.
- **The silence's writes run before the machine hears it.** The choice is cleared, the
  thinking left and the waits for the Guide and the peer cue cleared before
  `GestureSilenced` is dispatched, not after. Measured: that dispatch reduces only the
  Channel, its one effect is `StopTheSound`, and neither `_followTheSound` nor
  `_followTheMicrophone` nor any listener reads those fields synchronously, so the order is
  kept with no tail hearing. Gestures that silence the room still dispatch the event
  themselves.
- **The guard list:** this slice adds no entry and moves no door; its eleven entries keep
  ENG-1444's tag until the per-Station tickets exist.

## Considered Options

**The six hearings as machine facts** (the reach's face, the refusal count, the opening's
bookkeeping). Rejected here: each changes the effect lists or the `Machine` values tests
assert. Each is its own slice if wanted.

**A separate sealed type in the runner, built from the effect.** Rejected: it duplicates
the four names for no gain.

## Consequences

- `EffectHost` keeps no effect method. It holds questions, hearings, `answer` and
  `answerWhereAsked`, and `handOver`; ENG-1477 reduces it.
- The drain's callbacks run in the zone of the dispatch that ran the effect, not apart. They
  dispatch nothing synchronously, and the count makes itself apart.
