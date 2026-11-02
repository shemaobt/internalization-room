---
status: accepted, amended by 0167 (in part: the reply landing during the 1.4 s line waits for the close)
date: 2026-10-30
amends: 0085 (in part: the way back while «terminei» is in the air), 0058 (in part: the one Station change that keeps the generation)
---

# The way back while «terminei» sends carries the turn to the Conversation

This amends ADRs 0085 and 0058 without editing their decisions; it adds "amended by 0165" to
their status lines. The Definer settled it on the ticket (ENG-1873) on 29 October, and her frozen app wins:
every step of her scene rehearsal screen draws the way back with no `disabled`
(`Rehearsal.tsx:812`, :821, :844, :877), `exitRehearsal` only switches the view
(`page.tsx:439`), and the turn belongs to the page and keeps flying (:675-711).

## Decision

- While «terminei» is in the air, its one look included, the scene screen's way back is lit
  and answers. The tap returns to the Conversation and the turn is not cancelled.
- That way back is the one Station change that does not move the generation: it carries the
  turn in flight and its look to the Canvas, so the answer still lands. Any other way off the
  scene screen drops the turn, as before.
- The held turn id is kept across it, so a later «terminei» on that rehearsal goes under the
  same id (0085's retry rule) and the room never runs the scene twice.
- A reply that lands on the Conversation plays at once, with no send-off line, as after a
  spoken turn, and «Ouvir de novo» replays it. Any other outcome follows the Failure policy
  as any turn on the Conversation does: a refusal rests it at the invite with nothing said,
  and an answer with nothing to play calls a person, as hers does.
- The red microphone does not reopen the screen while the turn flies, as hers refuses
  `openRehearsal` with a turn in flight; once it lands the list reads the rehearsal «enviado».
- The 1.4 s send-off line stays inert (0101): a way back there would move the generation
  under a reply that has already landed and drop it.

## Considered Options

Moving the generation and re-stamping the send's answers. Rejected: every await of the send
checks the generation it began on, and a second notion of who owns an answer is a larger
change than one carried turn.

## Consequences

A Station change no longer always moves the generation. The reply that lands during the
1.4 s line still waits for the screen to close; ENG-1907 owns that line.
