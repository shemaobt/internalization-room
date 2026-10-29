---
status: accepted
date: 2026-10-29
amends: 0026 (the mark is gone), 0045 (the resume row carries no part), 0158 (a row written before it no longer restores its part)
---

# The mark to record a part again and its resume field are gone

This amends ADR 0026, ADR 0045 and ADR 0158 without editing their decisions: it adds "amended
by 0160" to their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October).
Settled on the ticket (ENG-2035).

## Context

ADR 0158 took the way back to record a part off the finding and left the mark behind: «the
mark, the home's dimmed rows and the circle's «Gravar de novo» stay in the code for a row
written before this», and «a row written before this with a part still restores it». Nothing
on the screen has set the mark since, so the only way it still reached the team was a resume
row written before ADR 0158, which reopened the home with one part chosen, the other rows
dimmed, the circle recording over a full scene and the advance disc dark.

- `Drafting.tsx:1118-1131`: her `exitBt` returns to the recording home with nothing marked.
- `Drafting.tsx:2391-2396`: her check has no bead row, so no tap of hers plays a told stretch
  out of the recording while it has a translation.
- `globals.css:374-385`: her check circle keys only on `data-state`; a disabled one only
  changes the cursor.

## Decision

- **The mark is gone**: `gravarAParteDeNovo`, `parteARegravar`, the home's dimmed rows and the
  circle's «Gravar de novo» for a marked part. The circle records the first scene with no part,
  and every row applies.
- **The resume row carries no part.** `ResumePoint.partBeingRecordedAgain` is gone; a row that
  still carries `part_being_recorded_again` is read without it and lands on the plain home.
- **The bead verbs are gone**: `ouvirAConta` and `ouvirOTrechoPendente`. A told stretch is heard
  through its row's play, which plays its translation when it has one.
- **The circle takes no tongue and no touch** it does not draw: `FacilitatorCircle.tongue`,
  `.answersATouch` and the `Tongue` enum are gone.

## Consequences

- To record a part again the team taps that part's row on the home, as on hers (ADR 0158).
- A part past the last scene can no longer be recorded again: only the mark reached it.
- ADR 0026 and ADR 0045 describe a mark and a field that no longer exist.
