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
- A resume touches the platform only for the clip in hand. With an open still pending it
  only wants the sound, and the open plays when its load returns. After a stop it does
  nothing: the clip the room stopped is not the clip it comes back to (ADR 0034), and a
  play given over a stop that is still settling would activate the platform under it.

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

A platform call that never returns now blocks every stop and open behind it, and the
queue has no timeout. The repository's own gestures no longer leak a native player, but
other things still can hang a call:

- just_audio deactivates the platform by itself, outside the queue, when the platform
  reports it is idle.
- A native player left over from a debug hot restart answers every later init with
  `Platform player already exists`.

What bounds this for the team today is the notifier's listening ceiling. A clip that never
announces itself is released by the generic ceiling, six minutes, so the room plays
silence for that long and then moves on. It
does not halt, and it does not stay "sounding". No timeout is added until a hang is seen
where the ceiling does not cover it.
