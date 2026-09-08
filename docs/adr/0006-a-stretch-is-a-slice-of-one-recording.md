# A stretch is a slice of one recording

## Context

The **Back-translation** plays the **Rehearsal** end to end, and the team tells it back
piece by piece. Each piece has to be addressable later, because a **Mend** replaces one of
them without touching its neighbours.

## Considered Options

Addressing a **Stretch** as a position on the concatenated **Passage**. Rejected because
every mend that changes a length would shift every stretch after it.

## Decision

A **Stretch** names one **Take** and a start and an end inside that file, never a position
on the concatenated **Passage**. Times relative to a file that never changes never shift.

## Consequences

One **Stretch** can be corrected without moving the ones after it, which is what makes the
**Mend** a local act at all. The concatenated view still exists, but only as a drawing
transform applied when the **Necklace** is painted; nothing stores it. What the room reports
as heard, and the length it measures a clip against, remain the **Rehearsal** end to end.
