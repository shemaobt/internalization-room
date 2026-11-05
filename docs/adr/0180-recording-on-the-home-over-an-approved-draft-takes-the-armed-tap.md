---
status: accepted
date: 2026-11-05
amends: 0113 (the home's record controls join its Armed tap), 0171 (they are a seventh control that disarms when focus leaves it)
---

# Recording on the home over an approved draft takes the Armed tap

This amends ADRs 0113 and 0171 without editing their decisions; it adds "amended by 0180" to
their status lines. Henok decided on 4 November that the rule is ADR 0113's, and the Definer settled the rest
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
- **Holding an older Outbox row for an armed tap.** Rejected: it is a new Outbox state and a new
  rule, what the tablet tells the team about a take recorded before the approval, and over a part
  the room ignores the flag anyway. It is left to Henok, with the room's own refusal.

## Decision

- **Every record control on the home, on a part's row or the whole passage's, is armed over an
  approved draft**, reading «toquem de novo: isto abre de novo o rascunho aprovado». The first
  tap records nothing. Over a draft not approved it stays one tap and goes up without the flag.
- **The tap decides the flag, and the take's file carries it.** A take goes up with
  `reopens_the_approved_draft` only when its own recording was opened by a confirmed armed tap,
  however late the keep or the send. An approval read while the microphone is open arms nothing
  for that take, and a later armed take that comes back empty leaves the stopped one as it was.
- **A row queued before the approval retries as it is.** Once its take is in the Outbox, an
  approval the tablet reads later arms nothing for it: the row goes up without the flag on its own
  retry, with no tap. This is the one exception to asking the armed tap over a draft the tablet
  holds as approved, and it is the race shema-api ADR 0081 already accepts (an approval minted
  between a keep and its row lands the take without the flag), with a longer window.
- **The confirmation does not cross sessions.** It answers one session's approved draft. A take
  whose session goes, kept already or not, waits for the next session without the flag.
- **The record control is a seventh control that disarms when accessibility focus leaves it**
  (ADR 0171).

## Consequences

- The tablet asks more than her recording screen does: the room keeps a part recorded here, and
  a whole take over the team's own parts, on one tap and ignores the flag. Over a joined
  recording the room refuses a whole take without the flag (ADR 0081).
- A row queued before the approval re-opens the draft with no warning when it is a part or a
  whole take over the team's own parts. Over a joined recording the room refuses its whole take.
- A tablet that has not yet read the approval records a part on one tap and the room re-opens
  the draft. ADR 0113's «the server refuses and the read arms the resend» holds only for the
  whole take over a joined recording; refusing the others would be a new rule of the room's.
