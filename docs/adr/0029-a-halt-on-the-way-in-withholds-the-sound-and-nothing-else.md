# A halt on the way in withholds the sound and nothing else

## Context

ADR 0027 made entering the **Back-translation** measure the whole rehearsal before a part
plays, which means the way in now waits on the player every time. A **Halt** can land
inside that wait: the server's own, read as a reopening picks the telling-back up, or any
other the room raises while it is measuring.

A halt either blocks, and then only the Desk lifts it (ADR 0009). The room says so once —
the call for a person is spoken on the way into the halt and not repeated; what repeats is
the asking of the server, not the line.

Putting a part in the air silences the room first, by design (ADR 0024). Done at the end of
a halted entry, it cut off that one line, and the team was left with a rehearsal playing
under a room nobody had attended.

## Considered Options

**Letting the entry finish as usual and accepting the cut line.** Rejected: the line is the
only thing a wordless room (ADR 0014) has to say that a person is needed.

**Abandoning the entry at the halt — no ruler, no choice of part, no ledger.** Rejected,
and measured: the finish would then be refused for parts the team had already heard in an
earlier round, because nothing of them would be written into the **Listening ledger**; and
the team would land back on the rehearsal's first part instead of the first with untold
ground.

**Leaving the part to the team's own listening gesture after the lift.** Rejected after
building it. It leaves the room standing in the telling-back with no clip at all, and every
gesture that needs one passes its guards over silence — the scissors above all, which
would mint a **Stretch** over a part nothing had played. It also made the fact that the
entry stopped short something only that one gesture knew.

## Decision

**A halt met on the way in withholds the sound, and nothing else.** The entry still
measures every part, still publishes the whole **Ruler**, still steps over the parts told
whole and writes them into the ledger, and still chooses which part would go in the air. It
then stops short of playing it, and remembers which part it had chosen.

**Lifting the halt finishes the entry.** Where the room learns the desk has attended, the
part the entry chose goes in the air. After the lift the room is exactly what an unhalted
entry leaves behind, so no gesture has to know that a halt happened, and none of them meets
a telling-back without a clip.

## Consequences

The room is never in the telling-back with a drawn cord and no part in the air for longer
than the halt itself, and while the halt stands every gesture that could act over silence
is already refused by its own guard on the halt.

Which part the entry chose is remembered between the halt and the lift. It is a latch with
no home in the session state, like the one the landing on an unheard part keeps, and it is
released by the part going in the air and by the passage being forgotten.

A halt raised while the player is measuring also keeps the room's voice: leaving the wait
returns the room to the invitation only if it is still thinking. The invitation put back
over a halt let a team reopening into a room the server had already stopped straight back
in, against ADR 0009. That path was reachable before ADR 0027 and was taken whenever the
measuring happened to wait; making the wait unconditional made it the ordinary case.
