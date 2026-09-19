# The resume row does not expire

## Context

A **Resume point** was dropped when the **Session** it names had been created more than a
day before. A team that parked a passage on a Friday and came back on a Monday found the
**Conversation** again: the row was thrown away, a new session was created for the
passage, and the old one stayed on the server holding every **Take** and every **Stretch**
the team had made, under an id no row named any more. Henok lived it on his simulator on
18/09, and the checked session of P01 is still there.

The server never expires a session. The expiry was one provider read in one branch of the
resume, and nothing else read the date it compared against.

## Considered Options

**Keeping the day.** Rejected by Henok on 19/09: the age of a session says nothing about
whether the team is coming back to it, and the cost of being wrong is the whole passage.

**Lengthening it to a week or a month.** Rejected: it moves the cliff without removing it,
and the row over the cliff is the one that cost the most work.

**Dropping the row when the session is old *and* the room no longer knows it.** Rejected:
the second half is the whole test, and the room already answers it — the 404 path forgets
the row the moment the room says the session is gone (ADR 0023).

## Decision

**A resume row never expires by age.** What drops it are facts about the room or the
passage, never the clock: the room saying it does not know the session or that the
passage is shut, a resume the room failed twice in a row to serve, the **Approval**
closing the passage, and a row created in another language.

`savedAt` stays on the row as the record of when the session was born. Nothing decides
anything by it.

## Consequences

A passage reopened a week later lands at the station its row names, in the session the
team left, exactly as one reopened the same afternoon (ADR 0023).

A row naming a session the server has forgotten costs one answer on the first reopening;
the 404 path then starts the passage clean, as it already did.
