---
status: accepted
date: 2026-09-25
---

# A lift replays what was sounding, and a halt silences every station

## Context

ADR 0029 gave the back-translation's entry a latch: a halt met on the way in, before a
part had ever gone in the air, was remembered and the part played once the halt lifted.
Every other halt inside the retro — one that caught a part already sounding, a bead replay
from the row, or the room mid-capture — was lifted with no play at all, the way ADR 0029's
own considered options describe as rejected. The room stood in the retro with a drawn cord
and no clip in it, and every gesture that needed one passed its guards over silence.

Fixing that with one rule — every lift inside the retro replays the part — reached the
scissors and a confirm still in flight. A team that had cut, recorded a translation and
left it pending, halted and lifted, found the cut wiped and the pending translation sent as
a stretch of no length: the lift's own `_tocarParteDaRetro` re-cursors and re-cuts
unconditionally, which is right for the part ADR 0029 already covers and wrong for one
already telling something back.

`_haltForAPerson` also only ever silenced the retro's own capture. A halt landing while the
Guide read a line, or while the rehearsal played straight through, left that sound running
under a room already asking for a person — the same defect ADR 0024 named for a gesture
that moves the room, now true of a halt too.

## Considered Options

**Keep the latch, widen it by hand to the new cases.** Rejected: a latch has to be set at
every place that could leave a part not sounding — held by a pause, ended, mid-capture, a
bead read from the row — and missing one silently reopens the old bug. The plan file
already carried this cost once, in the `_entradaParouSemTocar` flag this decision retires.

**Re-cursor and re-cut on every lift, and let the team re-cut by hand if a halt caught them
mid-cut.** Rejected: the team's own cut and their own recorded, pending translation are
theirs; a halt is not a gesture that moves the room in ADR 0024's sense, and undoing work
nobody asked to undo is not a room "exactly as it stood."

## Decision

**A lift replays only what the halt actually caught sounding, and never re-cursors or
touches the cut otherwise.** Read once, in `_haltForAPerson`, before `_silenceTheRoom`
clears every flag that would answer the question afterwards: a part in the air, a bead
replay from the row, or a part the entry had chosen but never landed (ADR 0029's case,
folded into this same read rather than kept as its own latch). A part a hold left silent,
or one already at its end, is not sounding by this reading, and the lift gives the room
back exactly as it stood — silent, the pause or the end kept, the cursor and any pending
cut or translation untouched. Henok, 25-09.

**`_haltForAPerson` silences the room first, unconditionally, in every station.** The one
line every gesture that moves the room already passes through (ADR 0024) now also opens the
halt: the Guide's voice, a bead or a stretch replay, and the rehearsal itself all stop
before the halt is read, not only the retro's own capture.

## Consequences

`_entradaParouSemTocar` is gone; the read above subsumes the case it existed for, so a halt
met before a part ever sounds and one that catches it mid-play are the same question now,
not two.

The cut's own guard — `cabeca` cannot sit behind the cursor — is read from a plain state
fact instead of a live one, so the scissors, the capture and the circle's label share one
answer the way `canCut` and `canConfirmTranslation` already do; a gesture that needs the
answer fresh (the scissors, opening a capture) asks for it again itself rather than waiting
on whatever last set it, and the circle owns its own timer to ask it again on a cadence of
its own — in the notifier the answer would outlive a test that never crosses the cursor,
the same shape ADR 0028's reading head already avoids by living in the widget.

A confirm or a correction still in flight when a halt lands reads its own `_trechoStart`/
`_trechoEnd` no differently for having been interrupted: neither is touched unless the lift
also replays the part, which by the decision above it does not while a translation is
pending or a stretch is armed for a retell.
