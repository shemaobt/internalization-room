# The room's reach is a fact of its own

## Context

A room that cannot get to the server falls: it says so on the circle, speaks the offline
notice once, watches the network and climbs a retry ladder until it comes back, and then
flushes the **Outbox**. All of that hung on one field. `offline` was `voice ==
VoiceState.offline`, so the sentence the circle was saying *was* the fact the way back
depended on, and every one of the thirty-one places that write the voice could end it
without knowing.

Three of them did, and each was found only after it shipped. The recorder's denied and
never-started arms (ENG-982's sibling, ENG-1057). Opening the **Rehearsal**, which the
record entry made reachable at any moment (ADR 0037). And the halt raised by a second
failed capture, which also raises a halt the room cannot tell anyone about. In each the
team is shown an ordinary invite over a room with nothing reaching the server, the ladder
gone, the outbox full — until some later call fails and the fall is declared again.

The `reach` field was already there, beside the voice, already written on the fall. It was
only never read as the fact.

## Considered Options

**A guard on each door**, as ENG-1057 put one on the recorder's arms. Rejected after the
third: the guard is the symptom. Two more would leave the fourth door for whoever opens
it, and the failure is silent — a green circle over a room that is not talking to anyone.

**Making the voice a stack**, so a state written over another could be put back. Rejected:
it answers the wrong question. What has to survive is not the sentence, it is the
knowledge; the circle only ever shows one thing at a time and should.

## Decision

**Whether the room can reach the server is a fact the room keeps on its own, and the way
back reads that fact.** The retry ladder, the network watch, the come-back and the fall's
own re-entry all gate on the reach. The voice stays free: the circle draws the fall from
it exactly as before, and a halt or an invite written while the reach is down changes what
the team sees and nothing else.

Coming back clears the reach, and restores the invite only where the voice is still the
one the fall wrote — a halt raised during the fall stands after the return, because only
the **Desk** lifts one (ADR 0035).

## Consequences

A team can go and record while the room is down: the entry is open, the takes queue, and
the outbox empties itself the moment the room is back. That is what the record entry being
open for the whole session is for.

The next writer of the voice cannot end the way back, whatever it writes and whoever adds
it. Nothing has to remember this rule to keep it.

`offline` stops meaning two things at once. Where the code asks "is the room talking to the
server", it reads the reach; where it asks "what is the circle saying", it reads the voice.
