# The outbox stamps in UTC, and reads only the stamp leniently

## Context

The **Outbox** paces its retries off the instant of each row's last attempt. A bare local
time makes that pacing depend on the tablet's clock and timezone surviving a restart, which
they need not.

## Decision

Each row's last attempt is stamped in UTC. A stamp sitting ahead of the tablet's own clock
counts as already due, and a stamp that is not text at all reads as no stamp, so the row
comes due now. That tolerance covers the stamp alone: every other field is read strictly,
and a bad one sets the whole manifest aside.

## Consequences

A clock moved backwards, or a timezone change across a restart, no longer leaves every
queued recording pacing against a moment that never comes — and it would have done so
silently, because a row that is merely never ready is neither exhausted, lost, nor stalled,
and those three are the only states the room says out loud. The strictness elsewhere is
deliberate: a row whose file or **Session** cannot be read points at nothing the queue could
send, so setting the manifest aside is the honest answer rather than a data loss.
