---
status: accepted
date: 2026-11-02
amends: 0169
---

# Play over a standing pause on the check drops it and goes on from it

This amends ADR 0169 without editing its decision: it adds "amended by 0175" to its status
line. Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket
(ENG-2131).

## Context

ADR 0169 moved the held part onto a nudged pause and left one difference as a recorded one:
her play over a pending cut drops the cut and goes on from it. On the check, with a pause
standing and no frase told again, ours replayed the stretch from the cursor up to the pause
and kept the pause, or resumed a stretch paused under it, so the circle's next tap opened the
microphone on a cut the team had just listened past. Her play with a pending cut and no retell
(`Drafting.tsx:1409-1412`) pauses the take while it sounds and otherwise drops the cut, seeks
the take to it and plays on; the next circle tap marks a fresh cut (`:1303-1311`).

## Decision

**Play over a pause standing with no frase told again drops the pause and plays the part on
from where it stood; at the part's end it plays the moment before the pause and keeps it.**
While «ouvir a pausa» sounds, play only pauses it and the pause stays; paused, the next play
drops the pause and goes on from it rather than finishing the moment before. After «um pouco
antes» or «um pouco depois» play goes on from the moved pause and drops it. The circle's next
tap marks a new pause at the head and never opens the microphone on the dropped one. With the
pause within 50 ms of the part's measured length, the scene's own margin (ADR 0172), play
plays the 1.5 s before it with the part held beneath and the pause stays, as the ticket settles
it; her code there drops the cut and her chain, having ended, starts the passage over, which
she avoids in the sibling branch with «ouvir a pausa». A frase told again with its pause on
the move is not this case and keeps ADR 0169: play there still replays the retold frase up to
the moved pause, the retell and the pause stay, and after «manter a tradução de antes» play
goes on from the moved pause.

## Consequences

The team listens past a pause they changed their mind about with one tap, and marks the next
one where they now stop, as on hers. A pause that survived an empty capture, a failed send of
the stretch, a refused restart or a halt is dropped by play the same way. While a told frase is
being heard over a standing pause, play still holds and resumes that frase; hers pauses it and
drops the cut in the same tap. That difference is recorded as a finding, not this decision.
