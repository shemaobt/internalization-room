---
status: accepted
date: 2026-10-20
amends: 0053 (a door of its own and its rows), 0068, 0085, 0099
---

# A frase nobody understood is asked again, and the scene screen closes after her send-off line

This amends ADRs 0053, 0068, 0085 and 0099 without editing their decisions; it adds "amended by
0101" to their status lines. The Definer settled the rules on 19 October (ENG-1363).

## Context

On the scene rehearsal's translate step the room hears each frase before it keeps it. A frase
with no words is refused as WORDLESS_TELLING, and the room answers the same for a recognizer
that failed, timed out or was unavailable. Until now that refusal went through the scene
rehearsal's door, whose row swallows any refusal, so the team saw nothing; a frase lost to the
network made the room fall out of reach. Marcia's app shows «não entendi — traduzam de novo
esse pedaço» on any failure of a frase and asks it again. Her app also lets the team tap a
frase's bar to translate it again, and holds «a tradução do ensaio da cena foi para a voz» for
1.4 s after «terminei» is answered.

## Decision

- The scene frase is its own door. Its wordless refusal and its network failure, the tablet's
  own timeout included, are `TheTellingCameBackEmpty` (0068's event), never a counted refusal,
  never the person sign, never the offline fall. A code that stops the room still stops it, and
  a sent, gone or out-of-place rehearsal still reads the list again.
- In the Scene rehearsal that event asks the frase again through one effect, and the mark lives
  on the scene screen, not on the machine: a new screen is born without it, and the frase
  microphone opening clears it.
- A frase lost to the network is let go, not held (amending 0099): the next circle opens the
  microphone and the team speaks it again. The room's refusal of a frase over a span it already
  kept (FRASE_OUT_OF_PLACE) now guards what the resend of the same bytes guarded: if the room
  had kept the first, the new one is refused and the list read shows the kept one, never two.
  A translation again lost the same way names the frase it replaces, so the room keeps the new
  one over the lost one and the screen still shows one.
- A frase translated again posts its own span and names the frase it replaces. The take does
  not play on after it lands.
- «terminei» shows her line on the answer, holds the screen 1.4 s, then closes it and voices the
  reply on the Canvas. The send's inert screen (0085) stays inert through the 1.4 s.

## Considered Options

**The machine's `wordlessTelling` fact, as the retro's.** Rejected: it is cleared only by a
Station change, the capture microphone and the verdict, so on the scene screen it would outlive
«gravar de novo», a row switch or a restart.

**Keeping a frase lost to the network held, and resending its bytes at the next circle.**
Rejected: her line asks the team to translate the piece again, and the tap must do what the line
says.

**Voicing the reply beneath the open screen, as her app does.** Rejected: a Station change moves
the Generation and silences the room (0083, 0058), so the reply would be cut when the screen
closed.

## Consequences

The reply starts 1.4 s after the answer, where hers starts at once. A dropped connection on a
frase reads «não entendi» and never «sem conexão». A frase the room kept while its answer was
lost costs the team one more recording, which the room refuses.
