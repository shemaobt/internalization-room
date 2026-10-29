---
status: accepted
date: 2026-10-29
amends: 0026 (the mark has no gesture that sets it on the check), 0040 (in part: the wood button of a finding), 0045 (the resume row carries no mark from the check)
---

# The way back to record a part stands through the tell step and marks no part

This amends ADR 0026, ADR 0040 and ADR 0045 without editing their decisions: it adds "amended by
0158" to their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October).
Settled on the ticket (ENG-1875).

## Context

Our «voltar e regravar uma parte» was drawn only after a verdict, lit only when a finding named a
stretch, and its tap marked that finding's part on the recording home (ADR 0026), wrote the mark into
the resume row (ADR 0045), dimmed every other row and kept the advance disc dark. Before any verdict
the check had no written way back at all.

- `Drafting.tsx:2465-2470`: her button sits inside the tell step, which is the whole of the telling
  after the first listen (`btStep` is only `listen` or `tell`, :256), so it stands before and after
  any verdict, a clean one too. It rests only while `btAct` is not idle or `voice`, while a «regravar a
  frase N» flow is open, or while a splice resumes.
- `Drafting.tsx:1118-1131`: her `exitBt` stops every sound, drops the open retell and returns to the
  recording home with nothing marked; the home is read again from the room. Her corner way back calls
  the same `exitBt` (:2387).

## Decision

- **The button stands on the whole tell step**, under «terminei», and never on the first listen.
- **It rests only while** a retelling is recorded or sent, the room checks the telling, the room's
  answer sounds (her `speaking`, first play or again), a sentence is recorded again, or an approval is
  in the air (her `approve` sets `checking`). A fixed line of the room (her `voice`) leaves it lit.
- **Its tap is the corner's way back** (`leaveTheBackTranslation`, ADR 0139): every sound stops, the
  open retell is let go, and the team lands on the home with no part marked and nothing said. The way
  back also lets go of the parts the room no longer has, as the button did before.
- **ADR 0026**: the check no longer marks a part. The mark, the home's dimmed rows and the circle's
  «Gravar de novo» stay in the code for a row written before this, and nothing on the check sets them.
- **ADR 0040**: the wood button of a finding is no longer a choice of voice that opens a mend on the
  Rehearsal, and it is never dimmed for a finding without a stretch.
- **ADR 0045**: the resume row written by this way back carries no part. A row written before this
  with a part still restores it.

## Consequences

- To record a part again the team taps that part's row on the home, as on hers.
- The corner way back now also lets go of the open retell and of the parts the room lost.
- `gravarAParteDeNovo` and the mark it sets have no caller on the screen; removing them, and the
  resume row's field, is a follow-up.
