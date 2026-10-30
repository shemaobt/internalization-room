---
status: accepted
date: 2026-10-30
amends: 0113 (in part: the «tentar de novo» of a held sentence over a frase that awaits)
---

# A held sentence whose frase awaits opens its review on retry, and never re-sends by itself

This amends ADR 0113 without editing its decision; it adds "amended by 0168" to its status
line. Her frozen app wins (ENG-2102): the retry of a held recording whose frase now awaits
another computer's sentence never re-sends by itself. Hers reaches that through the clip's
stamp — the landing moves it, the retry's POST answers `moved`, and `rereadAction`
(`app/lib/sentenceRerecord.ts:115-119`) answers `review` for a frase that awaits, so
`Drafting.tsx:1899` opens the review and lays nothing.

## Context

A sentence the room could not take stays held on its row, and the row's line sends it again
on a tap (ADR 0113, the DRAFT_APPROVED case included). When another computer's sentence
landed on the same frase meanwhile, the read reported the frase awaiting its translation and
the tap still went to the room, which laid the held recording over the landed one before
anyone had heard either in its place. Our room keeps no clip stamp, so the tablet cannot
learn from the room's answer that the frase moved under the held recording.

## Decision

- A «tentar de novo» on a held sentence whose stretch is the one awaiting its translation
  opens the review a fresh recording gets — hear it, «gravar de novo», «usar esta» — with the
  held file as its recording, and sends nothing. The tablet's own knowledge of the frase that
  awaits stands in for her clip stamp.
- «usar esta» sends that same recording once, under the id it was held by. «gravar de novo»
  takes it off the tablet and the circle records over it. Closing the review holds it again,
  as before.
- Over an approved draft the line still arms first (0113); the confirmed tap opens the review
  carrying the reopening, so its «usar esta» goes up with `reopens_the_approved_draft`, the way
  «regravar a frase N» carries it into the review of a fresh recording.
- A held sentence on any other frase still goes up on the tap. When another frase awaits, the
  room refuses it with ANOTHER_SENTENCE_AWAITS and the voice opens the frase that awaits, as
  before.

## Considered Options

Reading the session before deciding on the tap. Rejected: the entry read and every refusal
already report the frase that awaits, and hers decides after the room's answer only because
it has a stamp to compare.

## Consequences

When this tablet itself re-recorded the awaiting frase and that send failed, hers lets the
retry through, because the stamp is current; here the review opens there too, and the team
taps «usar esta» once more. Nothing is laid unheard either way.
