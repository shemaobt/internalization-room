---
status: accepted
date: 2026-11-02
amends: 0170 (in part: a refusal that carries its own route never writes her line)
---

# A refusal that names a frase leads to it whatever its line did

This amends ADR 0170 without editing its decision: it adds "amended by 0175" to its status
line. Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket
(ENG-2129).

## Context

ADR 0170 made every verdict that will not sound write «não deu para conferir agora — tentem
de novo» and rest where «terminei» was pressed. The check refused because a frase still
awaited its words took its own route, reading the stretches back and opening that frase's
retell, only when the room sent no fixed line. With a line (the N5 the room names for a
re-recorded sentence), the refusal was loaded as a reply and went down the verdict's path, so
an N5 the player failed, or an asset the room could not serve for the language, ended with
her check-failed line and nothing open. The refusal's route was lost to a sound that was never
the point of it.

Her Drafting answers the awaiting refusal by re-reading the passage and calling `toAwaiting`
whatever any audio did (`app/components/Drafting.tsx:1498-1502` at 18fa7c4). `toAwaiting`
says the awaiting line and opens the frase (`:1046-1056`); the line resolves on a fetch
error, on a player error and on a rejected play (`:915-937`). Only a passage with no awaiting
frase in it makes `toAwaiting` answer false, and only then is `btCheckFailed` written
(`:1501`). Her `lastVerdict` is kept when the check's own audio arrives (`:1537`), never for
a refusal's line.

## Decision

- **A refusal that names a frase takes one branch, with or without a line.** The line is said
  through the door the untranslated stretch already uses, its failure is swallowed there, the
  stretches are read back and the team is led to the frase afterwards. A line that does not
  load, that the room refuses, or that the player fails leaves the frase open and the line
  silent.
- **Her check-failed line is written only by a verdict with no route of its own:** one that
  arrives with no audio and no fixed line, or whose own sound will not play (ADR 0170). The
  untranslated stretch keeps the same rule it had: its route never depended on its line.
- **A refusal's line is not what «ouvir a resposta de novo» gives back.** Said as a line, not
  loaded as a reply, it is never kept as the last spoken; the replay stays with the verdict's
  own audio, as hers does.

## Consequences

- A team whose N5 cannot sound is still led to the frase it has to translate, instead of
  reading a line about the check and finding nothing to touch.
- The refusal's line no longer shows the replay button on the retro after a refusal.
- The room never answers this refusal without naming the frase, so no branch exists for a
  nameless one.
