---
status: accepted
date: 2026-10-28
amends: 0106 (in part: over a forced version the approve button stands beside the badge), 0136 (in part: the recording home offers the approval over a forced version too)
---

# A forced approval is offered again once the telling is conferida

The server half is ADR 0101 of the API (ENG-1837): the Session read's `approved` says whether
the version was `forced`, and an approval over a forced version with no blocker standing mints
the next version, not forced.

## Context

Marcia's approve gate hides «Aprovar como rascunho final» once a release exists, with one
exception: when the current release was forced and the telling is now conferida, the button is
offered again, and her finalize mints the next version (`src/draft/approveGate.ts`,
`app/api/draft/finalize/route.ts`, at 18fa7c4). Otherwise the draft stays forced for ever over a
passage the team did check. The room hid the button over any approved draft, forced or not.

## Decision

- **The approved draft carries `forced`**, read from the Session read, and false when the room
  does not say it.
- **Over a forced version the approval stays open.** The recording home offers it when the room
  calls the passage checked, and the Back-translation draws the approve button beside the badge
  at its checked phase, which only the room's clean verdict or its read of `checked` enters. The
  badge, the listeners and «Checagem externa» stay as they were, as her badge stays beside her
  button. A version nobody forced never offers the button again.
- **The press is the approval it always was.** The room mints the next version, the Saved screen
  shows it, and the read after it brings a version nobody forced, so the button goes.
- **An answer naming the forced version itself approved nothing.** The room keeps a forced version
  while a blocker still stands over its takes and names no blocker. The tablet reads that answer
  as a body that says neither a version nor a refusal: no Saved screen and no approved line, and
  her «não deu para conferir agora — tentem de novo», on the Back-translation back before
  «terminei» as for any such body.

## Consequences

- The next version starts its Checagem externa with no listeners; the forced version's listeners
  stay with it.
- A forced version answered with a blocker standing leads the team to no hole, because the room
  does not name one there. The tablet says only that it could not check.
