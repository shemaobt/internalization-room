---
status: accepted
date: 2026-10-28
amends: 0068 (every result that leaves a telling not stored), 0101 (the frase door's timeout, found nothing and sent rehearsal), 0131 (the Back-translation leaves the Outbox)
---

# A translated piece that was not stored is translated again, and never waits in the Outbox

This amends ADRs 0068, 0101 and 0131 without editing their decisions; it adds "amended by
0146" to their status lines. The Definer settled the rule with Jonatas on 22 October
(ENG-1411).

## Context

In Marcia's app any translated piece the room did not store stops the screen at its cut with
«não entendi — traduzam de novo esse pedaço», and nothing is re-sent later. Ours already did
so for a frase lost to the network or refused. It did not for a timeout (a silent let-go), for
an answer that found nothing (the sign waiting for the Canvas), or for a sent rehearsal met at
the frase door (the list read again, with no word). The Back-translation also put every stretch
that failed in the Outbox as a whole-passage take, which went up later by itself, so a stale
translation could reach the record the team never saw.

## Decision

- **At the scene frase door and the Back-translation's telling door, every result that leaves
  the piece not stored is a telling not understood** (0068's event): the network, a timeout,
  found nothing, an answer without a reply, a wordless telling, and any refusal not named
  below. Her line shows, the pause stays at the cut, the recording is untouched, and nothing is
  counted, halted or signed.
- **Excepted at the frase door:** SCENE_REHEARSAL_SENT shows «a tradução deste ensaio da cena
  já foi para a voz» and reads the list again, as a refused «terminei» does; a refused moved
  pause keeps her refusal line; a frase out of place or a translation again still reads the
  list; SCENE_REHEARSAL_SENDING still says nothing of the frase.
- **A stretch the tablet could not send at all is not stored either:** one over a part the room
  has not named yet, and one whose recording the tablet could not read, read her line the same
  way.
- **The one exception is a key still in flight.** When the room keeps answering that it is
  still working on a stretch and the tablet stops asking, the step is let go and the stretch
  stays pending: the room may yet store it, so asking the team to translate it again could put
  two translations over one cut.
- **The Back-translation never uses the Outbox.** A stretch goes to the room at the cut or not at
  all. A Back-translation row an older build left in the Outbox is removed with its copy before
  the Outbox sends anything, and never reaches the room.
- The scene turn («terminei») is untouched: a rehearsal answered with nothing to play still
  keeps the sign for the Canvas. The two are told apart by door, never by Station.
- ADR 0093's six cases stay six: none of these failures was one of them.

## Considered Options

**Keeping the queued copy as a safety net.** Rejected: her line asks the team to translate the
piece again, and a copy sent later puts a translation in the record that the team replaced or
never meant.

**Letting old rows go up once.** Rejected: they are exactly what the rule forbids from reaching
the server.

## Consequences

- A stretch lost to the network is told again by the team, never recovered from the tablet.
- A stretch or a correction the room refused no longer stays pending for the check: her line
  shows, and the circle records it again.
- The busy watchdog still gives up at its own door: a telling stuck past it, which the room
  client's own timeout reaches first, lets the step go in silence.
