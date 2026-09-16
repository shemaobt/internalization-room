# A part recorded again keeps its number and its place

## Context

A **Finding** that names a **Stretch** can mean the recording itself was wrong, and then
what has to be recorded again is the whole **Part** that stretch sits in. The room had no
gesture for it: the only way back to the microphone kept every **Take** and appended, so
a scene 2 recorded again landed as scene 4, and the only in-place path threw the whole
rehearsal away.

A **Part** addresses nothing by name. A **Stretch** says which part it sits in by where
that part sits in the row, and so do the **Ruler** and the **Listening ledger**. A part
that moved would take the whole rehearsal with it.

## Considered Options

Appending the new recording and renumbering the row. Rejected: every stretch of every
later part addresses a number, and renumbering rewrites all of them at once — for a
correction that touched one part.

Leaving the old part's stretches on the cord as drained **Band**s. Rejected: ADR 0011
fixed what a drained band means, and it is *waiting to be mended*. This ground is waiting
to be told, which the cord already draws as absence.

Waiting for the server to retire the old stretches before trimming them here. Rejected:
the tablet would draw bands over ground nobody has explained until a round trip lands,
and the next telling-back would step over a part the team has not heard.

## Decision

Recording a part again replaces it in its own place: the same scope `parte-N`, the same
number on the wire, a new file and a new name. The other parts keep their recordings,
their stretches, their bands and their listening. The stretches told over the recording
that was replaced leave, as untold ground.

The name goes to the file it was given for, not to every take of the scope: two
recordings now share a scope, and the outbox row is what tells them apart.

A **Missing without an address** keeps the appending path (ADR 0002): it is the end of
the story nobody recorded, not a part recorded badly.

## Consequences

Two takes of one part reach the server under one scope, and which of them is the part is
decided there by pass and arrival. The outbox can send them out of order — a row backing
off after a failure is skipped while a later row goes — so a retry landing after the
re-recording would leave the room holding the recording the team abandoned. Nothing in
this slice guards against that, and the contract has no per-part pass to guard it with.

The replaced file stays on the tablet. Nothing points at it, and deleting audio a team
recorded is not a thing this room does quietly.
