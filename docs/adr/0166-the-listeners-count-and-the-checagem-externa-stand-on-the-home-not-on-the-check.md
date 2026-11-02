---
status: accepted
date: 2026-10-29
amends: 0113 (in part: the Back-translation no longer shows the listeners' count or «Checagem externa»), 0114 (in part: the Station is reached from the recording home, not from the Back-translation)
---

# The listeners' count and «Checagem externa» stand on the recording home, not on the check

This amends ADR 0113 and ADR 0114 without editing their decisions: it adds "amended by 0166"
to their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October).
Settled on the ticket (ENG-2052, trimmed on 29 October to this one point).

## Context

ADR 0113 drew, under the approval on the Back-translation of an approved draft, the outside
listeners' count and the «Checagem externa» button, and ADR 0114 made that button the one tap
that opens the Station. ADR 0136 then drew both on the recording home as well, so the check
and the home each offered the door. Her tell step (`Drafting.tsx:2462-2471`) has neither: the
`ext-badge` and the `ext-enter` are drawn once, on the recording home (`:2549-2552`).

## Decision

**The check draws neither the listeners' count nor «Checagem externa».** At conferida with an
approved release the check keeps its badge and nothing else of the external check; the count
and the button stand on the recording home only, where ADR 0136 put them, with the words ADR
0014 lists. While the approval line still plays on the check, no «Checagem externa» stands
there either.

The notifier's open and the machine's transitions are untouched: `abrirAChecagemExterna` still
accepts a draft drawn on the check, and the Station still answers an arrival from the
Back-translation and leaves back to it (ADR 0114, ADR 0116). No tap reaches those paths any
more; retiring them is a lifecycle change through the machine, left to its own decision.

## Consequences

- «While the open is in the air no other Back-translation gesture acts» (ADR 0114) has no door
  left; its tests went with the button. The home's own rule stands (a Scene row does not record
  while the external check is opening).
- A refused open (`DRAFT_NOT_APPROVED`) used to write «a checagem externa abre depois que o
  rascunho final é aprovado» on the check's status line and nothing on the home. With the door
  off the check, the home draws that same word (`externalCheckNotFinal`) in place of the
  open-failed line, beside its reading of the session that takes the badge and the button away,
  as her home says `extNotFinal` on a 409. The Checagem externa stays paused (26 October):
  nothing else is built there.
