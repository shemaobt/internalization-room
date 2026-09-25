---
status: accepted
date: 2026-09-25
---

# The part being recorded again lives in the Resume point

## Context

ADR 0026 put the part being recorded again on `SalaSessionState`, in memory, released by
every gesture that moves the room out of the Rehearsal. A findings-note review of ENG-1114
(ENG-1138) named the gap that decision left open: the row a passage is resumed from carried
the stage and the kept takes, never the mark. A team back in the Rehearsal to record a part
again, with the app killed before the keep, reopened with no mark at all, and the next
recording they kept landed as a new last part instead of taking the one they came back for.

## Considered Options

**Asking the room for it.** Rejected: the room has no notion of a part "being recorded
again" — it only ever sees a finished take under a number. The fact belongs to the tablet's
own navigation, not to anything the server tracks.

**Deriving it again from the finding that sent the team back.** Rejected: the finding that
opens the way to the Rehearsal is itself read once and not kept anywhere durable. Deriving
the mark from it would only move the same problem: the tablet would still need to remember
which finding it was answering across a kill, and a finding remembered for that purpose is
the mark under another name.

## Decision

**`ResumePoint` carries the part being recorded again**, optional and 0-based like
`SalaSessionState`'s own field, absent from a row written before this. The notifier writes
it whenever it persists the resume row while the mark is set — including right after the
gesture that sets it, so a kill in the moment between marking the part and the team's first
recording still reopens with the mark in place — and restores it into state on landing back
in the Rehearsal.

The row is never asked to carry the mark past the Rehearsal. Every gesture that releases the
mark in memory (ADR 0026) does so before the next write of the row, so a row saved for the
Retro or any later stage never carries a mark to restore — `startRetro` releases it ahead of
writing rather than after, the one ordering the room's other stage-leaving gestures already
had.

This amends the reading of ADR 0026's Consequences that "every gesture that moves the room
out of the rehearsal releases it" as a fact of memory alone. It is now also a fact of the
row: leaving the passage and coming back while the mark still stands brings it back from
disk, which is the resume this ticket asked for, not an exception to the release.

## Consequences

A tablet killed mid-Rehearsal, mid-regrave, reopens exactly where the team left it: the same
part marked, the next kept recording replacing it under its own number and the next pass.

A row written by an app that shipped before this field existed has no key for it and reads
back with no part marked, the same as a fresh row — the field costs nothing to a passage that
never used it.
