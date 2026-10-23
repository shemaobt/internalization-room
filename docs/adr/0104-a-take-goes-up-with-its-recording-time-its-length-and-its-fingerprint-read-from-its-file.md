---
status: accepted
date: 2026-10-20
amends: 0087
---

# A take goes up with its recording time, its length and its fingerprint, read from its file

This amends ADR 0087 without editing its decision: it adds "amended by 0104" to its status
line. The server half is ENG-1273; this is the tablet half (ENG-1710).

## Context

A part kept at 10:02 and drained at 13:40 said 13:40: the room stamped the upload's arrival as
the recording time. The room now takes `recorded_at`, `duration_ms` and `sha256` on the keep
door and the scene rehearsal door, refuses a `sha256` that is not the bytes
(TAKE_FINGERPRINT_DIFFERS) and a `duration_ms` more than 100 ms from what it measures
(TAKE_DURATION_DIFFERS). Both are coded refusals, which the Outbox gives up for good, so a
value the tablet estimates is a take lost on the server.

## Decision

- The Outbox row keeps three values, fixed when the row is written and sent unchanged on every
  try, however late: the **Recording time**, the length and the fingerprint. A row an older app
  wrote has none and sends none.
- The Recording time is the recording file's last write, read before the copy: the recorder's
  final write is the stop.
- The length is read from the WAV header of the queued copy, from the data chunk only and never
  past the bytes present. An m4a, a WAV whose header never got its length and any other header
  send none; the room measures.
- The fingerprint is the sha256 of the queued copy, the exact bytes that go up.
- A conversation take carries none of the three; it does not go through the Outbox.
- The tablet's clock is never corrected; the room notes how far off it was.
- A joined part, when the tablet gets one (`origin`), stamps `recorded_at` when its request is
  built, on every attempt, not from its file (the Definer, 2026-10-19). No tablet join exists
  yet, so there is no code for it here.

## Rejected

- A stamp at `enqueue`: off by the time the team listened between the stop and the keep.
- A stamp at the stop kept in the notifier: a new lifecycle field in the notifier, which
  AGENTS.md "The room's core" forbids.
- A stopwatch: the recorder runs with `AudioInterruptionMode.pauseResume`, so a stopwatch counts
  a phone call's pause.
- A length for an m4a from a player or a guess: a value off by more than 100 ms is a take the
  Outbox gives up.

## Consequences

- ADR 0087's "the tablet announces no size or duration ... never counts a number" no longer
  holds for the scene take.
- A malformed length or fingerprint in a row sets the manifest aside as any other field does
  (ADR 0016). A malformed recording time does not: like the last-try stamp it is read
  leniently, because the take still goes up without it and the room stamps its arrival, while
  setting the manifest aside would strand every pending recording for a field that is optional.
- The queued copy is read and hashed off the UI isolate: the keep tap waits for it, and 25 MB
  took 135 to 155 ms on a Mac.
- The room, not the tablet, says how far off the tablet's clock was. A join row (0120) keeps its own Recording time, the tablet's raw clock as the row is written, and also sends `sent_at`, the tablet's clock as each request is built, from which the room measures the offset (amended 2026-10-23, Definer Q67).
