---
status: accepted
date: 2026-10-06
amends: 0053
---

# A line holds the part beneath it, and sound answers name what they answer

This amends ADR 0053 without editing it; it adds "amended by 0055" to its status line. The
Orchestrator settled it on 6 October while the sound effects left the notifier (ENG-1452).

## Context

The effect runner now plays every line and part through the Sound port. ADR 0053 did not
settle four things.

First, ENG-1442 decided that the Sound adapter stops the other kind of sound unconditionally.
That was harmless while lines did not go through the port. But the machine plays a line only
over silence or over a part on hold, and the held part is meant to come back once the line is
said. A stopped player cannot resume.

Second, a line cut by a part does not move the generation. So a bare end or failure of that
line would end or fail the part now sounding.

Third, what a gesture does after its sound is Station work: the line it waits on, the
callback it hung on a part, the listening ledger and the retro cursor. That work cannot live
in the runner. It also cannot hang off the effect list or the type of an event, because that
would be a second switch beside `reduce`.

Fourth, when a part ends, the Station may start the next sound. That has to happen before the
machine is told the part ended, so that the machine does not drain a waiting line into the
gap.

## Decision

- **A part cuts a line; a line holds the part.** The Sound adapter stops the voice before a
  part plays. Before a line plays, it pauses the part instead of stopping it. One sound
  still plays at a time.
- **A sound's answer names what it answers.** The runner answers the machine with
  `PlayerEnded`, `PlayerFailed` and `LineNotSaid`. Each one carries the line, or the part's
  sound. A part's answer is stamped with the generation the part was played under. A line's
  answer is stamped when it comes back, so the gesture waiting on the line always hears how
  it ended. `reduce` drops an answer whose sound is not the one in the Channel. A dropped
  line comes back as not said.
- **The machine keeps how the last line ended:** the line, said, failed or not said, and the
  room failure that stopped it. The notifier reads that on the transition and answers the
  gesture waiting on the line. It measures a part once the machine takes the part's opening.
  The retro cursor hears the runner's own hold and run of the part.
- **The Station hears a part's end before the machine is answered.** One subscription in
  the runner calls the Station's hearing first and answers the machine second. A part the
  Station starts on that end makes the old part's answer one that `reduce` drops.
- **No runner timer survives a silence.** A gesture's silence reaches the runner as the
  machine's own stop, which cancels the part's ceiling, as a hold does. The ceiling is the
  flat one while the clip opens. It becomes what is left of the clip plus the grace only
  when the machine takes the opening of the part it is playing, so the opening of a part
  already stopped arms nothing.
- **`ReplayTheSound` decides and never sounds.** Which part to put back, and from where, is
  Station state. The decision stays on the host until the Stations move, and the sound
  reaches the port through the part the machine is then asked to play.

## Considered Options

**The adapter keeps stopping the part before a line.** Rejected: every part held beneath a
line would die there.

**The notifier keeps today's checks and switches on the answer's type.** Rejected: that is a
second machine. `reduce` alone decides what a stale or foreign answer does.

**The machine is answered first, and the Station acts on the transition.** Rejected: the
machine would drain a waiting line into the gap, and the next sound the Station starts
would cut it at once.

**The line carries a callback that the runner calls when the line ends.** Rejected: the
runner would run Station work.

## Consequences

- Two plays of the same part look the same to `reduce`. If the Station starts the very part
  that just ended, the old part's end is not dropped and ends the new play. Nothing in the
  room does that today.
- Every path that moves the generation silences the room, so no part stays Playing without a
  ceiling.
