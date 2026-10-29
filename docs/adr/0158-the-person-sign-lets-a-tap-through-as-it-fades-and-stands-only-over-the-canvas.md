---
status: accepted
date: 2026-10-29
amends: 0093, 0107, 0144
---

# The person sign lets a tap through as it fades, and stands only over the canvas

This amends ADRs 0093, 0107 and 0144 without editing their decisions: it adds "amended by 0158"
to their status lines. Marcia's handoff drops its pointer events the moment the phase turns
(`app/globals.css:179` against `:234`, at 18fa7c4); only its opacity eases out, so a click
during the fade reaches her circle beneath. ENG-1971 brings ours to hers. Her frozen app wins
over ADR 0107.

## Decision

1. **From the moment the sign starts to fade, a tap reaches what lies beneath.** A second tap
   on the circle as the sign fades out opens the microphone, as hers. ADR 0107's «a second tap
   as it fades never opens the microphone» and ADR 0144's item 3 no longer hold.
2. **A halt raised on the Scene rehearsal is not drawn there.** It waits for the Canvas, as
   the scene's own given-up turn already did: the sign rises once the team is back on the
   Conversation, and the halt is dropped if they arrive anywhere else first. The scene's screen
   keeps working beneath it, and «terminei» still sends. Hers draws the handoff only on her
   canvas (`app/page.tsx:944-945`, `:1063`), and a failure on her Rehearsal shows there once
   the team is back (`:704`). On the Scene rehearsal such a halt comes only from the build
   guard or an `Error` in a hand-off, and once raised on the Canvas it calls for a person.

## Considered Options

**Keep the fading wash as a wall.** Rejected: it is not hers, and a team that tapped twice saw
its second tap vanish.

**Hide the sign off the canvas and keep the halt standing beneath.** Rejected: the screen would
stop answering with nothing on it saying why.

**Move the team to the Canvas when a halt lands off it.** Rejected: it throws away the screen
the team was on, and hers keeps it.

## Amends

- 0093: «a scene rehearsal given up whose look finds nothing, shown once the team is back on
  the Conversation» now covers any halt raised on the Scene rehearsal.
- 0107: «While any of the wash is on screen, it takes every tap, fading in or out» now reads:
  while the sign rises or stands, it takes every tap; as it fades out, it takes none.
- 0144: item 3 is reversed.
