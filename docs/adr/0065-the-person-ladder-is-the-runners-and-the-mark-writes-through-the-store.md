---
status: accepted
date: 2026-10-07
amends: 0060
---

# The person ladder is the runner's, and the closed-passage mark writes through the Store port

This amends ADR 0060 without editing its decision; it adds "amended by 0065" to its status
line. The Definer split ENG-1456 and the Orchestrator settled the mechanism on 7 October
while the ladder, its stop and the closed-passage mark left the notifier (ENG-1476).

## Context

ADR 0060 left the ladder, the stop and the mark on the host, and said that runner timers
survive a generation move by design. The ladder was the notifier's `'person'` timer: made
apart, cancelled by every `_cancelTimers`, and dropped at fire if the generation had moved.
The mark wrote the finished passage to the disk from the notifier.

## Decision

- **The ladder's timer is the runner's.** It is armed by `AskForAPersonAgain` when the
  Station says a person is needed, stamped with the generation when it is armed, and drops
  its fire if the generation moved: the one runner timer that does not survive a generation
  move. The Watch and the retry still do. At fire, the runner calls its own
  `callForAPerson`, which asks `callIsWanted` as before.
- **The delay is the runner's `retryDelay(step)`**, the seam `ArmTheRetry` already uses,
  clamped at the last step. The runner keeps the step and climbs it on every ask again.
- **The stop cancels the timer and resets the step, then the Station hears it:** its flag,
  the network health settled and the resume counter, in that order. A forgotten passage
  does the same through a public runner method. Cancelling there is equivalent to before,
  because every caller of the forget already moves the generation through `_clearAll`.
- **The closed-passage mark writes through the Store port.** The Station hears the mark
  begin, holds the call, tells the Choice the passage is closed, and hands back the book and
  the passage to write; the Store port writes them and swallows its failure at the boundary.
  The Station then hears the mark end with the session and does what it did: the room's
  session hears `ThePassageClosed`, another session is let go. A mark with no session asks
  nothing.
- **The ladder's fire runs in the zone of the dispatch that armed it, not apart.** The
  notifier's timer ran with no gesture on the chain. Measured: no test sees the difference,
  because the retry, the answers of that call and the stop's settle say no line and arm no
  wait.

## Considered Options

**An event through `host.answer`, stamped at arm time**, for the ladder's fire. Kept as the
fallback if the zone ever shows; it would move the retry into the machine.

**A host question for the delay.** Rejected: it would duplicate the notifier's ladder read
and grow the host ENG-1477 shrinks.

**The adapter reading the book.** Rejected: `bookProvider` lives in the notifier file, so
the Station hands the book back, as it hands back the read stamp.

## Consequences

- `EffectHost` keeps no method that stops the call, asks again or marks the passage closed.
  It answers `aPersonIsNeeded` and hears through `hearTheCallStopped`, `hearTheMarkBegin` and
  `hearTheMarkEnd`.
- ADR 0060's sentence that the ladder, the stop and the mark stay on the host until ENG-1456
  is no longer true, and so is its remark that runner timers survive a generation move: the
  ladder's does not.
- An earlier session's closed passage (ADR 0060) still writes from the Station.
