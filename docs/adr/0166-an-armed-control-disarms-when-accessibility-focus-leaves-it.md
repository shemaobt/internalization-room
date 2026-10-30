---
status: accepted
date: 2026-10-30
amends: 0113 (the Armed tap gains a fourth disarm: focus loss)
---

# An armed control disarms when accessibility focus leaves it

This amends ADR 0113 without editing its decision; it adds "amended by 0166" to its status
line. Her frozen app at Tripod-Internalization 18fa7c4 wins: every armed button drawn by
`armedBtn` carries `onBlur: () => { if (armedId.current === id) disarm(); }`
(`Drafting.tsx:2228`), the sheet's «usar este» carries the same (`EnsaioFinalSheet.tsx:81`),
and the wake-up is `aria-disabled` rather than `disabled` precisely so the button keeps the
focus its blur watches (`:2222-2223`).

## Context

ADR 0113's Armed tap disarmed by itself after six seconds, on another arm, and on any gesture
of the team. A VoiceOver user who armed «regravar a frase 2» over an approved draft, swiped
away to hear the other rows and came back inside six seconds found the control still armed:
one double-tap opened the sentence and the approved draft with it, with no second arm. Her app
reads a swipe away as the team changing its mind.

## Decision

- **Focus leaving the armed control disarms it.** The platform's
  `didLoseAccessibilityFocus` on the armed control clears the arm as the lapse does, whether
  the control has woken or is still asleep. Focus leaving any other control leaves the arm
  alone, and focus that lands and stays keeps it armed until the lapse.
- **The six controls that carry it are hers:** on the check «regravar a frase N» and the held
  sentence's «tentar de novo»; on the recording home, the plan and the check
  «gravar a passagem inteira de uma vez»; on the whole home «Ensaio Final: juntar os ensaios
  das cenas»; on a scene row «trazer de volta as traduções do ensaio desta cena»; on the home
  sheet «usar este». The check's «recomeçar a tradução» and the scene rehearsal's keep their own
  arm with no focus disarm, as her `bt-restart` buttons carry no `onBlur`
  (`Drafting.tsx:2457`, `Rehearsal.tsx:925`).
- **The disarm is not a gesture.** It silences nothing, starts nothing and moves no
  generation: her `disarm()` runs apart from `armTap`. The wake and lapse timers keep their
  own guards and are re-keyed by the next arm.

## Consequences

- A VoiceOver user confirms an armed action only with focus still on the control, as in her
  app; a touch user sees no change, since touch moves no accessibility focus.
- A control whose semantics node is replaced while armed would read the platform's focus loss
  as a disarm; the six controls keep their node through the arm, since only their label and
  enabled state change.
