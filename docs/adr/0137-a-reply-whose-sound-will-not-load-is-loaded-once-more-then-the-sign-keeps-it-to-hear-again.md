---
status: accepted
date: 2026-10-23
amends: 0049, 0063, 0093, 0097
---

# A reply whose sound will not load is loaded once more, then the sign keeps it to hear again

This amends ADRs 0049, 0063, 0093 and 0097 without editing their decisions; it adds
"amended by 0137" to their status lines. The Definer settled the rule on the ticket
(ENG-1370, Definition of 22 October); the Orchestrator and Jonatas ruled the open points on 23 October.

## Context

Marcia's app loads a reply's clip once more 1.5 s after it fails, then shows the person sign
with replay ready for that reply. Ours never loaded a reply again: a clip download that
failed took the room's network-failed path, and the sign came from two failed Guide lines in
a row, across replies. «Ouvir de novo» never gave back a fail-safe line, nor the reply whose
sound failed.

## Decision

- **A reply whose sound fails to load is loaded once more about 1.5 s later**, from a fresh
  download. A failed load is the clip not coming down, the room refusing it or the player
  refusing it; a line cut by the team or dropped unsaid is not one. A reply is every line
  the Guide answers with: a turn's, the Panorama's, the verdict's, and a line said again.
- **The second failed load of one reply raises the person sign** (her case 4: one reply,
  two loads), decided by the failure policy, and the reply stays the one «Ouvir de novo»
  says. Nothing is counted across replies, and no other Guide line counts: it leaves
  silence. A clip load never decides a network failure or gives a turn up.
- **An Opening's second failed load lets the Opening go**, as every other Opening failure
  does (ADR 0063): the quiet invite, with no sign.
- **«Ouvir de novo» says the last reply as it was meant**, a fail-safe line included. As in
  her app, it is not offered under the sign; it is lit once the team's tap clears it.

## Considered Options

**«Ouvir de novo» lit over the sign.** Rejected (Jonatas, 23 October: as in her app): her
replay waits for the sign to clear, and the sign takes every tap.

## Consequences

- A reply that will not sound costs the team about 1.5 s before anything else happens.
- The Opening's clip that fails is fetched twice before the room rests.
