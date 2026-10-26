---
status: accepted
date: 2026-10-26
amends: 0070
---

# A revocation ends the life and sweeps its takes

## Context

ADR 0070 kept a take refused because the tablet was turned away, and sent it with the
next link. A relink may belong to another team, so the old team's recordings would go up
under the new team's credential. Outbox rows carry no life, credential or team, so nothing
else says whose a row is.

## Decision

A revocation ends the life of everything the tablet held. The sound and the microphone
are closed, the Outbox is emptied with its copies, and every recording on the tablet is
deleted. The Outbox refuses a take from the moment the life ends until a credential is
presented again, so a take handed over while the revocation lands is never written; its
copy goes with it. This supersedes the last paragraph of ADR 0070's Decision: nothing
waits for the next link.

## Consequences

- A take the revoked tablet had not yet sent is lost for good. The Desk unlinked the
  tablet, and the relinked room opens afresh.
- Recordings the room already holds come back through the resume fetch (ADR 0023).
