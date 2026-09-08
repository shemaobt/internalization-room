# A halt is lifted by the Desk, not by the tablet

## Context

When the room cannot carry on alone it enters a **Halt** and makes a **Call for a person**.
The question is who ends it: the tablet in front of the team, or the **Facilitator** at the
**Desk**.

## Considered Options

Letting the tablet lift its own halt. Two existing tests encoded that behaviour; both were
rewritten rather than the rule bent to fit them.

## Decision

Only the **Desk** lifts a blocking **Halt**. On the tablet the long press asks the server to
read the session's state again; it never releases the halt itself. Where there is nobody to
ask — the session gone with the halt, or the room offline — the long press keeps the local
release it always had.

## Consequences

A **Facilitator** who has just marked the session attended hands the room back at once,
because the press forces the read rather than waiting on the next poll. If the server still
says halted, the room stays halted and says nothing again. Recording that a person arrived
and lifting the halt are two separate acts, and only the second one unblocks the team.
