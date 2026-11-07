---
status: accepted
date: 2026-11-05
supersedes: 0114, 0115, 0116, 0166
amends: 0111, 0112, 0113, 0138 (status lines only)
---

# The Checagem externa leaves the tablet and returns on the Desk

Henok decided on 4 November that the Checagem externa lives on the facilitator's Desk, not on the tablet (ENG-2164).

## Context

The tablet carried the whole Checagem externa: a Station, a listener screen, a button and a listeners count on the Back-translation of an approved draft, a listener's resume point, five `external-check` calls and three script lines. The Checagem externa was paused on 26 October. In the hand test of 4 November the approval line pointed to a button the «Ensaio salvo» screen did not have.

## Decision

- **The tablet has no Checagem externa.** No Station, stage, screen, control, script line or route of it remains in the app.
- **The Back-translation of an approved draft ends on «Aprovado como rascunho final da equipe (vN).»** No button and no listeners count follow it.
- **A resume point an older build saved on the Checagem externa reads as a resume point on the Rehearsal, so the takes it names are restored as the home restores them**, and a listener it names is ignored. The `checagem-` recordings older builds left in the recordings folder are swept at launch. An approved draft then lands as any other resume point onto it does (ADR 0138).
- **The API keeps its `external-check` routes** for the Desk.

## Consequences

- ADR 0114, 0115, 0116 and 0166 are superseded. ADR 0111 keeps the listener count per version for the API; ADR 0112 keeps the three refusal texts, and the approval's saved screen without its last line; ADR 0113 keeps the armed tap over an approved draft; ADR 0138 keeps the conversation as where an approved passage reopens, and the dot to the home with its badge. Only the tablet's half of the Checagem externa is gone.
- The Desk's own Checagem externa is defined elsewhere (ENG-2156).
