---
status: accepted
date: 2026-09-25
---

# A warning is a mark beside the circle, never its colour

## Context

ADR 0040 made the circle's colour the voice — telha for the Guide, wood for the mother
tongue, azul for the bridge language — and kept green for the verdict alone. Before that
ADR, and still through ADR 0032 (the tablet is silent over a warning), a warning had drawn
the circle green: the room's only way to say "someone should come watch" was to borrow the
verdict's own colour, over whatever voice was sounding. A warning that landed while a
recording played turned wood or azul into green mid-turn, and the team lost the one signal
that said which language the room was hearing.

ADR 0032 kept that green as its premise — the tablet still called nobody, only the colour
carried the news — but the colour itself was never examined: green was already how a
warning showed itself by the time 0032 was written, and 0040 shipped without saying whether
it still applied.

## Considered Options

**Keep the green, but only outside the voices that need their colour read** (listening,
speaking). Rejected: a rule with exceptions is a rule the next station gets wrong, and the
room already has one clean rule for the disc — colour is the voice, no exceptions.

**Speak the warning.** Rejected by ADR 0014 (the room is wordless) and ADR 0032 itself: a
warning refuses the team nothing, and a spoken line would read as a halt.

**A mark beside the circle.** Chosen.

## Decision

**The disc's colour is the voice, full stop — a warning never draws over it, in any
voice.** A warning shows as a small mark beside the circle instead, present only while
`warning` holds and the voice is not already one of the halted states (a stop that has
already told the team to wait outranks a warning, as it did before). The mark carries its
own VoiceOver label, since the room has no text on screen (ADR 0032's own constraint: what
"beside" can be is visual, not spoken). It reuses the verde already spent on "someone should
come and look" — the same colour, now a mark instead of the whole disc.

The thinking state keeps drawing the dimmed clay disc it always drew, breathing, with no
turning or standing arcs any more (Henok, 2026-09-25, reversing PR #230): the arcs said
nothing the breath and the glow did not already say, and cost the wait a fast redraw clock
for it.

## Consequences

ADR 0040's rule now has no exception left: the disc is always the voice. ADR 0032's
Decision is unchanged — the tablet still calls nobody over a warning — only its premise
("the only way to show a warning is the colour") is corrected: the mark is the way, and it
does not require the whole disc.

`ArcPainter` and the `turning` parameter go with the arcs; nothing else read them.

`CONTEXT.md`'s Circle and Warning entries did not name the green, so neither needed a
clause changed. A new entry, Warning mark, names the mark itself.
