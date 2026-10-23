---
status: accepted
date: 2026-10-23
extends: 0102, 0120
---

# The Rehearsal swap lays a scene rehearsal in as the part's next pass, and keeps the take it replaces

The Definer settled the rules on ENG-1407 (Definition of 22 October; answers Q38–Q43 of 23 October). After the join the team must be able to hear which rehearsal stands in each scene and put another one in its place, without losing the take it had and without an old take slipping back into the passage they approve.

## Decision

- Every Scene row with a take shows «✓» (her `done-tick`). A row whose part came from a join offers «trocar o ensaio desta cena» when another Joinable rehearsal of its scene exists; a row with no joined part offers «usar o ensaio desta cena» when one exists. Neither shows while the row's take is unsent or a recording is open, nor on the whole passage's home (0134), which has no Scene rows. Both open the scene's Rehearsal sheet over the home, read from the scene-rehearsal listing the home asks for on each arrival.
- On the home the sheet's «usar este» is the Rehearsal swap: that rehearsal's bytes go up through the Outbox as the part's next pass, with `origin` and the rehearsal's fingerprint, under a file of the part's own named for that pass. The part is replaced in place only once the room names the take, exactly as a record-again replaces it: the stretches told over the old take leave the check as history, and the part starts unheard.
- The swap takes the Armed tap over an approved draft, with her «toquem de novo: isto abre de novo o rascunho aprovado», and over a take already standing under the scene, with «usar este» dimmed until it wakes. A row with no part swaps on one tap.
- A swap that cannot land changes nothing but its sheet line: «este ensaio não pode entrar — ensaiem esta cena de novo» when the room or the door says the rehearsal cannot be the part, else «não deu para juntar esta cena — toquem para tentar de novo» within the join's windows. Its row leaves the Outbox and its file is deleted; a refusal also re-reads the session, so a draft approved meanwhile arms the next tap.
- «ouçam a cena nova antes de conferir» stands under the rows from a landed swap until the team taps the advance disc, and is not kept across a relaunch.
- While a swap runs nothing else on the home starts.
- A swap decides only once the request in the air has answered. Given up after 70 s, its row leaves the Outbox at that answer, before anything sends it again; a row the room took then becomes the part as the room holds it, with the same «ouçam a cena nova antes de conferir»: the tablet follows the room rather than show a part the room no longer counts.
- Each arrival at the recording home settles the swaps left behind (a relaunch or a leave between the row's writing and its landing): it sends what the Outbox still holds above a part, then a part whose current take in the room came from a scene rehearsal at a higher pass becomes that take, with «ouçam a cena nova antes de conferir».
- The swap lives in the notifier, not in the machine, as the join it reuses does (0120): an exception to AGENTS.md «The room's core» until the plan's steps move to the machine.
- Nothing is deleted: the replaced take stays on the tablet and in the room as an earlier take under that number. A → B → A is three takes (api ADR 0095).

## Considered and rejected

- Replacing the part before the row lands, as the join does: a refused or lost swap would leave the tablet on a part the room does not hold. Her swap is answered before the screen changes.
- Leaving a swap that did not answer in the Outbox to land later, as the join does (0120): it would change the part under the team's feet minutes later.
- Reusing the join's file name `parte-N-junta-<id>`: a swap back would reuse the earlier file, and the Listening ledger would count its old listening.
- «ensaio {n}» on the home row: her home shows only «✓», and which rehearsal is in shows as «✓ em uso» in the sheet (Q39).
- A second arm state: one armed control at a time (0113).

## Consequences

- Two tablets swapping one scene to two rehearsals both land, at their own passes; the room's order picks the part, and each tablet sees it at its next resume.
