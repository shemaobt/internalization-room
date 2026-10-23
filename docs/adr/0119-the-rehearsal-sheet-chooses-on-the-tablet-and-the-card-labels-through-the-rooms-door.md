---
status: accepted
date: 2026-10-23
---

# The Rehearsal sheet chooses on the tablet, and the card labels through the room's door

The Definer settled the rules on ENG-1384 (Definition of 22 October, with the answers of
23 October: the card is in this ticket, and nothing on the plan screen is armed).

## Context

A plan row's «trocar o ensaio desta cena» opens the scene's Rehearsal sheet, where the team
picks the rehearsal that stands for the scene. Rehearsals with no Scene label of the passage
(recorded while the scene list was missing, or before labels existed) are put to the team on
the card «De que cena é este ensaio?». The room already has a door that labels a rehearsal
afterwards, and answers its record.

## Decision

- **«usar este» on the plan is the team's choice, held for the visit, with no request**, as
  ADR 0118 holds choices. It is one tap: nothing on the plan can be lost, since nothing there
  is joined yet. Only «juntar as cenas e ouvir» joins.
- **The card writes the label through the room's label door at once**, not through the
  Outbox. It sends one label at a time, and the record the room answers replaces the one in
  the plan's read, so the rows and the card re-derive without a second read.
- **A label the room could not keep says her line**, «não deu para guardar a resposta —
  toquem de novo», and the rehearsal stays on the card. Tapping again is safe, because the
  door changes nothing for the same label. The door names a rehearsal, so a 404 there is a
  refusal and says the same line; a session the room forgot meets the Failure policy at the
  next door that asks for the session.
- **«gravar esta cena de novo» is an arrival from the plan Step to the Scene rehearsal
  Station**, with the scene highlighted and never picked. Unlike the red microphone, it never
  reopens the room's newest unsent rehearsal, which stays on the sheet; a take still waiting
  in the Outbox does come back, so it is never recorded over unseen. Leaving that screen
  lands on the Conversation, as from the red microphone.

## Considered and rejected

- **The Outbox for the label:** a queued answer would draw a scene the room may refuse, and
  Marcia's app posts it at once.
- **Reading the plan again after a label:** it would flash «pensando…» and could route away,
  while the door already answers the record.
- **Arming «usar este» on the plan:** her app arms it only on the recording home, and an
  approved draft never stands under the plan. The armed swap is ENG-1407's.
- **A second arm state:** an armed control goes through ENG-1260's one armed tap.

## Consequences

ENG-1407 opens the same sheet from the recording home, where «usar este» swaps a part
through the Outbox. ENG-1385 holds the sheet and the card while it joins, and refuses to
join while a label is in the air.
