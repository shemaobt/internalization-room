# The part being recorded again is a fact of the session

## Context

ADR 0020 let a team record a **Part** again in its own place. The part they came back for
was a private count in the notifier: written by the gesture on *Where the error lives*,
read once by the keep, and seen by nothing else.

The **Rehearsal** screen never saw it. Every **Bead** of the row was drawn alike and the
record circle carried the label of a part being recorded for the first time. In a room
with no words (ADR 0014) that is the whole of what the screen has to say, and it said the
wrong thing: the team was told a part was about to be added to the end of the rehearsal
while it was in fact replacing one.

## Considered Options

**Mirroring the private count into the session state.** Rejected: two copies of one fact
drift, and the one the screen reads would be the one nobody updates.

**Marking the bead by where it sits in the row.** Rejected: the row is `keptTakes`, and a
correction kept in the same rehearsal sits in it too, so the nth bead is not the nth part.

**Naming the part in the `recording` label as well.** Rejected: while the microphone is
open what the team needs is the instruction to stop. The ticket asks for the idle label
and that is what changed.

## Decision

**`SalaSessionState` carries the part being recorded again**, 0-based like the code's own
row index and named `parte + 1` wherever a person hears it. The private count is deleted;
there is one source and the screen reads it.

The rehearsal screen draws that part's bead apart from the others, **matched by scope**.
The scope and the number are the same fact said twice, so the session counts them in one
place — the reason `_aParteVoltaAoSeuLugar` already gives for counting them together on
the way out — and the screen asks for the scope rather than deriving it.

The record circle's idle label names the part. The keep spends the mark, and every gesture
that moves the room out of the rehearsal releases it.

## Consequences

The mark survives a discarded take, because discarding is the same recording being made
again, and dies on the keep, because the next recording is a part of its own.

The bead's mark is one boolean on `Bead`, so a widget test finds the marked bead without
reading paint. It overrides the row's opacity and border, which is hidden logic in the
smallest widget the room has; there is one call site, and a second would be the sign to
split it.
