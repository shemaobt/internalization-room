---
status: accepted
date: 2026-10-26
amends: 0070
---

# A revocation ends the life and sweeps its takes

## Context

ADR 0070 kept a take refused because the tablet was turned away and sent it with the
next link. A relink may belong to another team, so the old team's takes would go up under
the new team's credential. Outbox rows carry no life, credential or team, so nothing else
says whose a row is.

## Decision

When the tablet is revoked, the sound and the microphone are closed, the Outbox is emptied
with its copies, and the files in the recordings folder are deleted. From that moment the
Outbox refuses a take, and one being enqueued as the revocation lands is dropped with its
copy and its source file, until a credential is presented again. If the sweep fails, it is
run again before that credential is presented and the Outbox sends nothing until it has
succeeded.

The Outbox still keeps and re-sends a take on a plain 401 and at launch, as ADR 0070 says.
Only a revocation sweeps it.

## Considered Options

- Keep the rows and send them after the relink, as ADR 0070 did: rejected. A relink to
  another team sends the old team's recordings under the new credential, and a row carries
  nothing that says whose it is.
- Mark each row with the credential or team it was recorded under and skip the foreign
  ones: rejected for now. It needs a manifest migration and still leaves the old team's
  audio on the tablet, which the ticket's rule forbids.

## Consequences

- An unsent take of the revoked tablet is lost for good.
- A resume point survives the revocation and fetches the room's parts again when its files
  are missing (ADR 0023).
