---
status: accepted, amended by 0101 (every end but SCENE_REHEARSAL_SENDING lets a held frase go: a network loss, UNKNOWN_REFERENCE, TOO_LARGE and a 413 join the let-go list)
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
- A frase is held by its rehearsal from the moment it is posted until the room says it
  kept it or refuses that frase (WORDLESS_TELLING, FRASE_OUT_OF_PLACE,
  SCENE_REHEARSAL_SENT, or the 404 of a rehearsal that is gone). Every other end keeps it
  held: a network failure, a 5xx, the tablet's timeout, an answer it cannot read, and any
  other refusal. While it is held, the next tap that would open the microphone for that
  rehearsal sends the same bytes, span and attempt again, whatever screen was rebuilt in
  between; the room's same-bytes rule makes them one frase. An answer lets go only of
  the frase it answers. «terminei» sends a held frase first, and the rehearsal only if
  the screen that asked is still there once the frase is kept or refused.
- The room refuses a frase that overlaps a current one as FRASE_OUT_OF_PLACE; the tablet
  then reads the list again, so a frase kept while its screen was away shows with its
  frontier.
- A held frase's file is deleted when it is let go, when its rehearsal is sent or
  recorded again, when its session is gone, and when the life ends. Frases a killed app
  left are swept at launch, once per process.
- «gravar de novo» waits while a frase is closing or in the air, and a frase whose screen
  moved on before it was sent is never sent.
- The frase upload follows the scene rehearsal's flow in the session notifier (ADRs
  0085-0089); its move into the machine is that flow's, not this decision's.

## Considered Options

**The Outbox, as the scene take.** Rejected: a frase queued past «terminei» would reach the
voice late, and the screen cannot play on from the frase until the room has kept it.

## Consequences

The scene take's loudness is read off the UI thread, since a take may be as large as the
room keeps (about 65 ms for 25 MB on an M4 Pro, more on a tablet); the screen opens at once,
the strip draws when it arrives, and a pausa tapped before stays at the tap.

A frase is lost if the app dies while it is in the air, and the team records it again: the
held frase lives as long as the life that posted it. The room
is silent for the seconds the server spends hearing each frase.
