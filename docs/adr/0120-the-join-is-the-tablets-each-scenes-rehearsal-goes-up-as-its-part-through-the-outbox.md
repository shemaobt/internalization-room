---
status: accepted
date: 2026-10-23
extends: 0087
---

# The join is the tablet's: each scene's rehearsal goes up as its part through the Outbox, under the rehearsal's fingerprint

The Definer settled the rules on ENG-1385 (Definition of 22 October; answers Q34–Q37 of 23 October).

## Context

«juntar as cenas e ouvir» on the Ensaio Final plan turns each scene's chosen rehearsal into that scene's Part. Her app does it with one server route per scene. Our keep door already takes `origin`, refuses an origin that is no live rehearsal of the passage, refuses bytes that are not the fingerprint sent (api ADR 0072), answers the take it already holds for the same bytes, and stamps a joined part with the server's clock. The room now lists each scene rehearsal's sha256.

## Decision

- The tablet joins, one scene at a time in passage order: the scenes with no part whose chosen rehearsal is Joinable. «juntando a cena {i} de {k}…» stands while a scene is joined; a landed row gets «✓».
- The part is the rehearsal's bytes: this tablet's file when its sha256 is the rehearsal's, else its audio door's. It goes up as an Outbox row (`ensaio`, `parte-N`, chunk N) with `origin` and the rehearsal's fingerprint, so the room refuses any other bytes. Nothing of the rehearsal is touched.
- The part is kept under a file of its own (`parte-N-junta-<id>`), so the Listening ledger starts it unheard.
- A join row sends the moment of each try as its Recording time; the room keeps its own clock for a joined part and reads ours only as the offset.
- The part goes up one pass above the highest the room lists for it when its row is written.
- Her windows over our Outbox: a request of the row's own with no answer for 70 s is given up, timed from when that request goes out, never while rows ahead of it are still sending; a "wait" (an answer the house reads as a network failure) is resent quietly every 5 s for at least 90 s. Either way, and on any other refusal, the row says «não deu para juntar esta cena — toquem para tentar de novo» and the loop stops; its tap continues from the plan as it is. A refusal naming the rehearsal as no part of the passage, a fingerprint that differs, or a recording gone from the room says «este ensaio não pode entrar» and the loop goes on.
- A row given up for no answer stays in the Outbox and lands by itself (0087).
- A row refused for good leaves the Outbox with its part, so it never comes back over the rehearsal the team chose next.
- The room answers the take it already holds for the same bytes. When that take is not the scene's current part (the part was recorded again by hand meanwhile), on this try or on a landing in the background, the join claims nothing: no «✓», the part and its file leave the tablet, and the plan closes to the recording home, where the current part stands.
- The join loop lives in the notifier, not in the machine, as the plan's own steps do (0117, 0118): an exception to AGENTS.md «The room's core» until the plan moves to the machine.
- A drop mid-join recovers from the room's listing and the Outbox: a resume at the Canvas restores no takes, so writing each part to the Resume point only puts its file under the session's forgetting. A part counts as joined only when the room lists it as the scene's current part, never because its row left the Outbox. The orange dot opens the plan again while every take so far came from a join and a scene is left to join; otherwise the recording home.
- A scene recorded again by hand takes back any join of it still in the Outbox, so the team's newer take stays the part.
- A join that ends without stopping closes the plan to the recording home, holding every part; nothing starts playing there (ENG-1408's).
- Nothing flags the reopening of an approved draft yet: the plan only opens over no take or joined parts, and the room refuses an unflagged join over an approved draft. The Outbox row carries the flag, for the armed tap to set.

## Considered and rejected

- Her one-route-per-scene join on the server: the Definition puts the join on the tablet, and the keep door already holds every rule.
- Writing every row up front and letting the Outbox drain: no «juntando a cena i de k», and no stop on a failed row.
- Keeping the part as the rehearsal's own file: a listen on the plan would count for the part.
- A server refusal when the bytes differ from the origin's: the fingerprint already refuses them.
- The rehearsal file's modification time as the Recording time: it reads as a clock offset of hours.
- A server refusal of a join over a part another tablet recorded by hand: the join lands at the next pass, and ENG-1760's order picks the part.

## Consequences

ENG-1405 lays frases on these rows' landing; ENG-1407's «usar este» writes the same kind of row over a part; ENG-1408 starts its first listen on the home the join lands on. An older server, with no sha256 on its listing, gets the bytes' own hash as the fingerprint and so cannot refuse a different file.
