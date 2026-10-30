---
status: accepted, amended by ENG-1862 (2026-10-29: an unread room asks the grain whatever is remembered); amended by ENG-1892 (2026-10-29: the choice acts on one tap); amended by ENG-2084 (2026-10-30: «A passagem inteira» reaches the plan through the whole home); amended by ENG-2103 (2026-10-30: a remembered grain is let go when the room's listing names none)
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
  only while the room names no grain. With the room's grain those cases open that grain's
  recording home; a grain read off takes an earlier visit left on the tablet never decides
  them, as her draft alone does (ENG-2078). Every other case is ENG-1382's.
- **The choice is a value of the plan, not a Station:** it is drawn on the plan Step, never a
  resume point. «A passagem inteira» switches to `whole` and opens the whole-passage home;
  «Cena por cena» switches to `scene` and reads the plan again.
- **The grain in force** is the listing's `grain`, else read off the current parts (a numbered
  part is `scene`, only the whole is `whole`), the server's own rule. It is written in the
  Resume point.
- **The whole-passage home** is the recording home with one row, «A passagem inteira». Its take
  goes up as `scope=passagem-inteira` with no `chunk_index`; recording it again replaces it at
  the next pass.
- **«gravar a passagem inteira de uma vez»** (on the plan, on a scene home over a joined
  recording, and on the check screen of a joined recording) takes one tap when nothing would
  be lost and ENG-1260's Armed tap otherwise:
  «toquem de novo: isto abre de novo o rascunho aprovado» over an approved draft, else «toquem
  de novo: as cenas e as traduções ficam guardadas». On a scene home with no join, her plain
  «Gravar a passagem inteira» takes one tap.
- **On the check screen** (ENG-1876, hers at Drafting.tsx:2465-2471) it stands under «voltar e
  regravar uma parte» through the whole telling step, never on the first listen and never over
  a recording no join touched. It is dimmed and takes no tap while a part or a line sounds,
  while the telling is recorded, sent or checked, while a sentence re-record is open, while an
  approval or an open of the Checagem externa is in the air, and while the room is stopped for
  a person; a part still on its way to the room does not rest it, as hers. Its second tap
  leaves the check for the recording home at once, as hers does (`exitBt` before the grain
  door, Drafting.tsx:2094-2101): leaving reports what was heard while the scene parts still
  stand, and nothing on the check can be started while the door is in the air. The switch then
  runs as the home's own does; a door that fails leaves the team on the recording home at the
  joined grain.
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
  (Drafting.tsx:2565-2569). The home's grain controls and the plan's «gravar a passagem
  inteira de uma vez» are dimmed and take no tap while a take records, is being kept or is on
  its way to the room, while a join or a bring-back runs, and while a switch is in the air
  (hers: `busy || grainBusy`, Drafting.tsx:2132-2137, :2274, :2566). A take whose send failed
  holds nothing. The plan's «Gravar cena por cena» still rests on the join and the switch
  alone: the plan never opens over a session holding its own part take.
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

## Amendment · 2026-10-29 (ENG-1862)

Her frozen app is the rule (João, 2026-10-26). Hers draws «Como vocês querem gravar?» whenever
the plan and the draft both went unread, whatever grain the team chose before
(`todaysScreen(null)`, ensaioFinal.ts:43,76 at 18fa7c4), and a draft she did read takes her to
that grain's screen. The first case changes: **a plan read that fails or runs out at 6 seconds
with the room's listing unread shows the grain choice even with a grain in force.** With the
listing read, a grain in force still opens that grain's home, and a listing that answers after
the choice stood still takes the team to the grain it names.

**A tap on the choice always calls the door,** also on the grain already in force, as her
`chooseGrain` always sends its PUT; the room answers a switch to the grain it holds without
changing anything. A door that fails changes nothing and says nothing, as above. The plan's and
the home's grain controls still go straight to a grain already in force.

## Amendment · 2026-10-29 (ENG-1892)

Her grain choice is two plain buttons (Drafting.tsx:2292-2293): one tap sends her PUT, and over
a finalized draft it switches all the same (app/api/draft/route.ts:106-120). She draws it only
while no draft holds a grain or the draft went unread (ensaioFinal.ts:43,76), and the room's
listing names a grain whenever it holds a current part, so ours never asks it over a draft the
tablet has read. **«A passagem inteira» and «Cena por cena» on the choice take one tap, never the
Armed tap, and never show «toquem de novo: isto abre de novo o rascunho aprovado».** Every tap
on the choice sends `reopens_the_approved_draft`, as the plain one-tap switches do, so the room
never refuses it `DRAFT_APPROVED`. The arm after a refused switch now belongs to the controls
alone: «gravar a passagem inteira de uma vez» and «Ensaio Final: juntar os ensaios das cenas»
on the home, the plan and the check keep their armed text.

The choice still stands over an approved draft when the room's listing went unread, so the
re-open is still needed there. **On the grain the room already holds, the re-open changes
nothing:** shema-api's `switch_the_grain` returns before it reads the approval
(`app/services/internalization_room/sessions.py:1554-1557`), so the approval and the parts stay
and the amendment above still holds. The flag is not left off there: with the listing unread, the
grain the tablet remembers may not be the room's, and a re-open withheld by that memory would be
refused on every tap of that button.

## Amendment · 2026-10-30 (ENG-2084)

Her `chooseGrain("whole")` (Drafting.tsx:2292, :540-555) sets the new empty whole draft and
reads the plan again, and `efScreen` sends an empty draft whose plan holds a scene rehearsal
of this session to the plan (ensaioFinal.ts:79-80, `planHasRehearsals` :90-92). **«A passagem
inteira» on the choice still opens the whole-passage home at once, and the home's own read of
the rehearsals takes it to the Ensaio Final plan when one of this session is there,** while
it still records the whole and nothing is recorded or kept on it; with none the team stays on
the home, and a «Gravar cena por cena» tapped before the read answers is her `aside`. A listing that names
the whole after the choice stood takes the same way. A plan read that follows counts the grain
as named, so a listing that does not answer there opens the whole home, never the choice again.
The empty whole home over a rehearsal is still reached from the plan by «gravar a passagem
inteira de uma vez», her `aside` (ensaioFinal.ts:68-71), and stays.

## Amendment · 2026-10-30 (ENG-2103)

Her frozen app is the rule (João, 2026-10-26). Hers keeps no grain on the tablet: her screen
is chosen from the draft's grain on every read (`todaysScreen`, ensaioFinal.ts:43 at 18fa7c4),
and a draft with no grain shows the choice. **The grain in force is the listing's `grain`
alone where the dot chooses its screen:** the grain written in the Resume point stands only
until the plan read hears the room, and a listing that answers there and names no grain lets
it go, so her three cases show the choice and the plan's whole-passage arm (ADR 0117, amended
by ENG-2103) reads no remembered grain. A listing that does not answer still asks the grain
whatever is remembered (ENG-1862), and a grain the room names is still the tablet's. The grain
read off the current parts still orders the rows, the row of the whole and the home's one row
(ENG-2078); it decides no screen.
