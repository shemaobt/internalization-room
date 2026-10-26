---
status: accepted
date: 2026-10-26
amends: 0070
---

# A revocation ends the life and sweeps its takes

## Context

ADR 0070 kept a take refused because the tablet was turned away and sent it with the
next link. A relink may belong to another team, and Outbox rows carry nothing that says
whose they are, so the old team's takes would go up under the new team's credential.

## Decision

A revocation ends the life. The Outbox is emptied with its copies and every file in the
recordings folder is deleted (unsent takes, retellings and the parts fetched from the room;
the room fetches them again on a resume), and only after that does
the tablet forget its link (ADR 0070). From the revocation until a credential is presented
again the Outbox refuses a take; one being enqueued as the revocation lands is dropped with
its copy and its source file.

The link is the durable record that the sweep is not done. When the sweep fails, the link
stays and the sweep is tried again on the room's retry ladder; if the app restarts meanwhile
it presents the revoked credential, is refused again and sweeps again. A relink therefore
always finds the Outbox empty.

## Considered Options

- Keep the rows and send them after the relink, as ADR 0070 did: rejected, for the reason
  in Context.
- Mark each row with its team and skip the foreign ones: rejected, it needs a migration.

## Consequences

- An unsent take of the revoked tablet is lost for good.
- A copy whose row is gone because the manifest was unreadable and quarantined is not found
  by the sweep; it stays in the queue folder and is never sent.
- The resume ledger survives and names files that are gone; a resume fetches them again.
- A sweep that failed only on the recordings folder is tried again when the revoked
  credential is next refused. With an empty Outbox the launch sends nothing to the room, so
  that waits for the first room call.
- A recording the revoked life keeps in the milliseconds after the sweep listed the folder
  stays there; it is never sent.
