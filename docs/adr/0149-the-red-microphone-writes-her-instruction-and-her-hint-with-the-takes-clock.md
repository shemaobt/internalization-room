---
status: accepted
date: 2026-10-28
amends: 0131 (the red microphone's take state)
---

# The red microphone writes her instruction and her hint, with the take's clock

This amends ADR 0131 without editing its decision; it adds "amended by 0149" to its status
line. João's rule of 26 October settles it: Marcia's app at 18fa7c4 wins over our ADRs and
tickets (ENG-1834).

## Context

On the scene rehearsal's record step her app writes, under the title, «Toquem no círculo
para gravar o ensaio da cena; toquem de novo para parar.», and under the circle one line,
her hint: «gravem o ensaio da cena na língua materna; toquem para parar» at rest, «gravando
· m:ss» with the take's clock while it records, and «guardando o ensaio da cena…» while the
take is being kept (`Rehearsal.tsx:838-857`, `app/lib/strings.ts:353-362`). Ours wrote only
the take's state: «gravando» with no clock, and «enviando…» while the take was kept, which
is not hers; the instruction and the hint reached the team only through VoiceOver.

## Decision

- Under the title the record step writes her instruction, in pt and en, byte for byte.
- Under the circle it writes her hint: at rest, also beside a failed take, as hers does;
  «gravando · m:ss» while the microphone is open, counted from when it opened, in whole
  seconds; «guardando o ensaio da cena…» while the take is being kept, in place of
  «enviando…». While the stop tap waits on the recorder the line still reads «gravando»,
  as hers does until her recorder answers.
- Neither line is written while the team is asked which scene, as hers.
- What ADR 0131 adds to her screen stays: «parar» after 8 s of sending, her failure words and
  «falhou — toque para tentar de novo» as the tap. The circle's VoiceOver names do not change
  here (ENG-1918).
- The hint is written for the eye only. Under the circle VoiceOver hears only the circle's
  name: «Gravar o ensaio da cena» at rest, the hint's words while the team records, and
  «guardando o ensaio da cena…» while the take is kept. Nothing is read twice, and the clock
  does not rewrite a VoiceOver label every second. Her hint is announced (`aria-live`)
  because her circle is named «Parar» and «Gravar o ensaio da cena» instead; once ENG-1918
  names ours as hers, the hint is what VoiceOver should read.

## Consequences

«enviando…» no longer appears on the red microphone; it stays on the Retro's re-recorded
sentence and on the Ensaio rows. The record step scrolls when it does not fit, as her screen
does.
