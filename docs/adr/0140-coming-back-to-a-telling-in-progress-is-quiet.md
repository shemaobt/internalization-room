---
status: accepted, amended by 0154 (the check waits for every part to reach the room)
date: 2026-10-28
amends: 0123
---

# Coming back to a telling in progress is quiet

ADR 0123 rule 1 left "none unheard" on today's path. On that path, coming back to a
Back-translation already partly told played the recording from the told end, under the team.
Marcia's app does not (`enterBt`, `app/components/Drafting.tsx:1106-1115`, at 18fa7c4). Coming
back to a telling in progress, it waits on a paused player, with the list, the marks and the
circle ready. ENG-1849 brings ours to hers. Her frozen app wins over this ADR and the earlier
decision in a44568c2.

## Decision

1. **Quiet.** The rule applies to every entry: the advance disc, a relaunch, and a return
   after a clean check. The room must name no part unheard, at least one frase must be told,
   no frase may be awaiting, and the room must name no untranslated stretch. Then nothing
   plays and nothing is said:
   - parts told whole are stepped over and reported heard, as before;
   - the play control waits where the telling stopped, and plays from there when pressed;
   - the circle is ready.
2. **«terminei» under her gate.** Hers counts the told frases' spans as coverage (`bReady`,
   `Drafting.tsx:898-910`). When the told ground reaches the end of every part, «terminei»
   opens at once, with nothing played. Otherwise it waits for the untold rest to be heard.
3. **A frase awaiting its translation comes first.** This applies from the recording home
   too, not only on a relaunch:
   - with every part heard: her N5, then that frase's retell at its own span;
   - when the room names only the awaiting frase's take unheard: her N5, then the sentence
     with what surrounds it, and no listen. This is her Q2 (`awaitingOnlyUnheard`,
     `app/lib/sentenceRerecord.ts:271-274`). A part whose upload has not landed has no take
     for the room to name and counts as unheard, so it keeps the listen first.
4. **A room out of reach is answered by what it last said** (ENG-1942). When the read fails,
   the return reads the room's last answer on this passage, in this Life, and goes where
   that answer would send it: quiet, the listen, or the untranslated stretch. Hers falls back
   to the passage it last held (`Drafting.tsx:1084`), which every heard report keeps up to
   date (`:422`). Every report keeps its answer, and an answer older than the one held never
   replaces it. A held answer is not "no answer".
5. **No answer held, or an older room**, stays on today's path, with one exception: a frase
   awaiting its translation still comes first, unpadded. The tablet already knows which frase
   it is, a relaunch already goes to it without asking the room, and hers reads it from the
   passage it holds when the read fails (`Drafting.tsx:1082`). A Life that has not yet had
   an answer to a report holds none: the resume read carries no unheard list.

## Consequences

- ADR 0123 rule 1's last case now reads: none unheard → this ADR; the room out of reach →
  its last answer on the passage (rule 4); no answer held or an older room → today's path,
  unless a frase awaits its translation (rule 5).
- A relaunch with a frase awaiting still goes straight to it, without asking the room first.
  Hers asks the room on a relaunch too; that difference is a follow-up.
