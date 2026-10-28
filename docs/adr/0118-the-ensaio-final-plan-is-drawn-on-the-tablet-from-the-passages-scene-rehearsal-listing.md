---
status: accepted, amended by 0134 (the other-language case opens the grain choice under her line while no grain is in force)
date: 2026-10-23
---

# The Ensaio Final plan is drawn on the tablet from the passage's scene-rehearsal listing

The Definer settled the rules on ENG-1383 (Definition of 22 October, as corrected the same
day).

## Context

The Ensaio Final plan shows one row per scene of the passage, each naming the rehearsal that
would join it, and opens «juntar as cenas e ouvir». Marcia's app works the plan out on her
server and sends it whole. Ours already reads the passage's live scene rehearsals of every
session in one listing before the plan opens (ADR 0117), and that listing carries everything
the rows need: each rehearsal's session, scene label, number, recording time, length, current
frases, the time the voice received it, whether the room confirmed it, and its content type.

## Decision

- **The tablet derives the plan from that one listing.** The server gains no plan door. The
  candidates of a scene are this session's rehearsals labelled with it that hold at least one
  current frase, newest first. Only this session's count, because two sessions of a passage
  are two interface languages.
- **The Default rehearsal is the joinable candidate the voice received last**, ties to the
  higher number. An unsent one is never the default.
- **Joinable reads three facts of the record:** sent, confirmed by the room, and a WAV
  content type, the server's own WAV rule. A WAV this tablet records is always 16 kHz mono,
  so the type is enough.
- **«tradução incompleta» is her coverage rule:** a stretch of half a second or more of the
  take, inside it or at its tail, that no current frase covers. Such a rehearsal stays the
  default and stays joinable.
- **«juntar» opens by her `canJoin`:** when at least one scene has a joinable rehearsal
  chosen. A scene without one is not joined and its row says why. Her other half, "or a
  scene is already joined", is not built here: any take sends the dot to the recording
  home, so no joined part reaches the plan yet.
- **«trocar o ensaio desta cena» moves the row to the next joinable candidate**, newest
  first, round and round, and is offered only where there is another joinable one, until
  ENG-1384 turns the tap into the sheet.
- **The other language is read from the same listing.** A team holds one live session per
  passage and language, so "nothing of this session, a sent rehearsal of another session" is
  "the rehearsals sit in the other language". The dot then opens the recording home under her
  line while no part exists. There is no second read and no 2.5 s cut.
- **The team's choices last one visit of the plan.** Each tap of the dot starts from the
  defaults, and the choices are never written to the Resume point.

## Consequences

ENG-1384's sheet and card and ENG-1385's join read the same rows. A listing without the
room's confirmation makes every rehearsal unjoinable, so its rows say «este ensaio não pode
entrar» rather than join a take the room never confirmed; one without a content type reads
as the WAV this tablet records.

## Amendment · 2026-10-27 (ENG-1830)

Her app lets the team choose an unsent rehearsal; only the default must be sent. «Unsent
rehearsals are swappable with a 'não enviado' badge and are never the default»
(`ENSAIO-FINAL-SPEC.md:522`). Her plan's candidates include unsent rehearsals
(`src/draft/joinPlan.ts:103-107`), her sheet marks «usar este» on any WAV the row does not
hold, sent or not (`ensaioFinal.ts:617`, `usable: c.wav && c.n !== inUseN`), and her row
offers «trocar» where there is more than one candidate or none is chosen
(`ensaioFinal.ts:363`). Her app wins over this record, so three of its rules change.

- **Usable** is a new fact of the record: confirmed by the room and a WAV, sent or not yet
  sent. A sent one whose time does not read is not Usable. Joinable keeps its meaning and
  still draws the Default rehearsal, so an unsent one is never the default.
- «trocar o ensaio desta cena» is offered wherever the row has a Usable rehearsal it does
  not hold, and the Rehearsal sheet marks «usar este» on each of them. A row the team points
  at an unsent one holds it, «juntar» opens on it, and the join sends it as the scene's
  part. The room's take door accepts an unsent origin: it checks only that the origin is a
  live rehearsal of the passage.
- A row with nothing chosen says «falta o ensaio desta cena» while a Usable rehearsal is
  there, and «este ensaio não pode entrar — ensaiem esta cena de novo» only when none is, as
  her row does (`ensaioFinal.ts:361`).
- The «não enviado» badge belongs to the sheet's line (`candidateLine`,
  `ensaioFinal.ts:331-332`). A plan row holding an unsent rehearsal writes only its facts,
  as a row holding a sent one does: hers writes `rowText` there (`ensaioFinal.ts:360`,
  `EnsaioFinalPlan.tsx:90`).

The recording home's doors still read Joinable. Hers offer an unsent rehearsal there too;
that is its own follow-up.

## Amendment · 2026-10-28 (ENG-1949)

The recording home now offers what hers offers, and the plan's «trocar» is her rule. Two
of the rules above change.

- **The recording home's doors read her `homeRow`** (`ensaioFinal.ts:600-607`). «usar o
  ensaio desta cena» stands on a row with no joined part while a Usable rehearsal of the
  scene exists, sent or not (her test `ensaioFinalTest.ts:314`). «trocar o ensaio desta
  cena» stands on a joined row while the scene has any other rehearsal, whatever it is
  (`:604`, her test `:317`). The home sheet marks «usar este» on each Usable rehearsal
  the row does not hold (`:617`), so an unsent one swaps in through the same path the
  plan's join takes. A rehearsal that cannot enter is listed with its note and no
  «usar este». This closes the follow-up the 2026-10-27 amendment named, and replaces the
  door rule of ADR 0122.
- **«trocar o ensaio desta cena» on a plan row is her `canSwap`** (`ensaioFinal.ts:363`):
  wherever the row has more than one candidate, or none is chosen and one exists, never
  over a joined part. A row holding its sent rehearsal beside one that cannot enter offers
  it, and so does a row whose only rehearsal cannot enter. «usar este» still asks for a
  Usable one, so what can be chosen does not change.
