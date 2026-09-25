# The player takes one change of source at a time

## Context

On the tablet, the findings play stopped at the switch from the mother tongue to the
telling. The log showed just_audio's `PlatformException(abort, Loading interrupted)` and
`Platform player already exists`. After that no play ended, and the circle could not
record.

Read in the source of just_audio 0.9.46, the platform accepts one change at a time. A stop
deactivates the platform, and a load activates it again. When one of these starts while
another is still settling, three things can go wrong:

- **A load begun while a stop is still settling** is interrupted.
- **A stop given while a load is still in the air** also interrupts the load. If the load
  had already created its native player, that player is never disposed.
- **A load begun while another load is still in the air** leaves a native player behind
  in the same way.

After a leak, every later load asks iOS for a player that already exists. That call never
completes, so the room waits for ever on a sound that never comes.

The room reached all three. Every stop the notifier issues is unawaited, so the next
source started with the stop still in flight. The completion that chains the mother tongue
into the telling does exactly this. ADR 0034 made a second open over a load in the air
safe for the repository's own count: it treated the superseded open as silence. It never
asked whether the platform survives that second open. The playback doubles let all three
through, so every gate stayed green.

## Considered Options

**Awaiting the stop in the notifier before every new source.** Rejected. There are nine
paths that change the source. The repository's own stop before a load, the rehearsal's
chained clips and any gesture added later would all be left out. ADR 0034 already
rejected deciding the player's rule in the notifier.

**Letting a stop cut the load in the air, as before.** Rejected. That is the leak.

## Decision

**`PlaybackRepository` changes the platform's source one step at a time.** Each stop, and
each open (its own stop plus the load), waits for the one before it to settle.

- A stop still takes effect the moment it is asked for. It holds the player's wanted
  state and clears the measure at once, so a load that settles behind it announces
  without sounding, as ADR 0024 says.
- An open waiting its turn keeps its generation. If a later open of ours supersedes it
  while it waits, it never loads.

The repository's API is unchanged.

This amends one paragraph of ADR 0034, "An open a later open of ours superseded is
silent, and is no failure". The superseded open is still silent. The difference is that
the later open no longer interrupts it. The later open waits for the first load to
settle, and the first open then returns without announcing.

## Consequences

The second of two quick gestures now waits for the first clip's file to finish loading
before its own source opens. On an old tablet with a long take, the team hears the second
clip later by the length of that load, not over it.

The platform double in the repository's tests has learned the three failures. It throws
where the real player hangs, so a test fails instead of timing out.

A load that never returns would now block every stop and open behind it. Only a leaked
native player causes such a load, and the leak is what this decision prevents.

`resume()` still plays straight on the platform. A resume during a load does not deactivate
it, so it is safe. A resume given while a stop is still settling would activate the
platform over that stop. The one way the room can do that is a hold and a resume on the
findings play, both tapped in the milliseconds between the two voices. That window is left
open, and recorded here.
