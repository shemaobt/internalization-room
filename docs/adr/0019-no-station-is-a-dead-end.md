---
status: accepted, amended by 0107, amended by ENG-1899 (2026-10-30: the Choice's way out)
---

# No station of the room is a dead end

## Context

The **Team** cannot read, so a screen with no way onward cannot be explained away by a
label. A station that traps the team ends the session, and nothing on the screen would say
why.

## Considered Options

Deriving the check from the routing code itself. Rejected: it proves only that the code
equals itself, and it would pass a station whose exit was wrong.

## Decision

Every station has a way out, and a test asserts it by walking the stations rather than by
listing them. The table of exits names both the gesture and what it leads to, written down
by hand, and the test first asserts that the table covers every station that exists.

## Consequences

A station added later is covered without anyone remembering to cover it: the set assertion
fails before the walk can silently skip it. The **Closing** is included — it is not where
the team stays, and the **Wheel** reopens on its own after a pause, or at once on a touch
anywhere.

Amended by ENG-1899 (2026-10-30): the Choice. While the Wheel is unread or failed, the Choice
draws the mark and its title over an empty list and no circle, as hers does. The Choice then
has no gesture of its own: "no dead end" holds there through the next open of the Choice by
the notifier (`abrirEscolha`, which reads the Wheel again), not through anything the team
touches on the Choice. João accepted on the ticket that removing the circle removes its
retry, because her Choice has none. The table of exits keeps the Choice's exit on a listed
Wheel, the tap on an entry.
