# The stored row wins at every door

## Context

A **Resume point** was read only at the doors the **Wheel** opens. The tablet looked the
row up when the passage was one the wheel had already said had work waiting, and only
when it was asking for the **Session** itself.

Two doors are neither. Asking for the **Panorama** is a request and not an instruction:
the room answers with a passage and with a session it has already opened, and the tablet
enters that passage through `opened`. It happens on the first launch of a book, from the
**Invitation**, and again from the panorama's own spoke on the wheel. At the invitation
the list of started passages has not been read yet, so it is empty whatever the ledger
holds; at the spoke the list is filled and the entry was skipped anyway, because a
session the room handed over was taken as the session to enter.

So a team coming back to a book landed at the **Conversation** of a passage it had
already told back, in a session minted a second ago, and the row naming the session
holding every **Take** and every **Stretch** was overwritten with the new id. That is the
loss ADR 0031 closed at the wheel's door, arriving through the two doors it did not
cover.

## Considered Options

**Filling the started list before the invitation.** Rejected: it puts a second reader of
the ledger at a door that has no wheel behind it, to answer a question one read of the
row answers directly.

**Preferring the room's session when the row stopped at the conversation.** Rejected: the
row is the fact and the station is detail. A passage left in its conversation is still
that team's work in that session, and the server is still holding it.

**Telling the server to close the session it opened for nothing.** Rejected: there is no
route for it, and a session nobody entered is the server's to tidy. The tablet's business
is to land the team where it stopped.

## Decision

**A passage's Resume point is honoured at every door into the passage**, including a door
the room opened before the tablet knew which passage it was. When the row is there and
its language is this run's, the tablet enters the row's session, at the station the row
names, and the session the room minted is simply not entered and is named by nothing.
When there is no row, the session the room opened is entered as it came back and the row
is written naming it, as it always was.

The `fresh` entry still skips the row — it is how the 404 path starts over — and a fresh
entry through the wheel still costs no read at all.

## Consequences

The first launch of a book whose passage the room answers with lands the team in the
**Back-translation** it left, with its parts under it, rather than at a conversation it
already finished.

One session per launch can be opened for nothing, on a tablet that had a row to keep. It
carries no take, no stretch and no turn, and nothing on the tablet points at it.

Two, when the room then says it does not know the session the row names: the single clean
retry re-enters without the room's answer, so it opens one of its own and the first is
left where it stood. Measured at this door — the room mints two sessions and is spoken to
only in the second, and the row ends naming that one.

A passage whose parts are not on this tablet fetches the room's own parts for the row's
session (ADR 0023), never for the one just minted.
