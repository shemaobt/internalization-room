---
status: accepted
date: 2026-09-25
---

# The player takes one change of source at a time

## Context

On the tablet, the findings play stopped at the switch from the mother tongue to the
telling. The log showed just_audio's `PlatformException(abort, Loading interrupted)` and
`Platform player already exists`. After that no play ended, and the circle could not
record.

Read in the source of just_audio 0.9.46, the platform accepts one change at a time. A stop
deactivates the platform, and a load or a play on an idle player activates it again. When
one starts while another is still settling, the platform breaks:

- **A load begun while a stop is still settling** is interrupted.
- **A stop given while an activation is still in the air** interrupts it. If the
  activation had already created its native player, that player is never disposed. Every
  open begins with a stop, so an open over a load in the air does this too.
- **A play given while a stop is still settling** starts one of those activations under
  the stop.

After a leak, every later load asks iOS for a player that already exists. That call never
completes, so the room waits for ever on a sound that never comes.

The room reached all of them. Every stop the notifier issues is unawaited, so the next
source started with the stop still in flight. The completion that chains the mother tongue
into the telling does exactly this. ADR 0034 made a second open over a load in the air
safe for the repository's own count: it treated the superseded open as silence. It never
asked whether the platform survives that second open. The playback doubles let all of it
through, so every gate stayed green.

A second defect sat behind the first, and only the simulator showed it. just_audio keeps
`playing` true at the end of a clip, and `playerStateStream` pairs `playing` with the
processing state. The stop the room gives after the end flips `playing`, so the stream
says `completed` a second time. The repository read that as the end of the next clip.
The telling was therefore closed before it made a sound.

## Considered Options

**Awaiting the stop in the notifier before every new source.** Rejected. There are nine
paths that change the source. The repository's own stop before a load, the rehearsal's
chained clips, the resume and any gesture added later would all be left out. ADR 0034
already rejected deciding the player's rule in the notifier.

**Letting a stop cut the load in the air, as before.** Rejected. That is the leak.

## Decision

**`PlaybackRepository` changes the platform's source one step at a time.** Each stop, and
each open (its own stop plus the load), waits for the one before it to settle.

- A stop still takes effect the moment it is asked for. It holds the player's wanted
  state and clears the measure at once, so a load that settles behind it announces
  without sounding, as ADR 0024 says.
- An open waiting its turn keeps its generation. If a later open of ours supersedes it
  while it waits, it never loads.
- A resume given while an open is still pending does not touch the platform. It only
  wants the sound, and the open plays when its load returns.

**The end of a clip is read from the processing state alone.** The repository listens for
the processing state becoming `completed`, once per clip. A change of `playing` is never
an end.

The repository's API is unchanged.

This amends one paragraph of ADR 0034, "An open a later open of ours superseded is
silent, and is no failure". The superseded open is still silent. The difference is that
the later open no longer interrupts it. The later open waits for the first load to
settle, and the first open then returns without announcing.

## Consequences

The second of two quick gestures now waits for the first clip's file to finish loading
before its own source opens. On an old tablet with a long take, the team hears the second
clip later by the length of that load, not over it.

The platform double in the repository's tests has learned these failures, and it re-emits
the player state the way just_audio does. It throws where the real player hangs, so a
test fails instead of timing out. It refuses a second load in the air outright, which is
stricter than the platform.

A load that never returns would now block every stop and open behind it. Only a leaked
native player causes such a load, and the leak is what this decision prevents.
