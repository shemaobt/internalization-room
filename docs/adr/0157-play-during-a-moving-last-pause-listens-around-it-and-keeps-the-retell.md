---
status: accepted, amended by 0171
date: 2026-10-29
amends: 0100 (play during a move no longer drops it)
---

# Play during a moving last pause listens around it and keeps the retell

On the scene rehearsal's translate step, ADR 0100 had play drop the move of the last frase's
pause, as it drops any pending pausa: the frase translated again was let go, the moved pause
cleared, and the take went on from where the translation stopped. Marcia's app at
Tripod-Internalization 18fa7c4 does not (`app/components/Rehearsal.tsx:640-656`): while the last
frase's pause is on the move, play and pause only listen around it, and the retell, its line and
«manter a tradução de antes» stay. The row is the control; «manter» is the way out (ENG-1919).

With the last frase translated again and its pause on the move:

- while the take sounds, play pauses it, and nothing else changes;
- while it is silent, play plays the take on from the moved pause to its end;
- with the moved pause at the take's own end, play plays «ouvir a pausa», since nothing lies
  after it.

Play still drops a pending pausa that no frase translated again holds, and still lets an
earlier frase's retell go, as ADR 0100 says.

## Consequences

- A line standing when play is tapped there (a refusal, «não entendi», a failed restart) stays
  in all three cases, as hers keeps its message; it goes at the next gesture that clears it.
  Play at the take's end plays the 1.5 s before the pause itself, so the «ouvir a pausa»
  button's own clearing of the line does not come with it.
- A moved frase held to be sent again stays held under play, and play still listens around its
  pause; only the adjust row's «ouvir a pausa» does nothing while a frase waits to be sent again.
