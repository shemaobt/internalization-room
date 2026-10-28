---
status: accepted
date: 2026-10-23
amends: 0014, 0039, 0102, 0117, 0118
---

# The grain choice stands on the plan Step in her three cases, and a switch goes through the room's grain door first

This is the tablet half of ENG-1382's grain choice, split out as ENG-1766. The room's grain
door, its stamp and the listing's `grain` and `set_aside_at` are shema-api's ENG-1765.

## Context

Marcia's app keeps her older choice between recording the whole passage at once and scene by
scene reachable when the Ensaio Final plan cannot stand, and a switch between the two archives
the earlier work, never deletes it. Ours always opened the recording home in those cases, kept
every rehearsal recording as a scene's part, and could not tell a recording the room had set
aside from a current one.

## Decision

- **Her three cases:** «Como vocês querem gravar?» appears when the plan cannot be read within
  6 seconds or its read fails, when the room answers the passage with no scenes (as soon as it
  answers), or when the rehearsals sit in the other language's session (under her line) — and
  only while no grain is in force. With a grain in force those cases open that grain's
  recording home. Every other case is ENG-1382's.
- **The choice is a value of the plan, not a Station:** it is drawn on the plan Step, never a
  resume point. «A passagem inteira» switches to `whole` and opens the whole-passage home;
  «Cena por cena» switches to `scene` and reads the plan again.
- **The grain in force** is the listing's `grain`, else read off the current parts (a numbered
  part is `scene`, only the whole is `whole`), the server's own rule. It is written in the
  Resume point.
- **The whole-passage home** is the recording home with one row, «A passagem inteira». Its take
  goes up as `scope=passagem-inteira` with no `chunk_index`; recording it again replaces it at
  the next pass.
- **«gravar a passagem inteira de uma vez»** (on the plan, and on a scene home over a joined
  recording) takes one tap when nothing would be lost and ENG-1260's Armed tap otherwise:
  «toquem de novo: isto abre de novo o rascunho aprovado» over an approved draft, else «toquem
  de novo: as cenas e as traduções ficam guardadas». On a scene home with no join, her plain
  «Gravar a passagem inteira» takes one tap.
- **«Gravar cena por cena»** is always offered, on the plan and on the whole-passage home, one
  tap. The plain one-tap switches send `reopens_the_approved_draft`, since changing the
  recording form takes one tap even over an approved draft (ENG-1260).
- **«Ensaio Final: juntar os ensaios das cenas»** is offered only over an empty whole-passage
  recording (no take on the tablet, in the Outbox or in the room); it switches to `scene` and
  opens the plan, armed only over an approved draft.
- **A switch calls the door before any recording at the new grain:** the new grain's home
  opens only once the door answered. While it is in the air every grain control is dimmed and
  a second tap does nothing.
- **The recording home always draws its grain switch,** scene rows or not, as hers does
  (Drafting.tsx:2565-2569). Every grain control, on the home and on the plan, is dimmed and
  takes no tap while a take records, is being kept or is on its way to the room, while a join
  or a bring-back runs, and while a switch is in the air (hers: `busy || grainBusy`,
  Drafting.tsx:2132-2137, :2274, :2566). A take whose send failed holds nothing.
- **The door's answer is applied in one place:** the other grain's takes leave the tablet's
  parts (the Outbox keeps every row; the room sets a late one aside on arrival), the
  telling-back starts over silently, and the Resume point is rewritten.
- **What the room set aside is never current:** a take with `set_aside_at` is never a part,
  a row's recording, named joined, or fetched as a part.
- **A door that fails changes nothing:** the team stays where it was, with no sign and no
  line. `DRAFT_APPROVED` reads the session again, so the next tap arms over the approved
  draft, both on the choice and on the controls, so the next tap arms with «toquem de novo:
  isto abre de novo o rascunho aprovado» and its second tap re-opens it. A door that did not
  answer is followed by one read of the listing: if the room did switch, the tablet takes its
  grain and goes on to that grain's home only when it is the one asked. The door's 404 is a
  refusal like any other, never a session the room forgot (an exception to ADR 0039's doors
  that ask for the session): a room without the door must leave the team where it was, not
  retire its session.
- **Whichever read tells it, the room's grain is the tablet's:** a listing that answers after
  the choice stood and names a grain takes the team to that grain's home; when the grain
  changed, every take of the earlier one leaves the tablet's parts and the telling-back starts
  over in silence. Under the whole grain the whole is never set aside; under the scene grain a
  whole is never a part. Reading the plan again after «Cena por cena» starts a new generation,
  so a read still in the air from before never decides over the grain chosen.
- **A keep the disk refused belongs to its grain:** its «falhou» stands on that grain's row
  only, and a switch sets it aside with the rest of the earlier grain: it never comes back on
  a later switch and is never sent. A listing in the grain already in force changes nothing.
- **The voice never speaks of the grain.**
- **A whole rehearsal an app before 19 August sent is a whole-passage recording** while no
  scene has its part, as the room reads it: its home has the one row, and a finding over it
  leads there. The team reaches the scene rows with «Gravar cena por cena», which sets the
  whole aside in the room. This replaces ADR 0102's fold of the lone whole into the scene
  rows; the Definer settled it on 23 October (Q73).

## Considered options

- **The switch on the machine, as AGENTS.md's «The room's core» asks of new lifecycle work.**
  Not now: like the join (ADR 0120) and the Armed tap (ADR 0113), the switch is a door and
  its answer applied to the parts; its moves between Steps are the machine's own events
  (`ThePlanOpened`, `TheRehearsalOpened`). It moves out with them.

- **The choice as its own Station or Step.** Rejected: it is reached only from the plan's read
  and leads to the plan or a home; as a value of the plan the machine stays untouched and it is
  never a resume point, like the plan.
- **Deriving the grain from the takes alone.** Rejected: right after a switch every take is set
  aside, and only the listing's `grain` says which grain is empty.
- **Refusing a late take of the earlier grain on the tablet.** Rejected: the room keeps it and
  sets it aside (shema-api ADR 0096); the Outbox never holds a row forever.
- **Withdrawing the earlier grain's Outbox rows at a switch.** Rejected: the room never deletes
  what a team recorded; the server sets them aside on arrival.

## Consequences

- A take the room set aside is never a part on the tablet, and a grain is written in the
  Resume point.
- A team that taps «A passagem inteira» while the room holds parts the tablet never saw (the
  read timed out, another tablet, a reinstall) sets them aside: kept for the consultant, gone
  from the team's screen. Her app does the same.
- An app with this change against a room without the grain door: the door answers 404 and the
  team stays on the screen it was on; nothing is set aside.
