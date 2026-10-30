---
status: accepted
date: 2026-10-30
amends: 0152 (in part: the verdict is no longer a reply loaded once more), 0160 (in part: the verdict's sound is no longer a source of a waiting halt)
---

# A verdict without audio or that will not sound writes her line and rests

This amends ADRs 0152 and 0160 without editing their decisions: it adds "amended by 0170" to
their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October). Settled
on the ticket (ENG-2092).

## Context

ADR 0152 counted the verdict among the replies loaded once more 1.5 s after a failed load, with
the second failure raising the person sign, and ADR 0160 made that halt wait for the
Conversation, naming the verdict's sound failing twice as one of its sources. The verdict is not
one of her replies. Her Drafting plays it once, from the check's own answer
(`app/components/Drafting.tsx:1539-1543` at 18fa7c4): when the player fails it goes back to
rest, with no second try and no handoff, and when the check answers without audio it writes
«não deu para conferir agora — tentem de novo» and rests (`:1528`). Nothing counts a failed
verdict toward a person, and the telling stays where it was.

Ours loaded the empty answer too: a missing `audio_url` is parsed as an empty one, the voice
cannot ready it, and the reply's reload ran on nothing before parking a halt.

## Decision

- **A verdict answered with no audio and no fixed line is a check that did not happen.** It
  writes her line, puts the phase back where «terminei» was pressed, and asks the voice for
  nothing. «Terminei» again is the retry.
- **A verdict is loaded once, never again.** It is said outside the reply's reload: no
  `TheReplyFailedToLoad` is dispatched for it, so no halt is raised, none waits for the
  Conversation, and nobody is called, whether the clip did not come down, the room refused it
  or the player refused it.
- **A verdict that will not sound writes the same line and rests.** The phase goes back to
  where «terminei» was pressed and the unplayable turn, which belongs to the Conversation, is
  not registered. A verdict whose clip came down to the tablet and whose player then refused
  it stays the one «ouvir a resposta de novo» says, as her `lastVerdict` is kept once the
  audio is in the check's answer (`:1537`); a fail-safe verdict the room could not compose is
  still not kept (ADR 0152's exception). A verdict that arrived without audio, or whose clip
  never came down, leaves «ouvir a resposta de novo» as it was: nothing is held to replay, and
  «terminei» is the only retry.
- **A clip the room refuses while it is readied takes the refused check's branch** (ENG-2064):
  her line, decided at the verdict's door, the phase back. A session that is gone keeps its
  route to the choice.
- **Her player failure writes no line.** Her Drafting idles without one when the audio arrived
  and the player fails (`:1534`, `:1540`), with the verdict's findings already on screen and
  the replay offered. Ours never opens the findings on a verdict the team did not hear, so the
  line is written there too, as the ticket asks; without it the check would end in silence.

Every other reply keeps ADR 0152: a turn's, the Panorama's, a line said again, and the verdict
heard again through «ouvir a resposta de novo», which still goes through the reload and the
sign; that replay is offered only for a verdict whose clip is held, so the sign it can raise is
for a clip in hand that will not play twice, never for one that never came down. ADR 0160's wait stays for the halts that still reach the Back-translation: the build
guard and an `Error` in a hand-off.

## Consequences

- A verdict that fails costs the team no 1.5 s wait and no sign, on the retro or later on the
  Conversation; the word they get is her line.
- The reply's reload and the verdict's door are now two paths, proved apart.
