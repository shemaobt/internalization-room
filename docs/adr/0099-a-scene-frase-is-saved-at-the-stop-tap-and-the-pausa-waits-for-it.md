---
status: accepted
date: 2026-10-19
amends: 0014
---

# A scene frase is saved at the stop tap, and the pausa waits for it

This amends ADR 0014 without editing its decision: it adds an "Amended by ENG-1348" paragraph,
the eighth named exception, for her words on the scene rehearsal's translate step.

## Context

On Marcia's scene rehearsal (Rehearsal.tsx:483-666 at 18fa7c4) a frase is circle, pausa,
circle to speak, circle to stop: the stop tap posts the frase with its span, and the take going
on is the only acknowledgement. The room's frase door hears each frase in the session language
for a few seconds before it answers, refuses one with no words, and sets aside at once a frase
that names an attempt older than the rehearsal's current one, or none after a restart.

## Decision

- The frase goes to the room at the stop tap, outside the Outbox, and the pausa stays pending
  until the room answers. «terminei» waits while a frase is in the air.
- A frase the room did not keep leaves the pausa where it was, and the next circle tap records
  it again, as on hers (Rehearsal.tsx:541).
- The frase is recorded on its own microphone, as the capture is: compressed, with the room's
  filters off.
- A pausa placed by the take reaching its end never passes the take's length as the room
  measured it.
- Every frase names the rehearsal's current attempt.
- A frase the room may have kept without saying so (a network failure, a 5xx, the
  tablet's timeout, an answer it cannot read) keeps its file and span on the tablet, held
  by its rehearsal. The next tap that would open the microphone sends those same bytes
  again, and the room's same-bytes rule makes them one frase. Only a kept answer or a
  refusal of that frase lets the file go. «gravar de novo» waits while a frase is closing
  or in the air, and a frase whose screen moved on before it was sent is never sent.
- The frase upload follows the scene rehearsal's flow in the session notifier (ADRs
  0085-0089); its move into the machine is that flow's, not this decision's.

## Considered Options

**The Outbox, as the scene take.** Rejected: a frase queued past «terminei» would reach the
voice late, and the screen cannot play on from the frase until the room has kept it.

## Consequences

A frase is lost if the app dies while it is in the air, and the team records it again: the
held file lives as long as the session's notifier. The room
is silent for the seconds the server spends hearing each frase.
