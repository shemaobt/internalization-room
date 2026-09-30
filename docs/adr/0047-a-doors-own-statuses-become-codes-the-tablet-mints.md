---
status: accepted
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
  under a fallback (`UNAUTHORIZED` for 401, `FORBIDDEN` for 403, `NOT_FOUND` for 404,
  `HTTP_<status>` otherwise). It is never the network.

The room halts on `UNAUTHORIZED`, `FORBIDDEN` and `DEVICE_REVOKED`, the three codes the
server gives a 401 or a 403.

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
