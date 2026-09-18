# Backend seams

The room talks to `tripod-backend` under `/api/internalization-room`, addressed by
`BACKEND_URL` and authenticated with `INTERNALIZATION_ROOM_KEY`, sent as `X-Room-Key` on
every request. A tablet that has already been linked also carries a credential of its own,
sent as `X-Device-Credential`; where that header is present the server judges the tablet by
it alone, and the room key still rides along beside it until retiring it becomes its own
change. The credential is handed to every client that speaks to the room, not only the
first, so the team's questions never arrive unnamed.

Every seam below is a provider, and every one of them is overridden in the suite.

## What each seam owns

- `roomRepositoryProvider` — sessions, turns, back-translation chunks and the verdict,
  takes, and the room's spoken clips. The takes listing answers which part of the
  rehearsal a recording stands for, which is what places a stretch the tablet holds no
  recording for (ADR 0022).
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
