---
status: accepted
date: 2026-10-30
amends: 0162
---

# A nudged pause takes the held player with it, and «manter» keeps it there

This amends ADR 0162 without editing its decision: it adds "amended by 0167" to its status line.
Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket
(ENG-2098).

## Context

ADR 0162 kept the player's line on a paused take where the team stopped, and left one
difference as a follow-up: after «um pouco antes / um pouco depois» the line stayed at the point
heard to while the pause walked away from it. Her nudge seeks the paused chain to the moved cut
(`Drafting.tsx:1377-1379`), so the line jumps onto the pending pause and play goes on from it;
and «manter a tradução de antes» only pauses the chain (`:1364`), so the player stays on the
moved cut and play resumes from there (`:1408`). Ours held the part where the take had stopped
and silenced the room outright on «manter», losing the held part with it.

## Decision

**A nudge rebuilds the held part at the moved pause, and «manter a tradução de antes» holds the
clip instead of silencing it.** The held part is the same part and file, from the pause, not
started: the strip's line sits on the pause, «ouvir a pausa» still plays the moment before it and
hands the held part back at the pause, and the next «Ouvir» after «manter» plays the take on from
the moved pause. What was heard to is not moved by a nudge.

## Consequences

The line follows the pause as hers does, so the team sees the pause and the player as one place
while they adjust it. «Ouvir» while a pause stands still replays the pending stretch, and during
a retell still replays the retold frase, as before this change; her play that drops the pending
cut and goes on from it stays a recorded difference, not this decision.
