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

## Note of 2026-09-25

The Context above says the server's only 400 on session creation is an unknown language. That
is false: `POST /sessions` also answers 400 when the passage cannot be opened, through
`require_walkable(load_map(...))` in shema-api `services/internalization_room/sessions.py:172`.
With the decision as written, that 400 became a refused call with `turnCall: true`, so a person
was called at once, which is the behaviour e2e5be5 had fixed. It is reachable from a wheel older
than a deploy, or from a resume whose fresh session lands on a passage that has since become
unwalkable.

Henok decided on 2026-09-25: **a 400 at session creation, and only there, is the passage that
cannot open.** The team goes back to the wheel, no strike is counted and no person is called.
Every other 400 stays a refused call on the three-strike ladder. The code lands in a follow-up
PR of ENG-1108.

## Note of 2026-09-25 (ENG-1134)

The note above reads as if a 400 at session creation never calls a person. ENG-1134 adds the
one case it does: the Choice keeps, for the visit it is on, every pericope the room has
refused this way; a refused passage is not offered again in the same visit, until the Choice
is opened afresh. When every non-panorama passage the wheel holds has been refused in this
visit, the room calls a person through the same halt a book with nothing left to offer already
takes — same halt, same fixed line, no new one. A single refusal still costs no strike and
still sends the team back to the wheel; only the wheel running out of anything unrefused to
offer reaches the halt.

Lifting that halt at the Choice is itself a fresh visit: the memory of what was refused is
cleared and the server is asked again, the same as leaving the book and coming back. A book
the server still has nothing for calls a person again at once — the long press no longer
pretends the problem is solved when it is not.
