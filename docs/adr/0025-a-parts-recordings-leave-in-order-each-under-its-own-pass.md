# A part's recordings leave in order, each under its own pass

## Context

ADR 0020 let a team record a **Part** again in its own place, and said what it left
behind: two recordings of one part reach the room under one scope, and which of them is
the part is decided there by pass and then by arrival.

Both halves of that sentence had failed.

The **Outbox** walks its manifest in order and steps over a row that did not go — one
inside its backoff window, one whose audio is missing, one the room refused, one that was
never answered. Nothing groups by scope, so the second recording of a part left while the
first was still waiting, the first landed afterwards, and the room kept the recording the
team had abandoned.

The pass was no defence either. It was a count of the whole **Rehearsal**, kept on the
session and written into the **Resume point**, and its only increment lived in a gesture
that was deleted with the per-stretch microphone. Every rehearsal take went up as pass 1,
a part recorded again included, so the room had nothing but arrival to choose by — which
is the same failure said twice.

*Pass* is the room's word, not this glossary's: `pass_number` is the tablet's own count of
its recordings of one part, and the room has always ordered by it.

## Considered Options

Superseding the earlier row when a part is recorded again. Rejected: the recording the
team replaced is history the room keeps on purpose, and a row is what names a recording
here — `takeIdOf` answers by row, so dropping one would leave the stretches of the new
recording addressed to a name that was never minted.

A per-part count of its own on the wire. Rejected: the contract has it. `pass_number` is
already the count of one part's recordings, and the room already orders by number, then by
that count, then by arrival.

Keeping the pass on the outbox row. Rejected: the row says what one upload went up under,
not how many recordings of that part there have been — and the rows a tablet can be left
with are exactly the wrong ones to count from. A manifest that cannot be read is set aside
whole, and a part fetched back from the room has no row at all (ADR 0023), so the tablets
that lost the most would be the ones that read a part's pass as none.

Holding a telling-back behind a waiting one too. Rejected: the rule is about a part, and
the stretches of one telling-back are not two recordings of one thing competing to be it.

## Decision

**The outbox delivers one part's recordings in the order the team made them.** A rehearsal
row that does not land on a pass of the queue holds every later rehearsal row of the same
session and scope for the rest of that pass: they are not tried, spend no attempt and are
not marked. A row that lands holds nothing, so the next recording of that part goes on the
same pass, behind it. A row that is no longer waiting — its budget spent, or written off
with its audio really gone — holds nothing either: it is not ahead of anybody. Rows of
other scopes and every telling-back row go as they always did.

**A part recorded again goes up under the pass after the one that part last went up
with.** The first recording of a part is 1, whatever pass the other parts are on. The pass
is kept with the **Take**, not with the session, and the resume point carries it per take,
so a team that closes the app and comes back records the part again under the next number
and not under one the room already holds. A passage resumed without its recordings
(ADR 0023) takes the pass the room lists for each part, because the room is what knows how
many it is holding. A take that carries no pass of its own — a row written before this
decision, a listing without the field — is read as the first.

The session-wide pass is retired.

## Consequences

The room can tell the recording the team kept from the one they abandoned without knowing
anything about the order the uploads happened to arrive in, which is what ADR 0023 there
already counted on. The outbox rule is the second defence and not the only one: a tablet
whose pass is wrong still delivers a part's recordings in order, and a room that receives
them out of order still reads the passes.

A part recorded again while the first recording of it is still waiting now waits behind it.
The team is never told so — the room has no words (ADR 0014) — and the bead that says there
is something still to send was already the way this is said.

A part held behind an earlier recording of itself does not learn its name until that
recording has left, because the name is adopted from the row the keep flushed and nothing
adopts it again later. A stretch told over that part in the meantime takes the path a
recording the room cannot name already had: the audio goes up as a telling of the whole
passage and the cut counts as a failure, so the room never holds it as a stretch of that
part. An unreachable room reached that path before this decision; a room that refused one
upload now reaches it too, for as long as the ladder makes the team wait.

The pass is a wire fact the room orders by and a tablet fact the row remembers, and the two
can drift: a manifest row still holding an upload the room already stored, a row copied to
another tablet, a part fetched from a room that lists no pass. Each of those reads as the
first recording of its part, which is the reading that never claims a recording is newer
than one the room is holding.

ADR 0020's consequence naming this race is amended to say it was closed here.
