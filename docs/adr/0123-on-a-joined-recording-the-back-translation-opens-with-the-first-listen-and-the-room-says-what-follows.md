---
status: accepted, amended by 0140 (coming back to a telling in progress is quiet), amended by ENG-1886 (2026-10-28: the First listen draws no circle)
date: 2026-10-23
---

# On a joined recording the Back-translation opens with the First listen, and the room says what follows

On her app the team hears its whole passage once before it translates anything («Primeiro, só
ouvir: a passagem inteira, do começo ao fim.»). Ours entered the Back-translation of a Joined
recording straight into the telling, with the circle live, and threw away what the listen
door answers after the last part (shema-api ADR 0070). ENG-1408 and its Definition of
22 October settle it; the Definer's answers of 23 October (Q44, Q45) close the two open points.

## Decision

1. **When.** Only on a Joined recording. Every entry asks the room which parts are unheard:
   the advance disc, a relaunch that resumes on the Back-translation (not checked, no frase
   awaiting), and the end of a join that left every scene with its part, with no tap.
   - every part unheard: her line N0, then every part from its beginning in passage order;
   - some part heard: her P2, then only the unheard parts, each from its beginning;
   - a part the room names that this tablet does not hold: her P2, then every part, as rule 7.1
     keeps the listen for it;
   - none unheard, no answer, or an older room: today's path.
2. **A recording no join touched has the First listen too** (ENG-1206, 26 October), as hers
   does (`listenPlan`, `afterFullListen`): every entry asks the room in the same way; every
   part unheard is her P0 and the whole recording, listen-only, and so is a part recorded
   again (the whole recording, not only that part). Once the room counts every part heard,
   her P1 is said and the recording plays again from its first part, whatever was told.
   Coming back with every part heard and nothing told says P1 the same way. That listen
   never shows «ainda falta ouvir», whether it opens from the advance disc or a relaunch:
   hers clears the line on every entry (Drafting.tsx:1084).
3. **The First listen is listen-only**, from the line to the room's answer after the last
   listed part. The circle is drawn but its tap does nothing. There is no «terminei», no pause
   row and no «recomeçar a tradução». The bars and the frase rows cannot be tapped. The wood
   play reads «Tocar ou pausar a gravação» and pauses and resumes where it stopped. The title is
   «Ensaio Final», the sub line hers, and a line under the circle reads «ouvindo a gravação de
   vocês… — parte 2 · 0:41 / 1:10» while a part sounds, the place alone while it is held.
4. **Continuous.** A part's end crosses into the next listed part from its beginning, never
   into a part the room counts heard.
5. **A line that cannot be had is skipped**; the screen stands and the parts play.
6. **It counts.** Every part is reported as it ends, and a pause closes the span (ADR 0105).
7. **Translating opens only once the room counts every part heard.** The last listed part's
   report is awaited, and its answer leads:
   1. parts still unheard: the listen stays, «ainda falta ouvir um trecho da gravação», and the
      play control plays those parts. A part the room has not named yet counts as unheard, as at
      the entry; a part the room names that this tablet does not hold keeps the listen too, and
      the play control then plays the listen's parts again;
   2. a frase awaiting its translation: back to that frase, as the resume does;
   3. `STRETCH_UNTRANSLATED`: the room's line (N2), then that part from where its untranslated
      ground starts, with the circle open;
   4. `automatic_check`: the room's line (N1), then the check, with no tap;
   5. nothing told: her P1, then the telling from the untold ground;
   6. otherwise: quiet, with the circle ready and «terminei» under its own rule;
   7. no answer: the listen stays and the play control replays the parts it last played (after
      rule 7.1, only those the room named).
8. **The carried frases** are read from the room once before the listen, and stay inert during it.
9. **It belongs to one visit.** Every exit of rule 7 but 1 and 7 ends it, and so do a new entry,
   leaving the Back-translation or the passage, and any check. It is never written to the Resume
   point: a relaunch decides again from the room's answer.

## Considered and rejected

- **Counting on the tablet whether the whole was heard**: the room is the only counter (ADR 0105).
- **A separate play/pause button**: the wood play already pauses and resumes, and closes the
  ledger's span.
- **The circle hidden**: ours has no screen without the circle, which draws the voice; the
  Definition says the circle is closed (Q45).
- **Resuming mid-part after leaving**: the room counts per part, so an unheard part replays from
  its beginning.
- **A client-side rule for the automatic check**: the listen door already decides (shema-api
  ADR 0070).

## Consequences

- ADR 0105's "every part unheard: her opening line P0" is N0 on a joined recording.
- ADR 0105's replay on a joined recording is listen-only and crosses by itself; telling a part
  during that replay is no longer possible.
- The mark that a part was recorded again is gone: every entry asks the room, on every recording.
- A complete join no longer rests on the recording home: the Back-translation opens.

## Amendment · 2026-10-28 (ENG-1886)

Her frozen app is the rule (João, 2026-10-26), and hers draws no circle on the First listen:
the check circle stands only on the telling (`Drafting.tsx:2404`, at 18fa7c4). Rule 3 changes:
**the First listen draws no circle**. From the line to the room's answer after the last listed
part the screen shows the title, the sub line, the parts, the wood play and the line
«ouvindo a gravação de vocês… — parte 2 · 0:41 / 1:10». With no circle that line keeps its
place in our column, under the parts and above the wood play; hers draws the play control with
its line beside it above the parts, a difference this amendment leaves open. Nothing on the
screen draws her voice while she speaks there, as on hers. The circle comes back
when the listen ends, on whichever exit of rule 7 leaves it, and the rest of rule 3 stands.

This retires «The circle hidden» under *Considered and rejected*: the Definer's answer (Q45)
gives way to her app.
