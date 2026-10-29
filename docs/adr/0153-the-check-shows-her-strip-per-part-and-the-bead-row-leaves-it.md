---
status: accepted
date: 2026-10-27
amends: 0040, 0011
---

# The check shows her strip per part, and the Bead row leaves it

This amends ADR 0040 for the Back-translation and the findings, the one screen where its Bead
row still stood after ADR 0102 took it off the Rehearsal. It adds "amended by 0153" to 0040's
status line and a note to 0011. Nothing else in either is edited. The work is ENG-1882.

## Context

Marcia's rule of 1 October makes her frozen app (18fa7c4) the bar for what the team sees. Her
check draws, for each take of the passage, a row with «parte N» written (or «A passagem
inteira» for a recording of the whole) and a strip of that take: its loudness as a silhouette,
so a silence reads as a valley; each translated frase as a band with a tick at its cut; a frase
of a take recorded again faint and dotted; the player's line; and the pending cut in telha
(`FraseStrip.tsx`, `Drafting.tsx` bt block). The strip cannot be tapped and says nothing to a
screen reader. Ours drew a row of tappable beads with no written part: a tap on a bead played
or reopened its stretch, the current bead wore a ring, the bead a finding pointed at was
drained, and the beads were named only to VoiceOver.

## Decision

**The check shows her strip, one row per part, and the Bead row leaves the check.** Each row
writes «parte N» / «part N», or «A passagem inteira» / «The whole passage» for a whole-passage
take, beside the strip of that part's own take: its loudness read on the tablet from the part's
WAV (ADR 0076), the told stretches as bands with a tick at each cut, the stretches of a part
recorded again faint and dotted, the pending pausa in telha on the part in the air, and the
player's line on the part that sounds. A part not measured yet shows its label alone. The
strip cannot be tapped and carries no words or buttons for VoiceOver: the play control and
the frase rows are the ways to hear and to translate again.

## Consequences

Nothing on the check is a bead any more, so there is no ring, no drained bead and no dimmed
bead there. A finding is marked on its frase row, as hers is, and its stretch is a band like
any told one; ADR 0011's drained bead leaves with the row. Two things only a bead did go
with it, as in her app: hearing the mother tongue of a stretch whose translation is on the
tablet, and stopping a chosen stretch to give the ring back. Every told stretch keeps its
frase row, since the room numbers each one it hands back. The notifier verbs only the beads
called stay until a follow-up removes them with their tests.
