---
status: accepted, amended by 0049, 0050, 0067 and 0068
date: 2026-09-29
amends: 0033, 0036, 0044
---

# The room's lifecycle is one machine of four regions

This amends ADRs 0033, 0036 and 0044 without editing them; what changes in each is said
under Consequences.

## Context

By the end of September about a third of the room's bug tickets were lifecycle defects: a
halt and its lift, a resume after the app was killed, a part recorded again, a lost answer,
the Outbox. They all lived in one notifier that grew from 2,686 to 5,197 lines in the month,
with fifty-five fields in its state and eighty-two private ones beside it, and no statement
anywhere of which combinations are valid. Each fix added a field or a branch, and three
quarters of the month's app commits were fixes. The hand test of 2026-09-28 and the findings
of the round before it (ENG-1151 to ENG-1157) were all of that kind. Henok modelled the
lifecycle before any of them was fixed.

## Decision

**The room's lifecycle is one state machine with four regions that change independently.**

- **Station**, with the **Step** of the team's work as its substate. Invitation: welcome,
  panorama. Choice: loading the Wheel, offering, opening the passage. Conversation: the
  team's turn, awaiting the Guide, team-talk. Rehearsal: nothing pending, a take pending
  (the part being recorded again is durable data). Back-translation: telling, storing a
  stretch, awaiting the verdict, findings, mending the short way, checked, approving.
  Closing: closing the necklace. A Step belongs to its Station, so leaving the Station ends
  it.
- **Channel**: silence, an open microphone with its owner (conversation, rehearsal, capture,
  question), the Guide speaking, a part playing, a stretch playing, paused. One at a time:
  the room never records and plays together. A line that arrives with no gesture while the
  microphone is open or a halt stands is a **Queued line**: it waits in a short queue, one of
  each kind, in arrival order. The **Head** is the Cursor until the player confirms the
  opening.
- **Halt**: none, warning, blocking. A blocking halt never changes the Station or the Step;
  it closes and discards any open microphone, silences the Channel and keeps only what was
  sounding. A blocking halt over a warning wins, and the warning stands again after it. There
  is one lift, whatever the Station: it replays what was kept, unless the Step changed while
  halted, when only the new Step's line plays. While a blocking halt stands the team has the
  long press, the hand, and the way out only on a checked passage whose approval was
  refused; with nobody to ask, the long press releases locally (ADR 0009).
- **Reach**: online, offline. A network failure at any door, the Outbox's included, takes
  the room offline; coming back drains the Outbox and re-sends the pending request under the
  same key. Going offline does not close an open microphone: what needs the server waits.

**Outside the regions.** The Outbox is an aggregate of its own; the machine sees one fact
per part: sent, pending or stranded. A gesture that needs a pending part is accepted, shows
that it is sending, and goes on by itself when the part lands. **Session gone** is one event
with one destination: whatever was the session's is discarded (the pending translation, the
Resume point, its Outbox rows and their files), the microphone closes, and the room returns
to the Choice.

**Events.** One room client makes every call to the server and returns one of four results:
an answer, the network failed, a **Refusal** with the server's code, or the session gone. It
classifies by the code, never by the words, and nothing past it catches exceptions. Every
read of the session is one event, the **Session read**, applied whole through whichever door
it came. The player reports opened, ended and failed; a failure leaves the Channel silent
and the Cursor kept. Timers are effects the machine asks for, and their firing is an event;
a Step that ends cancels its own. The Watch is armed whenever the Halt is not none. An answer
changes the Station only in the Step that asked for it; one that lands during a blocking
halt advances the Step in silence, and its line plays after the lift.

**What is durable.** The Resume point is the durable slice of the machine, written whole at
every transition: the Station and Step, the kept takes, the part being recorded again, the
Cursor, the pending translation and the Listening ledger. On a reopening the server rules
over what it knows (whether the session exists, the current take of each part, the
stretches, the halt, the warning, the verdict) and the slice rules over the rest. The Outbox
follows the slice: a take the slice holds pending and the Outbox lacks goes back in, and a
row the slice does not know is delivered anyway, so no audio is ever lost. Reopening by the
way out or after a kill is the same event.

**A Wordless recording is the server's to answer**, as in Marcia's app: the tablet keeps its
700 ms and 800-byte floor, and a stretch or a question with no words is refused with a code
and answered with the inaudible line, as a turn already is.

**Invariants.** Each is a test that drives generated sequences of events and checks after
every step:

1. The microphone never opens under a sound.
2. A blocking halt never stands over an open microphone.
3. A halt never stands without the Watch.
4. An answer never moves the Station outside the Step that asked for it.
5. A Session read is never applied in part.
6. Nothing of a gone session survives.
7. A Wordless recording never becomes a kept take, a stretch or a question.
8. The Head never reads another part's or stretch's position.
9. A stretch on a superseded take has no place and counts as told nowhere.
10. A told stretch always has a playable telling.
11. An accepted gesture never vanishes in silence: it moves the room, or shows it is
    waiting, or its control was already dimmed.
12. The Outbox never idles online with a part pending.
13. The screen never shows a sound the Channel does not hold.
14. Reopening from the same slice always lands in the same place.
15. A warning is the same on the tablet, on the server and on the Desk.

## Considered Options

**Keep the fields and add the invariants as tests only.** Rejected: the tests would find the
bad combinations, but nothing would stop the next fix from adding another field.

**The halt as a value of the circle's voice**, as it was. Rejected: entering it erased
offline and thinking, and two separate lifts guessed where to return.

**The Outbox inside the machine.** Rejected: its order and its retries are rules of their
own, and every row would pass through the room's transitions.

**A statechart library.** Not needed: the only history the room keeps is what a halt caught
sounding, one field.

**Detecting silence on the tablet.** Rejected: Marcia's app sends a wordless take to the
server, which answers it, and a take of twenty seconds with no words means the team spoke
its own language.

**The Listening ledger left in memory, the Cursor standing for what was heard.** Rejected by
Henok: after a kill, the report would count less than the team heard.

## Consequences

ADR 0036 is widened: a halt closes and discards every open microphone, not only the capture.

ADR 0044 is amended: the scissors and the capture read the Head, which is the Cursor until
the player's opening, no longer the live position from the first instant.

ADR 0033 is narrowed: the stored row wins only over what the server does not know.

ADR 0009 stands, local release included.

The server has to state a warning as a warning in the Session read, and the Desk has to list
it. A stretch or a question with no words needs a refusal code on the server.

The notifier is emptied into the machine one region at a time, starting with the Halt; the
private fields and epoch guards of each region go with it.
