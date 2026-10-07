---
status: accepted
date: 2026-10-06
amends: 0012 (the Decision's "rotated" clause)
---

# The acknowledgement is one of her three at random, and never before an opening

This amends ADR 0012 without editing its text; it replaces the clause in its Decision that
the line is "rotated so it never repeats twice running"; the rest of 0012 stands. The
Orchestrator settled it on 6 October (ENG-1448).

## Context

The room played four acknowledgements in a fixed rotation, and again from the first at every
new passage. Marcia's app has three, picks among them at random, never repeats the one said
last, and keeps that memory for the life of the page. The room also played an acknowledgement
before a re-asked opening, a wait nobody had spoken into.

## Decision

The **Instant acknowledgement** is one of three fixed lines, F0, F1 and F2. The next one is
`(last + 1 + random(2)) mod 3`, her formula, so it is never the one said last. The last one
said lives as long as the notifier and is not reset by a new passage.

No acknowledgement is played before an opening: not the scene, the panorama or the
invitation's, and not an opening the room asks for again. A team turn keeps its
acknowledgement.

## Consequences

The fourth line, «Tá.» / «Right.», leaves the list but its clips stay in the bundle until
ENG-1458 re-renders them.

Amended by ENG-1268 (where the clips are): none of her lines ships in the bundle any more,
so the fourth line's clips are not in it either, and there is nothing in the bundle for
ENG-1458 to re-render here.
