---
status: accepted, amended by 0149, amended by ENG-1972 (2026-10-28: the one body of the corner buttons is superseded; every way back is her bare chevron), amended by ENG-1994 (2026-10-29: the necklace's bead material is hers), amended by ENG-1900
date: 2026-10-22
amends: 0062
---

# The corner buttons share one body, and the necklace hangs on a thin cord with glowing beads

Amended by ENG-1900 (2026-10-30): the chevron's inert 0.2 applies only where no passage is held; a held passage is never inert. As in her app (`app/page.tsx:408`, `:950-956`), the chevron
shows whenever a passage is held under the Choice, is always live, and its tap lays the passage back with
no call to the room. Nothing else here changes.

Amended by ENG-1972 (2026-10-28): the «one body» decision is superseded. ENG-1844 draws the
≡, the replay and the passage's chevron as Marcia's bare glyphs, and every way back is her
bare chevron, `M15 5l-7 7 7 7` at stroke 1.6 in verde-claro, as her `.draft-close` (the
passage's and the rehearsal sheet's take it once ENG-1844 and ENG-1959 land). The bullet that
gave the three a 44 px disc is gone; its last sentence, the chevron's inert 0.2, stays as
its own bullet.

Amended by ENG-1994 (2026-10-29): the bead material is superseded, her frozen app 18fa7c4
(`app/globals.css`) winning over this ADR. A bead at rest is `areia` at .55; a filled one is
`verde-claro` at .92, with no gradient and no glow. The last filled bead, the growing edge,
scales 1.1, and a bead just filled scales 1.2 for the 1.3 s it settles. Nothing of this ADR's
necklace stands: ADR 0149 already replaced the cord and the 16 px beads with her 9 px row.

This amends ADR 0062's "faint at rest" without editing it; it adds "amended by 0130" to its
status line. Settled on the ticket (ENG-1536), from Henok's prototype choice of 9 October
(variant B's button, variant C's cord).

## Context

The ≡ and the chevron were a bare grey glyph at half opacity, and the hear-again button a
transparent circle around its glyph. They read as three unrelated marks. The necklace's cord
was heavy and its beads, lit or not, looked the same weight.

## Decision

- **The chevron's inert state keeps its own 0.2.** While the way back to the passage is
  offered but not live, it draws at 0.2 and takes no touch.
- **The hand keeps its own body.** It is a primary control with states (note mode, a reply
  waiting) that the light disc does not have.
- **The necklace's cord is 1.5 px in `line`, its beads are 16 px, and a lit bead glows.**
  Superseded by ADR 0149 (cord and sizes) and ENG-1994 (bead material).

## Consequences

The hear-again gains a disc and a shadow it never had. ADR 0040's "Bead row replaces the
cord" is about the Rehearsal's and the Back-translation's rows and is not touched.
