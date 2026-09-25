---
status: accepted
date: 2026-09-25
amends: 0029
---

# A lift replays what was sounding, and a halt silences every station

This amends ADR 0029 without editing it: 0029's latch, `_entradaParouSemTocar`, is retired
below, and the rule it stated — a halt met on the way in withholds the sound and nothing
else — is folded into the broader one this record states instead.

## Context

ADR 0029 gave the back-translation's entry a latch: a halt met on the way in, before a
part had ever gone in the air, was remembered and the part played once the halt lifted.
Every other halt inside the retro — one that caught a part already sounding, a bead replay
from the row, or the room mid-capture — was lifted with no play at all, the way ADR 0029's
own considered options describe as rejected. The room stood in the retro with a drawn cord
and no clip in it, and every gesture that needed one passed its guards over silence.

Fixing that with one rule — every lift inside the retro replays the part, whenever the halt
caught something sounding — reached the scissors and a confirm still in flight. A team that
had cut, recorded a translation and left it pending, halted while listening back to that
translation, then lifted, found the cut wiped and the pending translation sent as a stretch
of no length: `_tocarParteDaRetro` re-cursors and re-cuts unconditionally, which is right
for the part ADR 0029 already covers and wrong for a cut, a pending translation or a retell
already armed — work already in progress that a bead-like sounding (hearing the cut
stretch, or the pending translation) must not make a lift discard.

`_haltForAPerson` also only ever silenced the retro's own capture. A halt landing while the
Guide read a line, or while the rehearsal played straight through, left that sound running
under a room already asking for a person — the same defect ADR 0024 named for a gesture
that moves the room, now true of a halt too.

A separate defect surfaced in the same pass: the guard behind "has anything been heard
since the cursor" — read by the scissors, the capture and the circle's label — first read a
live player position at every use, which never rebuilds the label on its own; moving that
question to a state fact set on a background poll then let the fact answer from whichever
clip's position happened to be current when the poll last ran, including a clip that had
already closed. Both the poll (a self-rearming timer that outlived any test landing a part
it never crossed the cursor of) and the stale read it produced are retired below too.

## Considered Options

**Keep the latch, widen it by hand to the new cases.** Rejected: a latch has to be set at
every place that could leave a part not sounding — held by a pause, ended, mid-capture, a
bead read from the row — and missing one silently reopens the old bug. The plan file
already carried this cost once, in the `_entradaParouSemTocar` flag this decision retires.

**Re-cursor and re-cut on every lift, and let the team re-cut by hand if a halt caught them
mid-cut.** Rejected: the team's own cut and their own recorded, pending translation are
theirs; a halt is not a gesture that moves the room in ADR 0024's sense, and undoing work
nobody asked to undo is not a room "exactly as it stood."

**Read "heard since the cursor" from a state fact everywhere, including the scissors and
the capture, kept current by a periodic poll.** Rejected on two counts, both measured. A
poll that only stops once it crosses the cursor left a timer running for the life of the
session on any part landed and never listened past — moved to the circle widget instead of
the notifier, that same timer just moved to outliving the widget's own test instead, one
layer up. And a poll armed at landing, before the new clip's own `openings` event, read the
*previous* clip's position: crossing from a part with a told cursor of 12s into a fresh
part at nought answered "already heard" with the head still sitting on the old part's tail.

## Decision

**A lift replays only what the halt actually caught sounding, and never re-cursors or
touches the cut when a cut, a pending translation or a retell is already the team's own
work in progress — even if that halt caught the team listening to the very thing it
named.** What "caught sounding" means is read once, in `_haltForAPerson`, before
`_silenceTheRoom` clears every flag that would answer the question afterwards: a part in
the air, a bead replay from the row, or a part the entry had chosen but never landed (ADR
0029's case, folded into this same read rather than kept as its own latch). A part a hold
left silent, or one already at its end, is not sounding by this reading either. `_leaveTheHalt`
only calls `_tocarParteDaRetro` when that reading holds *and* nothing is cut, pending or
armed for a retell — the second half of the guard is unconditional on top of the first, not
folded into it, because the team's own work in progress is never touched regardless of what
was sounding. Henok, 25-09.

**`_haltForAPerson` silences the room first, unconditionally, in every station.** The one
line every gesture that moves the room already passes through (ADR 0024) now also opens the
halt: the Guide's voice, a bead or a stretch replay, and the rehearsal itself all stop
before the halt is read, not only the retro's own capture.

**"Heard since the cursor" is a state fact for the circle's label alone; the scissors and
the capture keep reading the live head, as they always did.** The fact is written by a
one-shot deadline armed once, from the position the clip's own `openings` event reports —
never a stale one left over from whatever played before it — and cancelled and re-armed
wherever the head stops or resumes moving (`_holdClip`, `_letTheClipRun`), so a paused head
never fires a deadline it can no longer be honest about. The deadline lives in the
notifier, next to the state it writes, and needs no widget of its own to own a timer: armed
once per landing or per hold/resume, it never re-arms itself the way the retired poll did,
so nothing here outlives a test that lands a part and moves on.

## Consequences

`_entradaParouSemTocar` is gone; the reading above subsumes the case it existed for, so a
halt met before a part ever sounds and one that catches it mid-play are the same question
now, not two.

A confirm or a correction still in flight when a halt lands reads its own `_trechoStart`/
`_trechoEnd` no differently for having been interrupted: neither is touched, because the
lift's resume is refused outright whenever a translation is pending or a stretch is armed
for a retell — regardless of whether the halt also caught that pending translation or that
stretch sounding.

The label can, for one instant, answer "listen first" a moment after the head has actually
passed the cursor — the deadline is armed from a position read once, at the clip's own
`openings`, and does not itself track continuous real-time drift the way a poll would. The
scissors and the capture do not share this imprecision: reading the live head at the moment
of the gesture, they are exact where the label is only current.
