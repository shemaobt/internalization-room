# A halt the tablet only read is not a new call for a person

## Context

`_haltForAPerson` already tells apart a halt this tablet can reach the server about
(`reachable`) from one it cannot (ADR 0029's broken build, and a session already gone).
It did not yet tell apart a halt this tablet only *read* from one it decided on its own.
Three doors read a halt the server already holds: the halt watch's own poll finding a
warning turned blocking, the pull after a turn lands, and the resume that picks a landed
passage back up. All three entered the halt the same way a room-decided one does — the
fixed line, the voice, and a **Call for a person** sent unawaited.

That call is fire-and-forget on the tablet, but not on the server: `askForAPerson`'s
route wipes the **Desk**'s attend stamps, on the reasoning that a fresh ask is an ask
nobody has attended yet (rejected below as a fix). A halt this tablet only read is one
the Desk was already told about by whatever raised it — the room's own decision earlier,
or the retells budget's warning. Calling again told the server nothing it did not know,
and could land after an attend that had already happened, undoing it and stranding the
team in front of a session the Desk believed it had cleared.

## Considered Options

**Making the server's route idempotent on the attend stamps.** Rejected: the wipe is a
deliberate rule with its own test on the server — "a new ask is an unattended ask" — and
changing it there would blur the one signal the Desk has for "somebody is still calling".

**Keeping the call as a harmless duplicate.** Rejected: it is not harmless. It wipes the
Desk's attend and can strand a room that the Desk had already cleared for a full beat of
the watch, or longer if the attend is the last one the Desk means to give.

## Decision

**A halt the tablet only read is entered and watched, never called in.** The three read
doors enter through `_haltForAPerson` with a parameter that says the halt was read: the
fixed line plays once, the voice and `_leaveThinking` run exactly as for any other halt,
but no `askForAPerson` is sent and the watch is armed at once, whether or not a call was
ever asked for. `_personAsked` stays false, so nothing insists and `_leaveTheHalt` clears
it as it always did. The call belongs to the room's own decisions — every site enumerated
in ENG-962 keeps calling exactly as before, including the 404 re-entry and the refusal
doors, and a warning still arms the watch and calls nobody (ADR 0032).

## Consequences

The watch being armed at entry, not only once a call lands, closes the race the ticket
named: an attend that lands in the window a read-door halt used to spend on its own call
is never wiped, because there is no call to land late. The long press keeps its meaning
(ADR 0009): a read halt is watched like any other, so `resolveWithPerson` asks the server
now instead of releasing locally.

This generalises ADR 0032's rule — the tablet is silent over a warning — to every read of
a blocking halt: the tablet only calls for what it decided, never for what it merely
heard.
