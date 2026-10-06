---
status: accepted
date: 2026-10-06
amends: 0053
---

# The generation moves on every Station change, and the resume takes it again

This amends ADR 0053 without editing it; it adds "amended by 0058" to its status line. The
Definer settled it on 6 October for ENG-1446, the slice that puts the Station in the machine.

## Context

ADR 0053's amendment of 6 October says the generation moves on every Station change. Until
then, the generation moved only when a gesture cleared the room. Three Station changes clear
nothing. The resume lands on the Rehearsal or the Back-translation in the middle of opening the
passage, and the Closing arrives on its own timer. The opening captured its generation before
the landing, then reads the session after it.

## Decision

- **A Station change moves the generation inside `reduce`, wherever it happens.** An arrival
  at the Station already held moves nothing.
- **The resume takes its generation again right after each landing**, so the session read
  that follows the landing still completes.
- **The busy watchdog is not re-armed at the landing.** Every landing marks the room idle,
  and the watchdog acts only on a room that waits. Every wait that marks the room busy
  arms its own watchdog, on the generation of that moment.
- **No silence is added at the landing or at the Closing.** Nothing sounds at either point.
  The Closing needs nothing more: its next timer is armed after the change.
- **A gesture takes its generation after its Station event**, so the change it makes does not
  abandon it.

## Considered Options

**The landing and the Closing keep the generation.** Rejected: the generation would mean
"the last gesture that cleared the room" rather than "the Station's work". The Stations that
follow (ENG-1281, ENG-1282) would each need their own exceptions.

**The resume does not take its generation again.** Rejected: the move at the landing would
abandon the resume before its session read.

**The resume also re-arms the busy watchdog at the landing.** Rejected: no wait can observe
it, for the reason above. Removing it changes no outcome.

## Consequences

- Any wait that was armed on the old generation and is still pending at the landing or at the
  Closing is abandoned there, like one abandoned by a gesture.
- A person call can fail during the 700 ms before the Closing arrives, under a halt the Watch
  raised. The retry it armed is then abandoned at the Closing, and nobody is asked again
  before the room starts over.
