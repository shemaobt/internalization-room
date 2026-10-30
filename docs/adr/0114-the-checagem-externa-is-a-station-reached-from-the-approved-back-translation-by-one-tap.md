---
status: accepted, amended by 0166
date: 2026-10-23
amends: 0014 (her Checagem externa screen is a named exception)
---

# The Checagem externa is a Station reached from the approved Back-translation by one tap

Her app at Tripod-Internalization 18fa7c4 is the bar (`ExternalCheck.tsx`, `strings.ts`,
`app/api/external/open/route.ts`). The server half is shema-api ADR 0082: the team's door
`POST /sessions/{id}/external-check/open` answers the approved Version's one record, creating it
on the first open, and refuses `DRAFT_NOT_APPROVED` when the draft does not stand approved. The
listener rules are ADR 0111.

## Context

ADR 0113 drew «Checagem externa» on the Back-translation of an approved draft, and its tap only
read the session: there was nowhere to go. ADR 0053 lists the Checagem externa as a Station of
its own.

## Considered Options

- **The check as a state of the Back-translation.** Rejected: ADR 0053 makes it a Station, and
  the ticket's Definition says the open is a Station transition.
- **The Version held in the session state.** Rejected: it would need a clear on every Station
  change. Held in the Station, `ChecagemExterna(version)`, it leaves with it, as `Panorama(id)`
  holds its id.
- **Arriving before the room answers.** Rejected: her screen opens only with the record, and a
  refusal must leave the team where it stands.
- **Storing the Station as a Resume point now.** Rejected: that belongs with the listener's
  step (ENG-1435).

## Decision

- The tap opens the check on the room. On its answer the tablet arrives at
  `ChecagemExterna(version)`, the Version the room answered, never the one the badge drew.
  Only the Back-translation answers that arrival; every other Station ignores it.
- `DRAFT_NOT_APPROVED` reads «a checagem externa abre depois que o rascunho final é aprovado»
  and reads the session, so the approval and the button leave with that read (ADR 0106). Any
  other failure reads «não deu para abrir a checagem externa — tentem de novo», with no person
  sign. The session gone takes the team to the Choice, as on every door that names it.
- The door answers its refusals itself, kept out of the failure policy by this decision, as
  ADR 0060 and 0085 keep theirs. A network failure is still told to the policy at the
  stretches' door, as the Session read it replaces did, and the session gone goes through it.
- While the open is in the air no other Back-translation gesture acts, as while an approval
  is: what the team taps meanwhile would otherwise sound on the station or be answered after
  the team left.
- The Station shows her title, her idle sub-line and «Novo ouvinte», not yet enabled, with no
  listener count at zero. Its back control, «Voltar para a gravação», returns to the
  Back-translation as it was. Nothing is spoken on arrival.

## Consequences

- A relaunch on the Station lands on the Back-translation until ENG-1435 stores it.
- The open needs the server of shema-api ADR 0082: against a server without the door it answers
  404, which reads as the session gone.
- The listeners (ENG-1422, ENG-1429) fill the Station's steps; the labels «Checagem externa» and
  «Novo ouvinte» are what they find it by.
