---
status: accepted, amended by 0168, 0171
date: 2026-10-23
amends: 0100 (the Restart's arm is now the Armed tap's)
---

# A change over an approved draft takes the Armed tap, and its Back-translation shows the Checagem externa

Her app at Tripod-Internalization 18fa7c4 is the bar (`ensaioFinal.ts` armed taps,
`sentenceRerecord.ts` `rerecordOffer`, `Drafting.tsx` home and `enterExt`, `strings.ts`). The
server half is shema-api ADR 0081: over an approved draft it refuses a re-recorded sentence, a
join, a swap and a whole take over a joined recording with `DRAFT_APPROVED` unless the request
says the team armed the tap (`reopens_the_approved_draft`).

## Context

The only control that asked a second tap was «recomeçar a tradução», with its own arm. Over an
approved draft, «regravar a frase N» was one tap, offered at conferida only on the frase the
verdict's nuance named, so a team could undo the version outside listeners would hear without
ever being told. The Back-translation of an approved draft showed the version and nothing
leading to the Checagem externa.

## Considered Options

- **A second arm state beside the Restart's.** Rejected: her rule is one armed control at a
  time (`armId`, `ensaioFinal.ts`), and the controls of the join, the swap, the whole take and
  the bring-back would each add another.
- **Arming at «usar esta» instead of at «regravar a frase N».** Rejected: her `rerecordOffer`
  arms the row's start over a finalized draft, so the team decides before it records.
- **Clearing the approval locally after a re-open.** Rejected: ADR 0106, only a Session read
  sets or clears it; the tablet reads the session once the sentence is laid in.
- **Showing «checagem externa: 0 ouvintes».** Rejected: her home draws the count only when it
  is not zero.

## Decision

- **One Armed tap for every control.** One control is armed at a time. The first tap arms it,
  a second tap counts only from 0.6 to 6 seconds after, and then it disarms by itself. Arming
  one control disarms the other, and any other gesture of the team disarms it too: every
  gesture takes the arm off the screen as it starts, and only a tap on the armed control itself
  finds it there. The Restart is one of its controls and keeps its own armed text,
  «toque de novo para apagar as {n} frases traduzidas», over an approved draft as well.
- **Over an approved draft, «regravar a frase N» is offered on every re-recordable frase and
  is armed**, reading «toquem de novo: isto abre de novo o rascunho aprovado». The sentence of a
  confirmed tap goes up with `reopens_the_approved_draft`; once it is laid in, the tablet reads
  the session, so the approval leaves with the server's answer. Over a draft not approved it
  stays one tap and goes up without the flag.
- **A `DRAFT_APPROVED` refusal keeps the sentence and reads the session.** The row offers
  «tentar de novo», armed over the approved draft the read now reports. No sign and no spoken
  line: it is a step the team answers with the armed tap.
- **The Back-translation of an approved draft shows, under the approval, the outside listeners'
  count** when it is not zero (from the session read's `approved.listeners`, 0 until listeners
  are kept), **and the «Checagem externa» button.** No facilitator code is asked. The button is
  closed while the microphone is open. Until the Station exists, a tap asks one Session read:
  a failure reads «não deu para abrir a checagem externa — tentem de novo»; a draft the room no
  longer holds as approved reads «a checagem externa abre depois que o rascunho final é
  aprovado», and the approval and the button leave with that read.

## Consequences

- The controls still to come over an approved draft (the join, the swap, the whole take, the
  bring-back) use the same gesture and add no rule of their own.
- A tablet that does not yet know the draft is approved sends without the flag; the server
  refuses and the read arms the resend, so a stale approval costs the team one tap, never the
  version.
- The scene rehearsal's own «recomeçar a tradução» keeps its own arm: it is another screen.
