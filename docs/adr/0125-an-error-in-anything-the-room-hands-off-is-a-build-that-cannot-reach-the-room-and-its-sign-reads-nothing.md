---
status: accepted, amended by 0145
date: 2026-10-22
amends: 0093, 0107
---

# An Error in anything the room hands off is a build that cannot reach the room, and its sign reads nothing

This amends ADRs 0093 and 0107 without editing their decisions: it adds "amended by 0125"
to their status lines. The Definer settled the rules on ENG-1755 (Definition of 22 October).

## Context

A tablet built without the room's address never showed the person sign. The build guard
raised the halt, but an unlinked tablet drew the claim-code screen, whose thinking circle
never ends, and never the stack that holds the sign. Had it drawn the room, the Wheel read
would have thrown `Env`'s `StateError`, which every hand-off dropped, and the Choice would
have thought until the busy watchdog let the step go. ADR 0093 says such a build shows the
sign and calls nobody.

## Decision

- **A broken build draws the room, never the claim code.** It shows the Choice beneath the
  person sign, and the build guard raises the sign after the first frame. It never links,
  so nothing is asked of the room.
- **An `Error` in a hand-off is `TheBuildCannotReachTheRoom`.** Both hand-off seams report
  it once to the operator's log and raise the sign, which calls nobody. The gesture awaited
  directly completes instead of rethrowing it. An `Exception`, and so every room result,
  keeps the failure policy's own path.
- **An `Error` from a hand-off the team has moved past still raises the sign.** It is a
  defect, not a room answer, so the generation guard, which is for answers, does not drop
  it. An `Error` that lands after its Life ended, disposed or linked anew, raises nothing.
- **A sign raised without a call calls nobody, and its tap reads nothing.** The team's
  tap clears it to the Choice as it stands; it neither reads the Wheel nor enters a
  passage. A raise that calls for a person over it, or a read that says a person is
  needed, is a real case beneath, and its tap goes on as for any halt.

## Considered Options

**Map only `StateError`.** Rejected: the ticket says `Error`, and any `Error` in a hand-off
is a defect that otherwise leaves the room thinking for 330 s.

**Map everything thrown.** Rejected: an ordinary `Exception` would raise the sign; it keeps
the policy's own path.

**Let the tap on the build guard's sign read the Wheel again.** Rejected: on a broken build
that read throws again, so the tap would only bring the sign back, and the glossary says
the build guard has nothing to read.

**Give the claim-code screen a sign of its own.** Rejected: the tap must land on the Choice.

## Amends

- 0093: a build that can reach no room is now any `Error` in a hand-off, not only the
  guard at launch.
- 0107: the tap on a sign that calls nobody takes no held hand-off. Its consequence
  «the build guard's tap reads the Wheel» no longer holds, and a broken build shows the room.

## Consequences

- A programming `Error` in any hand-off now shows the sign and calls nobody, instead of a
  silent stall.
- A broken build never shows the claim code.
- The Desk sees nothing of a broken build.
- On a working build, a tap on a sign an `Error` raised mid-passage does not re-enter the
  passage; the team goes on from the station as it stands.
