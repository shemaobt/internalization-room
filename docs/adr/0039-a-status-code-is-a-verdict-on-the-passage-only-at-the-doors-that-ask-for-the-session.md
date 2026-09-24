---
status: accepted
date: 2026-09-24
---

# A status code is a verdict on the passage only at the doors that ask for the session

## Context

The room's one decoder read every 404 as the **Session** being gone and every 400 as the passage
being shut, on all eighteen calls that go through it, and the notifier answered both by forgetting
the **Resume point** and leaving the passage. The server never had an answer that means "passage
shut": its only 400s are an unknown language on session creation and audio over 25 MB. On the
stretch route a 400 is an empty or inverted slice and a 404 is a take that is not a rehearsal
take of this session; on divide and replace a 404 is a segment not in this session.

On the by-hand test of 24 September a cut with the playhead still on the stretch start sent an
empty slice; the 400 was read as a shut passage, the row of a live session with four rehearsal
parts and a stretch was forgotten, and the next entry minted an empty session. That is the loss
ADR 0031 closed for the clock, arriving through a status code.

## Considered Options

**The stretch route answering its refusals as a 200 with a field**, the shape ADR 0028 gave the
release. Set aside: an empty slice is the tablet's own mistake, which it stops making, and the
take not being the session's is not something the team can act on from the screen.

## Decision

**The room says it does not know the session only when the tablet asked about the session
itself** — the state read, the turns, the takes listing, the person calls, the release and the
finish. **A 400 is never a verdict on the passage**, and the meaning "passage shut" retires with
its class and the scenario that rehearsed it. A 400 or 404 on a call that names a **Take** or a
**Stretch** is a refused call on the three-strike ladder every other refused call already walks:
the row stays and the team stays where they are. **A cut with the playhead at or behind the
stretch start records nothing.**

## Consequences

A session the server has truly forgotten still costs one answer on the first door that asks
about it, as before (ADR 0031). A refused stretch costs the team a person after three strikes
instead of their session. The device routes keep their own answers; session creation and the
passages listing are not about a session, and where their 404 lands is the executor's call,
said in the PR.
