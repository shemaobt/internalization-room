---
status: accepted, amended by 0168 (the verdict is loaded once and writes her line when it will not sound)
date: 2026-10-23
amends: 0049, 0063, 0093, 0097
---

# A reply whose sound will not load is loaded once more, then the sign keeps it to hear again

This amends ADRs 0049, 0063, 0093 and 0097 without editing their decisions; it adds
"amended by 0152" to their status lines. The Definer settled the rule on the ticket
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
- **Except a retro verdict the room could not compose**, which is not kept, so «Ouvir de
  novo» says the line before it. This is an older rule of ours (3 September), not her
  app's: her `speak` keeps every clip with no exception for a fail-safe. ENG-1880 made
  every other fail-safe line kept and left this one in place, and this ADR keeps it rather
  than reverse it unasked. Under the sign, such a verdict does not take the place of the
  line before it either.

- **While the reload waits, the room is thinking** («pensando»), as it already is for a
  turn's reply, so nothing offers to say the reply again: a second «Ouvir de novo» in the
  wait would play it alongside the reload, which then deletes the file it plays.

- **The reload answers the waiting reply by callback, an exception to the rule that every
  answer returns as an event stamped with the generation.** The gesture that said the reply
  (a turn, the Panorama, the verdict, a line said again) awaits the reload's answer. The
  repo already resolves a stamped line event to its gesture through the line's saying, the
  completer kept for each Line and answered from the machine's last line outcome. The reload
  cannot ride it without bending three things. A readying that fails has no Line yet: the
  reply never reached the machine, so a Line that never sounds would be minted only as a
  key. The answer is "load again or not", so a line's outcome (said, failed, unsaid, cut)
  would be read as load again. And a stale due event is dropped by the reducer, so the
  saying would never end unless the machine held the waiting reply as state of its own and
  answered it on every path that ends it: the halt, a step left, leaving the passage, the
  notifier disposed, and a generation moved, which happens outside the dispatch that
  answers sayings. That is about 150 lines across the machine, the runner, the notifier and
  the generator. So the failed load carries its answer with it, the effect runner stamps
  the 1.5 s wait with the generation, and an abandoned or replaced wait answers "do not
  load again".
- **The failed load is never stale, by discipline, not by type.** It is told under the
  generation it happened in because the notifier dispatches it synchronously right after
  checking that the generation was not abandoned. The event carries no generation, so
  nothing but that order keeps it fresh; the machine then answers it exactly once.

## Considered Options

**The reload answered through the line's saying, by a stamped due event.** Rejected: see
the exception above. It needs a Line minted as a key, a line outcome read as "load again",
and the waiting reply kept and answered by the machine on every ending path.

**«Ouvir de novo» lit over the sign.** Rejected (Jonatas, 23 October: as in her app): her
replay waits for the sign to clear, and the sign takes every tap.

## Consequences

- A reply that will not sound costs the team about 1.5 s before anything else happens.
- The Opening's clip that fails is fetched twice before the room rests.
