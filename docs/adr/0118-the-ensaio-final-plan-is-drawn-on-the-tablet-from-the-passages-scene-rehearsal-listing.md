---
status: accepted
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
  chosen. A scene without one is not joined and its row says why.
- **«trocar o ensaio desta cena» moves the row to the next joinable candidate**, newest
  first, round and round, until ENG-1384 turns the tap into the sheet.
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
