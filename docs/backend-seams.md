# Backend seams

The room talks to `tripod-backend` under `/api/internalization-room`, addressed by
`BACKEND_URL`. A linked tablet is known by its device credential alone, sent as
`X-Device-Credential` on every request; the app ships no shared key. The three claim doors
— minting a claim code, reading whether it was spent, collecting the credential — take no
header at all. The credential is handed to every client that speaks to the room, not only
the first, so the team's questions never arrive unnamed. An answer that says the device was
revoked, at any door, sends the tablet back to a fresh claim code (ADR 0070).

Every seam below is a provider, and every one of them is overridden in the suite.

## What each seam owns

- `roomRepositoryProvider` — sessions, turns, back-translation chunks and the verdict,
  takes, and the room's spoken clips. The takes listing answers which part of the
  rehearsal a recording stands for: it places a stretch the tablet holds no recording for
  (ADR 0022), and it is where a passage reopened without its recordings reads which parts
  to fetch back, through the take-audio door beside it (ADR 0023).
- `handInboxRepositoryProvider` — the facilitator inbox: raising a question, fetching
  replies, marking one heard. It keeps a client and a header block of its own.
- `takeUploadQueueProvider` — the outbox that carries kept takes and back-translation
  chunks through a flaky connection, retrying and eventually giving up.
- `connectivityServiceProvider` — whether the server is reachable, answered before the team
  ever taps.
- `workInProgressProvider` — the resume point, one row per passage.

## Timing and escalation

Timing is not hard-coded; it lives in providers so the suite can shrink it. They govern
how late a bead settles, how long the room may show itself busy, the ceiling on a
playback wait, the grace after a clip, the backoff
between retries, and how long the Closing lingers before the wheel reopens.
