---
status: accepted, amended by 0149
date: 2026-10-22
amends: 0062
---

# The corner buttons share one body, and the necklace hangs on a thin cord with glowing beads

This amends ADR 0062's "faint at rest" without editing it; it adds "amended by 0130" to its
status line. Settled on the ticket (ENG-1536), from Henok's prototype choice of 9 October
(variant B's button, variant C's cord).

## Context

The ≡ and the chevron were a bare grey glyph at half opacity, and the hear-again button a
transparent circle around its glyph. They read as three unrelated marks. The necklace's cord
was heavy and its beads, lit or not, looked the same weight.

## Decision

- **One body draws the three light corner buttons:** the ≡, the chevron and the hear-again.
  A 44 px disc on `elev`, a light shadow, the glyph in `verdeClaro` at 22 px, at full
  opacity at rest. The chevron's inert state keeps its own 0.2.
- **The hand keeps its own body.** It is a primary control with states (note mode, a reply
  waiting) that the light disc does not have.
- **The necklace's cord is 1.5 px in `line`, its beads are 16 px, and a lit bead glows** with
  a 3 px ring of `wood` at 25 % outside its matte shadow. At the Closing the beads stay as
  they hung.

## Consequences

The hear-again gains a disc and a shadow it never had. ADR 0040's "Bead row replaces the
cord" is about the Rehearsal's and the Back-translation's rows and is not touched.
