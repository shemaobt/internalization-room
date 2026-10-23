---
status: accepted
date: 2026-10-23
extends: 0113, 0120
---

# A joined Scene row brings its scene rehearsal's translations back with an armed tap, and the room says which rows can

The Definer settled the rules on ENG-1405 (Definition of 22 October; answers Q46–Q48 and Q67 of 23 October). The room's half is shema-api ADR 0085.

## Context

A joined part lands in the room with its scene rehearsal's frases already told. After «recomeçar a tradução», or when they never came, nothing on the tablet laid them again, so the team had to translate a joined scene a second time. The room now serves `back_translation.bring_back` (the part numbers it can lay again) on the Session read, and a door that lays them on one part.

## Decision

- The Session read's `bring_back` is the tablet's offer. Every applied Session read replaces it, and the recording home reads the session once more as it opens: a restart in the Back-translation is what makes the offer, and the next home is where it must show. That read fails silently.
- A Scene row whose number the room offers draws «trazer de volta as traduções do ensaio desta cena» under its controls. It is ENG-1260's Armed tap with her own armed text, «toquem de novo: as traduções do ensaio voltam; as que vocês fizeram aqui para esta cena ficam guardadas», also over an approved draft. The second tap counts 0.6 to 6 s after the first. The arm lapses after 6 s, when another control is armed, when the Generation moves, and at any other gesture between the two taps, which the Armed tap already does by handing the arm only to the next gesture.
- The second tap silences every player and calls the door. Until the room answers, the recording home is frozen: its rows, circle, wood play, green check, advance disc and «enviar agora» take no tap and read as disabled. The view draws the freeze; the notifier's own gesture refuses while one runs.
- The room's stretches replace the tablet's, and the row loses its control. A failure leaves «não deu para juntar esta cena — toquem para tentar de novo» on the row and the control offered, and the session is read again so the offer follows the room. There is no line and no sign. Only a session the room has forgotten goes through the Failure policy, as at every door.

## Considered and rejected

- Deriving the offer on the tablet: the takes listing carries spans but no words, and the room is the one that knows whether a rehearsal frase still stands on the part.
- A guard in every gesture of the home: those gestures belong to other slices (ENG-1406, 1420, 1762), and freezing the view is the house pattern of the plan while joining.
- Re-importing on arrival, as her app does: our room lays the frases when the part lands and heals a lay that never committed on the Outbox's resend.
- Refusing the tap while the rehearsal plays: the second tap silences the players first, as her app does.

## Consequences

ENG-1407's «usar este» sits beside the control on the same row, and its swap lands through the room's lay. A team that corrected every laid frase one by one is offered the Bring-back again; taking it keeps their corrections as history. Over an approved draft, a Bring-back makes the draft no longer the approved one, as the Restart does.
