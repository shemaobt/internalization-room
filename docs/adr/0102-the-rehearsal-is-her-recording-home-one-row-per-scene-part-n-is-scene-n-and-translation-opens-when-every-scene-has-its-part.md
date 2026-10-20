---
status: accepted
date: 2026-10-20
amends: 0014, 0040
---

# The Rehearsal is her recording home: one row per scene, part N is scene N, and translation opens when every scene has its part

This amends ADRs 0014 and 0040 without editing their decisions; it adds a paragraph to the
amendments at the top of 0014 and "amended by 0102" to 0040's status line. The Definer settled it on
19 and 20 October (ENG-1406).

## Context

Marcia's rule of 1 October makes her frozen app the bar for what the team sees. Her
recording home is one row per scene of the passage, «Cena N» with the scene's title, each
with record, listen and record again, and the button that moves on stays closed until every
scene has a recording. Ours showed the Bead row and one circle: each recording was "the
next part", tied to no scene, and one kept part opened the Back-translation. The server
already reads part i as scene i (it names a scene's title only when the rehearsal has as
many parts as the passage has scenes), and a passage take carries its number (`ordinal`)
and, since ENG-1207, the scene rehearsal it was joined from (`origin`), but no scene id.

## Decision

- **One Scene row per scene**, in passage order: «Cena N», the title the scenes door
  answers in the Session language, and her controls, icons labelled «Gravar», «Ouvir»,
  «Gravar de novo» and «Parar». Above them her title, «Gravem o ensaio de vocês», or
  «Ensaio Final» once a current part was joined from a scene rehearsal, and her sub-line.
  The screen's words follow the Room language (ADR 0077).
- **Part N is Scene N**, by position, the server's own rule; there is no scene column. A
  recording made from row N is kept as part N under `parte-N` and chunk N, in place of the
  part already there under its next pass; the other scenes are untouched.
- **A part keeps the number the room holds for it.** A resume restores each current part by
  its `ordinal`, never by its place in the listing, so a room holding part 3 alone shows it
  on row 3. The current part under a number is the newest row for it, as the server reads
  it, so a joined part recorded again by the team is no longer joined.
- **The advance disc opens the Back-translation only once every scene has its part**, and
  the Rehearsal's own gate refuses it otherwise, whatever calls it. The disc also stays
  dark while a recording waits for the check or a finding's mark stands, as before. While at least one
  scene has a part and another has none, «gravem todas as partes primeiro» stands beneath
  it. While the scene list is awaited or missing, the disc stays closed and the list is
  asked again on the scene list's own retry ladder; a passage the room answers with no
  scenes keeps the one-part rule.
- **The circle stays** (halt, warning, the person's long press, ADR 0040): it records the
  part a finding sent the team back for, else the first scene with no part, and with every
  scene recorded it does nothing.
- **Parts beyond the last scene**, from sessions recorded before this, get no row; they are
  kept, played and told in the Back-translation, and nothing is deleted.
- **The Bead row leaves the Rehearsal**; the Back-translation and the findings keep it,
  and there the segments are still «parte N».
- **Her recording home is the eighth named exception of ADR 0014**, under the moment
  label's reason: her words, which the team reads.

## Considered Options

**Keep the Bead row and add the rows.** Rejected: two pictures of one recording.

**A scene id column on the take.** Rejected: the server's rule is positional, and the
Definer settled it.

**The gate open while the scene list is unknown.** Rejected: the rule is "every scene".

**Renumber restored parts by their place.** Rejected: a room holding part 3 alone would
show it on row 1, as if scene 1 were the one recorded.

**Count a row's listening in the Listening ledger here.** Moved to ENG-1419, which owns the
report: the Back-translation hears every part again from its start before «terminei»
lights, so the Rehearsal's listening never reaches the report the check sends today.

## Consequences

A team can no longer reach the Back-translation with half the passage recorded. A session
recorded before this with fewer parts than scenes reopens with the missing rows waiting, the
disc closed, and «gravem todas as partes primeiro» beneath it.
