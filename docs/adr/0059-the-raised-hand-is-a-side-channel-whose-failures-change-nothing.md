---
status: accepted
date: 2026-10-06
amends: 0050
---

# The raised hand is a side channel whose failures change nothing

This amends ADR 0050 without editing it; it adds "amended by 0059" to its status line.
Jonatas and the Definer settled it on 6 October for ENG-1328, to match Marcia's app.

## Context

ADR 0050 says a network failure at any door, the inbox's included, takes the room out of
reach. The hand reached the room through three doors: the Knot it sends, the check for
waiting replies with the heard mark, and the reply clip. A Knot that met a network failure
took the room out of reach and said the offline notice. One sent after a reset ran the
session-gone path, and a refused one counted toward a Call for a person. A side channel
that only the facilitator listens to could stop the team's conversation with the voice and
make the voice speak a line.

## Decision

**A failure at one of the hand's doors (the Knot, the inbox, the reply) changes nothing in
the room.** The Failure policy decides every non-answer there as one event: a network
failure, a time-out, a refusal of any code, or the session gone. The machine answers that
event with no transition and no effect. The reach, the Station, the halt, the session and
the refusal count stay as they were, and no line is spoken.

No time-out reaches the hand's doors today. The only time-out the room produces is the
busy watchdog's, and it is decided at the step door, not at the hand's. A Knot whose upload
hangs ends at its own 90-second limit as a network failure, well before the watchdog's
330-second ceiling. If either limit changes so that a Knot can still be in flight when the
watchdog fires, the watchdog decides it at the step door and raises the halt.

**What the hand loses stays on the hand.** A failed Knot is never sent: its recording stays
on the tablet, nothing sends it again, and the circle goes back to waiting. A reply that does
not load, or whose heard mark does not save, keeps the dot, and the next tap tries again.

Every other door keeps ADR 0050's rule.

## Considered Options

**The notifier drops the hand's failures before the policy sees them.** Rejected: ADR 0053
makes the policy the one place a room result becomes an event. The reach guard exists to
stop exactly that kind of drop.

**The hand's failures reuse the event for a refusal that passes.** Rejected: a network
failure or a gone session is not a refusal. One event named for the hand says what happened
and keeps the hand's doors in one place in the policy.

**A Knot the disk cannot read goes through the policy too.** Rejected: it is not a room
result, and nothing reached the room. The Knot is not sent and the circle goes back to
waiting.

## Consequences

A Knot that never left is not sent again and gets no sign. A visual sign would be the
production team's call, and it would never be spoken.

A room whose only failing door is the hand never learns that it is out of reach. The next
real door that falls takes the room out of reach.
