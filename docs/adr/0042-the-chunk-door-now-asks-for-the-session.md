---
status: accepted
date: 2026-09-25
---

# The chunk door now asks for the session

## Context

ADR 0039 put the chunk door among the calls that name a **Take** or a **Stretch**: a 404
there was read as a refused call on the three-strike ladder, never as the session gone,
because the server's chunk route answered both a dead session and a take that is not this
session's rehearsal take with the same 404.

ENG-1133 split that 404 in shema-api: the chunk route (and the replace route) now resolve
the session first, and a session gone keeps the 404 the session read already gives. The
take named in the form body is resolved by one query filtering on session, take id and
kind (rehearsal) together, so any of three misses on it — a take of another session, a
take id that never existed, or a take of this same session that is a back-translation
take rather than a rehearsal one — answers the same 422 `UNKNOWN_REFERENCE`, naming the
take. The chunk door can now tell a session gone apart from any of the three.

## Decision

**The chunk door (`sendChunk`) moves to the doors that ask for the session.** Its 404 is
read as the **Session** being gone, `notFoundIsTheSessionGone: true`, and the tablet leaves
the passage on it the way it does at every other session door. Its 422 (or any other
refusal) stays a refused call on the three-strike ladder, unchanged.

Divide and replace stay where ADR 0039 put them. Divide's 404 can still be a segment that
is not this session's. Replace resolves the segment before the take, so its 404 can still
be that same segment miss even though its take miss is now the same 422 the chunk door
gets; either way, replace's 404 stays a refused call.

## Consequences

A session the room has truly forgotten now costs the team the passage at the chunk door too,
instead of three strikes spent discovering it. A take named wrong at the chunk door — the
one case the team cannot act on from the screen — still walks the ladder ADR 0039 gave it.
