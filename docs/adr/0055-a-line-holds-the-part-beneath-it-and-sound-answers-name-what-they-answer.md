---
status: accepted
date: 2026-10-06
amends: 0053 (the Sound port's one-at-a-time rule, decided under ENG-1442)
---

# A line holds the part beneath it, and sound answers name what they answer

## Context

ENG-1452 moves the sound effects out of the temporary `EffectHost` and into the effect
runner, which plays them through the Sound port. Two things ADR 0053 does not say came up.

First, ENG-1442 settled that the Sound adapter stops the other kind of sound
unconditionally. That was harmless while lines did not go through the port. The machine
plays a line only over silence or over a part on hold (`GuideSpeaking` holding a `Paused`),
and that held part comes back once the line is said. A stopped player cannot resume, so
routing lines through a port that stops the part would kill every held part beneath a line.

Second, the runner reports what happened to a sound as the answering events that already
exist. A line cut by a part does not move the generation, so a bare `PlayerEnded` or
`PlayerFailed` for that line would end or fail the part now sounding. The generation alone
cannot tell the two apart.

## Decision

- **A part cuts a line; a line holds the part.** The Sound adapter stops the voice before
  a part plays. Before a line plays, it pauses the part instead of stopping it. One sound
  still plays at a time, and a held part can still come back.
- **A sound answer names what it answers.** The runner brings back `PlayerEnded`,
  `PlayerFailed` and `LineNotSaid` carrying the line they answer, or no line for the part.
  Each is stamped with the generation the sound was played under. A dropped line comes back
  as `LineNotSaid`.
- **Station work stays in the notifier's answer.** Until the Stations move into the machine,
  the notifier receives these answers. It hands the machine a line's answer only while that
  line is still the one speaking. It runs what a gesture waits on: the line's completion,
  the gesture's callbacks, the listening ledger and the retro cursor.
- **The part's ceiling is a runner timer.** The flat ceiling applies while the clip opens.
  After that, the ceiling is what is left of the clip plus the grace. A hold cancels it, and
  a run arms it again.

## Consequences

- The natural end of a part is now stamped with the generation of the `PlayPart` that
  started it, where it used to read the current generation. One path moves the generation
  without silencing the room: the busy-state watchdog giving up while the room waits on the
  Guide. If a part were playing there, its end would be dropped and the part would stay
  playing. No test reaches that path, and it is not known whether the team can play a part
  while the room waits on the Guide.
- The gestures' own silence still stops both players directly. Moving it is Station work.
