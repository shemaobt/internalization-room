---
status: accepted
date: 2026-10-09
amends: 0050
---

# A failed check is asked again only by the team's tap

This amends ADR 0050 for the Verdict alone. It adds "amended by 0073" to 0050's status
line. Nothing else in 0050 is edited.

## Context

ADR 0050 made every Pending request go again once per return, the Verdict included, on the
room's ladder. The tablet reads a 5xx as a network failure, so a finish the server could
not answer (the analyst cut at its token limit, any 502) made the room fall, the health
check pass, and the finish go again: one paid analyst call every 5 to 32 seconds, for as
long as the team stood there (hand tests of 08-10 and 09-10, ENG-1517 item 4.11). Henok
decided on 09-10 that a failed check is asked again only by the team's tap.

## Decision

**The Verdict falls at a door of its own.** A finish answered with a 5xx or a network
failure takes the room out of reach, says the offline notice once per outage, and rests on
«Tocar para tentar de novo». While it rests, the machine arms no retry: neither a timer
nor the radio coming back asks for a probe, and a probe that fails climbs no ladder.

**Only the team's tap asks again.** The tap probes the room; a return sends the finish
once, as the Pending request. A second failure returns to the same rest. The advance
button, pressed while the check rests, takes the same route.

**Leaving the Retro gives the ladder back.** The rest belongs to the Retro: if the team
goes to another Station while the room is still out of reach, the machine arms the room's
own ladder again.

Every other door keeps ADR 0050: a stretch, the approval, a turn or the way in still goes
again once when the room comes back on its own. A halt the Desk lifts while the room is out
of reach, and the long press that releases the room, still send what is pending.

## Considered Options

**Send the finish only on a network failure and treat a 5xx as a refusal.** Rejected: the
tablet cannot tell an overloaded server from a lost connection by the status alone, and
every other door reads a 5xx as the network; one door reading it otherwise would split the
failure policy.

**Keep the ladder but cap the resends.** Rejected: each resend is a paid call the team
never asked for, and the ticket's rule is that none is sent unasked.

## Consequences

A Verdict lost to a real network outage now waits for the tap even after the radio comes
back, which costs the team one gesture ADR 0050 had saved them. The circle already asks
for it.

While the Verdict rests, a part pending in the Outbox waits for the same tap, or for the
team to leave the Retro: the room asks the server nothing on its own.

A probe already in the air when the Verdict falls, because another door had taken the room
out of reach first, can still answer and send the finish once with no tap. It stops at that
one send; it is accepted as a race.
