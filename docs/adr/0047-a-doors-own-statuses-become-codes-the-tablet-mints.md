---
status: accepted, amended by 0051
date: 2026-09-30
---

# A door's own statuses become codes the tablet mints

## Context

ADR 0046 gave the room one client that answers every door with one of four results (an
answer, the network failed, a **Refusal** with the server's code, or **Session gone**) and
tells refusals apart by the code, never by the words. The server names most refusals with
a code of its own, but a few doors give a bare status a meaning only at that door: opening
a session answers 400 for a passage that cannot open, collecting the credential answers
409 for a row not claimed yet and 403 for a credential already handed out, the
device-scoped call for a person answers 404 or 409 when there is no team to reach, and
reading the link answers 204 when nobody has claimed the tablet. None of these carries a
code that says so: the 400 is the generic `BAD_REQUEST`, the 409 the generic `CONFLICT`.

## Decision

**The door decides its own statuses before the shared table does, and answers them as a
Refusal under a code the tablet mints** (`PASSAGE_CANNOT_OPEN`, `CREDENTIAL_NOT_YET`,
`CREDENTIAL_TAKEN`, `NOBODY_TO_REACH`), or as an answer (the link's 204 is an answer with
no team). Every other status goes through the one table:

- 2xx whose body reads is an answer; 2xx whose body does not read is refused as
  `UNREADABLE`.
- 429, any 5xx, a timeout, a transport error and no answer are the network.
- 404 is **Session gone** only at a door that asks for the session; elsewhere it is a
  Refusal.
- Any other status is a Refusal under the server's code, or, when the body names none,
  under a fallback (`NOT_FOUND` for 404, `HTTP_<status>` otherwise). It is never the
  network.

The room halts on `UNAUTHORIZED`, `FORBIDDEN` and `DEVICE_REVOKED`: a 401 is always
`UNAUTHORIZED`, and a 403 is `DEVICE_REVOKED` when the server says so and `FORBIDDEN`
otherwise.

Three decisions Henok made on 2026-09-29 come with the client:

- **The network is the network.** A 5xx, a 429, a timeout and no answer take the room out
  of reach, at every door. The slow path that told a timeout apart from a lost network, and
  the opening's thinking loop, are gone; the turn is resent under the same id while the
  room is reachable and the busy wait has time left, and the room goes out of reach when
  either runs out.
- **A refused recording leaves the Outbox at once.** It gets no second attempt, its file
  stays on the tablet and the room says the stranded line. A network failure still waits.
  A Session gone on an upload keeps spending an attempt until the Session gone slice
  (ENG-1175) discards the session's rows.
- **A stretch that no longer counts is never a strike.** A correction refused with
  `STRETCH_NO_LONGER_COUNTS` reads the stretches back and takes the ENG-1139 path, however
  many times in a row it comes: with no successor stretch the pending translation is
  dropped, and with one the telling is adopted or the stretch armed again. This amends ADR 0039's "a 400 or 404 on a call that
  names a Take or a Stretch is a refused call on the three-strike ladder" for that code;
  every other refusal of such a call stays on the ladder.

## Considered Options

**A result type per door** (a credential answer, a passage answer). Rejected: every caller
would switch over a different shape, and the one table would split again into one per door.

**Waiting for the server to name each of these.** Rejected for now: the statuses are the
contract these doors already have, and the minted codes can be replaced one by one by the
server's own when it names them.

## Consequences

A minted code never comes from the server, so nothing but the door that mints it produces
it. The streamed doors (the coverage channel and the voice's clip) classify their status by
the same table, without a body to read the code from.

## Amendment of 2026-10-01 (ENG-1174, the Reach region)

A 409 with the code `IDEMPOTENCY_KEY_IN_FLIGHT` (ENG-1170) is not a refusal of the request:
it says the same request is still being handled under the same key. The tablet waits the
backoff and sends it again under the same key; it is never a strike on the room and never
strands an Outbox row. Every other 409 keeps its code's meaning.

