---
status: accepted
date: 2026-11-05
amends: 0113 (the home's record controls join its Armed tap)
---

# Recording on the home over an approved draft takes the Armed tap

This amends ADR 0113 without editing its decision; it adds "amended by 0180" to its status
line. Henok decided on 4 November that the rule is ADR 0113's, and the Definer settled the rest
on the ticket (ENG-2159) on 5 November.

## Context

The hand test of 4 November recorded a part again over an approved draft on one tap, and its
take re-opened the draft with no warning. ADR 0113 armed «regravar a frase N», «usar este», the
grain and the Restart, but not the home's record controls.

## Considered Options

- **The room refuses the take without the flag.** Rejected: shema-api ADR 0081 keeps a part
  recorded on the recording screen on one tap, as hers does, and the room adds no rule to her
  ledger.
- **Arming only «Gravar de novo».** Rejected: a row's first recording over an approved draft
  changes the takes just the same.

## Decision

- **Every record control on the home, on a part's row or the whole passage's, is armed over an
  approved draft**, reading «toquem de novo: isto abre de novo o rascunho aprovado». The first
  tap records nothing. Over a draft not approved it stays one tap and goes up without the flag.
- **The tap decides the flag.** A take goes up with `reopens_the_approved_draft` only when its
  own recording was opened by a confirmed armed tap, however late the keep or the send. An
  approval read while the microphone is open arms nothing for that take.

## Consequences

- The tablet asks more than her recording screen does: the room still keeps these takes on one
  tap and ignores the flag on a part recorded here.
- A tablet that has not yet read the approval records on one tap and the room re-opens the draft.
  ADR 0113's «the server refuses and the read arms the resend» does not hold for these takes;
  refusing them would be a new rule of the room's.
