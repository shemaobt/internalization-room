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
decided there by pass and arrival. The outbox could send them out of order — a row backing
off after a failure was skipped while a later row went — so a retry landing after the
re-recording left the room holding the recording the team abandoned. Nothing in this slice
guarded against that, and the pass the contract already has was a count of the whole
rehearsal with no increment left. ADR 0025 closed it: a part's recordings leave in order,
and each goes up under its own count.

A **Composed passage** went with the part it was built from, while the room still built
them: ADR 0022 has since retired them. The room kept a rebuilt passage under the number of
the recording it was composed out of, and it retires the stretches of every earlier
rehearsal take under the number that arrives — by kind and number, never by scope — so the
composition's stretches were retired along with the replaced part's. Nothing addressing
the composition came back afterwards, and the tablet's swap of a rebuilt passage into a
part never found one to make. What is left is
the upload the room reads as an old retry rather than as this part: it retires nothing,
and that is the consequence above, not a second one.

The trim is the tablet's and the retirement is the room's, and they do not happen at the
same moment: the row is trimmed when the team keeps the recording, and the stretches are
retired when the upload lands. A reading of the session that reaches the tablet inside
that window brings the replaced part's stretches back, addressed to a recording the
tablet no longer holds — a stretch of no part. The way out is the halt above: a pointer
at one of them has no part to record again and calls for a person.

The replaced file stays on the tablet. Nothing points at it, and deleting audio a team
recorded is not a thing this room does quietly.

Leaving the passage says nothing to the room. A release refused at the resting screen
calls for a person and now has a way out, so a team can walk out of a **Halt** the
**Desk** is still being shown — a stopped room with nobody in it. That is the price of
the way out, and it is written here because this decision is what makes it reachable.
