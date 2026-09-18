# The cord is measured on entry, and the reading head has two drivers

## Context

Three things the team does around a **Part** recorded again had no answer on the screen.

The part the team came back to record was a private count in the notifier, written by the
grid's gesture and read once by the keep. The **Rehearsal** screen never saw it: every
**Bead** of the row was drawn alike and the record circle carried the label of a part being
recorded for the first time. In a room with no words (ADR 0014) that is the whole of what
the screen had to say, and it said the wrong thing — the team was told a part was about to
be added to the end of the rehearsal while it was in fact replacing one.

Entering the **Back-translation** threw the **Ruler** away and rebuilt it as a side effect
of deciding which part to put in the air. That decision walks the parts in order and stops
at the first one with no told ground — which, after a part is recorded again, is that very
part (ADR 0020 leaves its ground bare). The **Cord** cannot place a **Band** of a part
beyond the ruler's end, so every band of every later part vanished until the replaced part
had played through to its end. The team came back to a cord that had forgotten the work it
had already done.

The reading head — the dot the cord draws where the team is listening — was a stored
millisecond, and the follower that walks it ran only while a part of the rehearsal was in
the air. Playing a **Stretch**'s mother tongue from *Where the error lives* moved nothing,
so the team heard a stretch with no way to see which stretch it was.

## Considered Options

**Mirroring the part being recorded again from the private count into the state.**
Rejected: two copies of one fact drift, and the one the screen reads would be the one
nobody updates. The count has a single home now.

**Growing the ruler only as parts end, and teaching the cord to place a band past the
ruler's end.** Rejected: it moves the guess into the drawing. A band placed against a part
of unknown length is drawn somewhere the sound is not, and the cord's rule — a part nobody
can measure ends the cord rather than lengthening it by a guess — exists because that was
tried.

**Drawing a drained band over the replaced part.** Rejected: ADR 0011 gives a drained band
one meaning, *waiting to be mended*, and this ground is waiting to be told. Absence is the
truth here, and ADR 0020 already said so.

**Parking the head at the stretch's end, or at the cord's end, while a stretch plays.**
Rejected with Henok on 2026-09-18: a head that jumps and then stands still says the stretch
was heard before it has been. It travels.

**Putting the head in the session state.** Rejected: it moves ten times a second and only
one layer draws it, and the room watches the session from everywhere.

## Decision

**The part being recorded again is a fact of the session.** `SalaSessionState` carries it,
0-based like the code's own row index and named `parte + 1` wherever a person hears it. The
rehearsal screen draws that part's bead apart from the others — matched by scope, never by
where it sits in the row, because a correction kept in the same rehearsal sits in the row
too — and the record circle's idle label names it. The keep spends it, and every gesture
that moves the room out of the rehearsal releases it.

**The cord is measured on entry to the back-translation.** Entering measures every part
the player can measure, publishes the whole ruler, and only then chooses which part goes in
the air. The choice keeps its two other jobs and loses the measuring: it still steps over
the parts told whole, still writes those and only those into the **Listening ledger**, and
still stops at the first part with no told ground. **A part measured is not a part heard** —
the ledger is written by listening, and the ruler by measuring, and entering the
back-translation does only the second.

**The reading head has two drivers.** The part of the rehearsal in the air, as before; and
a stretch's mother tongue played from the grid, where the head is the stretch's place plus
the clip's own position, clamped to that place. The clip counts from its own start, so the
place is what carries it onto the cord — the same place the band is drawn at (ADR 0021).
When the clip ends, or the team holds it, the head is the told ground again. Hearing the
telling in the bridge language moves nothing: it is a recording that lives nowhere on the
rehearsal. Playing a stretch never writes the told ground, so the **Cursor** of a resumed
back-translation does not move because somebody listened.

## Consequences

The first clip of the back-translation now starts behind the measuring rather than in the
same call that asked for it. The room stands in its thinking state across that wait, which
is the honest answer for a tablet that is busy, and the gestures that wait on it were
already written for a wait that could happen — it happened whenever anything had been told
back. What is new is that it happens every time.

Leaving that wait returns the room to the invitation **only if it is still thinking**. A
halt raised while the player was measuring is the room's state by then, and the invitation
put back over it let a team reopening into a room the server had already stopped straight
back in, against ADR 0009 and the **Halt** the glossary defines. That path was reachable
before this decision and was taken whenever the measuring happened to wait; making the wait
unconditional made it the ordinary case, and the desk's own test is the witness for it.

Measuring on entry asks the player for every part each time the team enters the
back-translation, where it used to ask only about the parts it stepped over. A part the
player cannot measure still ends the ruler rather than lengthening it, and still does not
stop the team.

The head is now asked for its value while a stretch plays as well as while a part does, so
there is a second way for the cord's ten-times-a-second timer to be left standing when the
screen goes. It is cancelled before it is armed and again when the layer is disposed, and
the suite keeps a case for each of the two doors.
