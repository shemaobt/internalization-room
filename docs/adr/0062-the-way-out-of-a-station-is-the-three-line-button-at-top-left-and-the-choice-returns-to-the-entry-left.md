---
status: accepted, amended by 0092, amended by 0130, amended by 0137, amended by 0139, amended by 0142, amended by ENG-1977, amended by ENG-1970, amended by ENG-1900
date: 2026-10-07
amends: 0040 (a button that does not apply is dimmed, never hidden: this button alone)
---

# The way out of a Station is the ≡ at top-left, hidden while it cannot apply, and the Choice returns to the entry left

Amended by ENG-1900 (2026-10-30): the chevron no longer waits for the Wheel to be read, and no longer dims while the voice is busy, when a passage is held (ADR 0143). As in her app (`app/page.tsx:408`, `:950-956`), the chevron
shows whenever a passage is held under the Choice, is always live, and its tap lays the passage back with
no call to the room. Where nothing is held it stays as decided here.

Amended by ENG-1970 (2026-10-30): there is no Closing; the ≡ is on every Station but the Choice, and a finished passage stays on its conversation canvas.

Amended by ENG-1977 (2026-10-30): the Panorama also comes back in silence when its line was cut
before it was heard but the tablet holds the line that began to speak; it offers «Ouvir de novo»
and asks the room nothing, as hers (openOnce.ts:83). The Decision below stands for every other case.

This amends ADR 0040 without editing it; it adds "amended by 0062" to its status line.
Henok decided on 6 October, and the Definer settled it on the ticket (ENG-1461).

## Context

The way out of a passage was a round button with an undo mark, and the Choice had no way
back. A team that left by mistake started the entry again from the Choice.

## Decision

- **The ≡ is on every Station but the Choice and the Closing.** It sits at top-left, faint at
  rest, with no visible text; its label is «Escolher outra passagem». The Closing restarts
  itself and carries none.
- **The Choice carries a chevron at the same spot after a leave,** labelled «Voltar para a
  passagem atual». It shows between a leave in this launch and the next entry opened, and
  waits for the Wheel to be read. A leave always offers the way back to the entry just left.
- **This button is hidden, not dimmed, while it cannot apply.** It is hidden while the voice
  thinks or speaks, while any microphone is open except the raised-hand note's (a tap throws
  the note away), and under the person sign. A turn underway hides it through the voice, not
  through the machine.
- **ADR 0019's exception stands:** at the resting screen of the Back-translation (conferida)
  the ≡ stays live under the person sign.
- **The pause holds a kept take only,** and only while the chevron can return: the take comes
  back paused where it was. A facilitator reply that is playing is stopped, stays unheard,
  and the hand offers it again.
- **The chevron is a return, not a new entry.** The Panorama comes back silent once its line
  was said. A passage comes back through the existing resume, and until ENG-1280 lands that
  resume says the passage's opening again.

## Considered Options

**A true mid-line pause of a facilitator reply.** Rejected for now: it reaches the voice
service's grace and ceiling timers; a ticket of its own.

**Dim the ≡ while it cannot apply, as ADR 0040 says.** Rejected: a dimmed control at the
corner where the hand rests invites the touch that discards a recording.

## Consequences

- The label «Deixar esta passagem e escolher outra» is gone.
- Nothing stored changes; the way back lives in memory and dies with the launch.
