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
