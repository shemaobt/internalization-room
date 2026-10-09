---
status: accepted
date: 2026-10-07
amends: 0053 (the temporary host is named and closed)
---

# The runner reads one interface of the Station's questions and hearings

This amends ADR 0053 without editing its decision; it adds "amended by 0069" to its status
line. The Definer settled the name on 7 October (ENG-1477).

## Context

ADR 0053 left the runner a temporary host: the notifier's own methods, still asked or told
what the Station knows. Slices 1c-1 to 1c-5b moved every effect out of it, and ADR 0066
moved the last small ones; what is left holds no effect to execute. It was still called
EffectHost, and its doc comment still said "Temporary".

## Decision

The interface is **StationHost**. It has four kinds of member and no other: the questions the
runner asks the Station (what is wanted, reachable or in course, and the session), the
hearings (what the runner heard back and tells the Station to take in), `answer` and
`answerWhereAsked` (what it brings back to the machine) and `handOver`, the one lifecycle
hand-off (ADR 0066). No member executes an effect or is named for one. The hearings whose
bodies do Station work in the notifier stay hearings, as ADR 0066 decided.

The questions stay on it. The session and the failure context are asked of the Station
because the machine does not know them; teaching the machine the session is a slice of its
own (ADR 0059).

The test double is **AStationHost**, after the house's `ARoomPort`; it implements only this
interface.

## Considered Options

- Delete the questions by teaching the machine the session: rejected, ADR 0059.
- A port for the Station: rejected. A port is a door to the world outside the app; the Station
  is the notifier's own role.
- Keep the name EffectHost: rejected, it names what the interface no longer does.

## Consequences

- ENG-1444's guard list, the eleven doors still waiting to move, is what remains of the
  temporary; the per-Station tickets move them.
- A new member that executes an effect has no place on the interface: it is a port method.
