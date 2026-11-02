---
status: accepted, amended by 0100, 0146, 0167
date: 2026-10-20
amends: 0053 (a door of its own and its rows), 0068, 0085, 0099
---

# A frase nobody understood is asked again, and the scene screen closes after her send-off line

Amended by 0167 (ENG-1907, 2026-10-30): the reply of «terminei» plays from the moment it lands, beneath the send-off line, and not after the screen closes; the screen still closes after 1.4 s.

This amends ADRs 0053, 0068, 0085 and 0099 without editing their decisions; it adds "amended by
0101" to their status lines. The Definer settled the rules on 19 and 20 October (ENG-1363).

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

- The scene frase is its own door. Its wordless refusal, its network failure (the tablet's own
  timeout included), an answer it cannot read, and every refusal of the frase, named
  (UNKNOWN_REFERENCE, TOO_LARGE, a 413) or not (a 422), are `TheTellingCameBackEmpty` (0068's
  event), never a counted refusal, never the person sign, never the offline fall. A code that
  once stopped the room (UNAUTHORIZED, FORBIDDEN, DEVICE_REVOKED) is a frase not understood
  too, since only her six cases raise the person sign (0093). A sent, gone or out-of-place
  rehearsal still reads the list again, and SCENE_REHEARSAL_SENDING says nothing of the frase.
- In the Scene rehearsal that event asks the frase again through one effect, and the mark lives
  on the scene screen, not on the machine: a new screen is born without it, and the frase
  microphone opening clears it.
- Every end of a frase's post lets it go but SCENE_REHEARSAL_SENDING, which keeps it held to be
  sent again (amending 0099's let-go list): a frase lost to the network or refused is let go,
  the next circle opens the microphone, and the team speaks it again. The room's refusal of a
  frase over a span it already kept (FRASE_OUT_OF_PLACE) now guards what the resend of the
  same bytes guarded: if the room had kept the first, the new one is refused and the list read
  shows the kept one, never two. A translation again names the frase it replaces, and the room
  replaces the newest of that frase's chain, so the screen still shows one.
- A frase translated again posts its own span and names the frase it replaces. The take does
  not play on after it lands. When its answer is lost (or cannot be read), the policy says
  so with 0068's event marked to read the list again, and the notifier never tells a lost
  answer apart itself (0053). The screen keeps «traduzindo de novo…» and waits, with nothing
  to tap, until the list read lands and decides: kept, it shows as kept with no line; not
  kept, her line and «manter a tradução de antes». A list read that fails shows her line
  with no «manter»: the next circle translates the piece again, and play and «terminei» read
  the list first and decide from it; a «terminei» the list shows kept sends the scene.
- That the room may hold a translation the team has not seen stays with the rehearsal, not on
  the screen: a bar tap, opening the rehearsal again or rebuilding the screen keeps it, and
  play and «terminei» read the list first while it stands. A list read that lands, or a new
  translation of that frase kept, ends it.
- A list read keeps a frase armed to be translated again while the list still holds it; if not,
  the arm drops and its stretch stops.
- «terminei» with a held frase whose last try is not kept stops at her line, and the piece
  stays at its cut. The scene goes once that piece is translated again and «terminei» is tapped,
  or on a second «terminei», which sends without it: on hers the refusal is seen before
  «terminei» can be pressed again.
- «terminei» shows her line on the answer in its place, holds the screen 1.4 s, then closes it
  and voices the reply on the Canvas. The send's inert screen (0085) stays inert through the
  1.4 s.

## Considered Options

**The machine's `wordlessTelling` fact, as the retro's.** Rejected: it is cleared only by a
Station change, the capture microphone and the verdict, so on the scene screen it would outlive
«gravar de novo», a row switch or a restart.

**That uncertainty on the scene screen.** Rejected: a bar tap or a rebuilt screen dropped it,
and «terminei» then sent the voice a translation the team never saw.

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
