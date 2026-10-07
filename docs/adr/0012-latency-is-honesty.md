---
status: accepted, amended by 0056
---

# Latency is honesty

Amended by ENG-1268 (where the Fixed line comes from): the tablet no longer plays it from the
bundle. It asks the room for the line by family and position, once per run, keeps the sound,
and plays that clip the moment the recorder stops. Wherever this record says bundled for
the Fixed line, read that: the line is on the device once the room has answered, not
shipped with it.

## Context

Every turn the team speaks goes to the server, and the answer takes time. The room needed
something to occupy that wait that would not read to the team as a machine thinking.

## Considered Options

A spinner, or any other progress affordance. Rejected: it announces that the team is waiting
on software, in a room whose whole design hides that.

## Decision

A **Fixed line** is played from the bundle the moment the recorder stops, before any request
leaves the tablet, rotated so it never repeats twice running. The wait then belongs to the
conversation. The **Guide**'s thinking state is calm clay, never a spinner.

## Consequences

The line costs nothing to start, because it is already on the device, and the request goes
out behind it without waiting for playback to finish. Two earlier exits run before it, so
the acknowledgement is what a capture gets once it has passed them: a capture that produced
no file halts for a person instead, and a capture too short to be speech is answered by a
different bundled line asking the team to say it again.
