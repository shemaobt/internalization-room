---
status: accepted
date: 2026-09-30
amends: 0046
---

# A sound that fails leaves silence, and no line interrupts

This amends ADR 0046 without editing it.

## Context

ADR 0046 made the Channel one region beside the Halt: one sound or one microphone at a
time, a short queue of lines, and the Head that is the Cursor until the player confirms
the opening. Moving the Channel into the machine (ENG-1172) needed three rules 0046 left
open. Every failure of a part or a stretch was a blocking halt, while a Guide line called a
person only on the third unplayable turn. A new line stopped the one in the air, and a part
landing stopped the Guide. The circle's voice was a field written in seventy places, so it
could say the room was speaking, inviting or done over a Channel that held something else.

## Decision

**A sound that fails leaves silence.** The Channel goes silent, the Cursor is kept, the bead
still answers a tap and nobody is called. **The second failure in a row on the same source
calls a person**, the rule ENG-1159 gave the hand's reply. The Guide is one source, a take
is one source and a stretch is one source; a success on that source resets the count, and
so does a failure on another one. Guide lines move from the third failure to the second.
The Guide's fixed courtesy lines (the instant acknowledgement, the offline notice, the
stranded line, the blocked microphone) and the facilitator's reply are not counted: the
reply keeps its own set-aside rule. Henok, 30-09.

**No line interrupts.** Every line, spontaneous or the answer to a gesture, waits in the
queue until the Channel is free: one line of each kind, in arrival order, while a sound
plays, a microphone is open or a blocking halt stands. Only a halt and leaving the passage
silence what is sounding. A team gesture that changes what sounds (a bead, the pause, the
scissors, opening a microphone, moving the wheel) still stops or holds the sound first, as
ADR 0024 says; the rule governs lines, not gestures. When the gesture is over, a free
Channel plays the line that waited. Henok, 30-09.

**The voice is a reading, never a fact.** The circle's voice is derived from the Halt, the
Reach, the Channel and the Step: a blocking halt, then the Reach down, then an open
microphone, then the Guide speaking, then the room awaiting the Guide, then the end of the
passage, then the invite. Nothing writes it. **The circle reads offline whenever the Reach
is down**, even over a gesture that used to write the invite over the fall. The microphone's
owner is a fact of the Channel; the question's label comes from it. Henok, 30-09.

## Considered Options

**A Guide line's source is the line's address.** Rejected: a server that serves a broken
clip on every turn hands each turn a new address and never calls a person.

**Remove the voice service's stop before each line.** Rejected (Henok, through the
Orchestrator, 30-09): the stop clears just_audio's playing latch on iOS, without which the
next line never sounds. It stays for the player, and it no longer cuts a line: lines reach
the service one at a time from the Channel, and the service chains them.

## Consequences

Two Step facts stand in for the Steps until ENG-1176 and ENG-1178 bring them: the room is
awaiting the Guide, and the end of the passage. Leaving a Station ends both.

The offline notice has no path under an open microphone until ENG-1174 takes the room out
of reach from every door; today it is spoken only from doors the room calls while it is
thinking.

A part that fails in the Back-translation no longer sends the team back to the Rehearsal.
