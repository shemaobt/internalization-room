# The tablet is silent over a warning

## Context

The retells budget raises a **Warning**, never a cap (ADR 0010): the room asks for someone
to come and watch, refuses the team nothing, and the circle turns green. The server marks
the session's halt as a warning inside the very transaction that counts the crossing, so
the room has already called by the time the tablet hears about it.

The answer to a **Short way** carried the same news as an ordinary telling — one field
saying a person is needed — and the tablet read it differently on the two routes. Off a
stretch told back it wrote the warning; off a correction it raised a blocking **Halt**: the
E0 line, the circle stopped, the room waiting for the **Desk**. A team that crossed the
mark by mending a stretch was shut out of the station it was working in, over a note
nobody had read yet.

## Considered Options

**The tablet calling a person over a warning.** Rejected. The room already called: the
server marks the halt as a warning in the transaction that counts the crossing, and the
**Desk** queues it from there. Worse, the tablet's own ask marks a halt *blocking*, so
calling from here would turn the room's warning into the stop the rule forbids.

**Keeping the halt, but only after the verdict.** Rejected by the glossary: a warning is
the kind of halt that refuses the team nothing, and a stop that arrives a moment later is
still the stop. The ordering this defended existed only because a halt walks the voice;
a warning is a field, and nothing writes over it.

## Decision

**Over a warning the tablet calls nobody.** Both readers of a correction's answer write
the warning on the session and do nothing else: the room stays in the phase the same
correction without the field leaves it in, the microphone keeps opening, no E0 line is
spoken, and nothing waits for the Desk. A blocking halt still comes from a state read, and
only the Desk lifts it (ADR 0009).

## Consequences

A warning is now raised on exactly two routes — a state read and a correction's answer —
and the chunk route's retelling plumbing goes with this decision: the tablet never sent
`retelling`, so the room never answered a chunk with that field, and the two warning
writes on that path read something that could not arrive. The field itself goes with
them — a chunk from this tablet counts one telling, which is under the mark, so the
answer cannot carry the news at all.

The team crossing the mark by mending stretches sees a green circle and goes on mending.
The facilitator's queue shows the room asking for someone as a warning, which is what the
server had recorded all along.
