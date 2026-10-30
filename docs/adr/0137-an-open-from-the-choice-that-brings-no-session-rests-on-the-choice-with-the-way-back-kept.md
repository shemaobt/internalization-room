---
status: accepted, amended by 0143, 0145, ENG-1979
date: 2026-10-27
amends: 0108 (in part: a way in from the Choice rests on the Choice, not at the invite), 0062 (in part: the way back lasts until the next entry's session opens)
---

# An open from the Choice that brings no session rests on the Choice, with the way back kept

Amended by ENG-1979 (2026-10-30): the third bullet of the Decision. «A thrown error still raises
the sign (ADR 0093)» no longer holds for the Opening of a passage or of the Panorama: a thrown
error while it is voiced is handled like a refusal, as hers is (`app/page.tsx:756-758`). The team
rests in its session at the invite, with no sign and nothing said, and the error goes to the
operator's log. Her catch first calls `recoverTurn`, which says the Opening again if the server
already holds it; ours says nothing even then, a known difference, the ticket's rule wins.

This amends ADR 0108 and ADR 0062 without editing their decisions: it adds "amended by 0137"
to their status lines. Her app is the bar (`app/page.tsx:786`, `choosePassage`): an open that
answers no session leaves her menu where it was, and a re-tap of the same reference asks again;
the Panorama goes through the same open (`:980-981`).

## Decision

- **A passage or Panorama pill whose session the room does not give rests on the Choice.**
  Whatever the failure (no network, a 5xx, a timeout, a refusal), the team is back on the
  Choice with the wheel as it was read, its entries live, nothing said and no sign. The return
  asks the room for nothing, and the next tap on the same pill asks for the session again.
  ADR 0108's «rests at the invite» still holds for every way in that is not a pill: the way
  back, the launch, a tap on a Canvas or Panorama with no session, and the sign cleared.
- **The entry left stays through the open and goes when a session opens.** A failed open,
  refused or not, keeps the chevron to the passage the team left (ADR 0062's «the next entry
  opened» is an entry whose session opened). Hers goes back to the passage's canvas by itself;
  ours waits for the team's tap on the chevron until ENG-1939 keeps the passage left in memory
  under the Choice.
- **A failure once the session is held is unchanged.** The Opening that fails rests in its
  session, as hers rests in hers (`app/page.tsx:746-757`); a thrown error still raises the sign
  (ADR 0093).
