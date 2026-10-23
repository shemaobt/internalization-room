---
status: accepted
date: 2026-10-22
---

# A store build below the room's minimum shows one screen that sends the team to its store

Henok settled it on 22 October (ENG-1377). ADR 0082 left the tablet knowing nothing of the
server; a tablet two releases behind kept opening against a room that had moved on. The server
now names the **Minimum build** per platform on `/api/version` (the API's ADR 0087), and the
tablet acts on it.

## Decision

- The tablet's own build number is `--dart-define=BUILD_NUMBER`, the `+N` of `pubspec.yaml`, 0
  when absent. A build of 0 is a laptop build and is never below a minimum, and it never reads.
- A build is below the minimum when `0 < build < minimum` for its own platform: iOS reads
  `ios`, Android reads `android`, any other platform has no minimum. Equal is not below.
- It reads `/api/version` with a 20 s budget at launch, on each arrival at the **Choice**, and on
  each resume while on the Choice. Never while a passage is open, so a raised minimum never cuts
  a **Session**: the team meets the screen when it next stands on the Choice. A read in flight
  is joined, not repeated.
- At launch the room waits for the read before opening, so a held session is never landed, and
  spoken, under the screen.
- Below the minimum, the **Update screen** replaces everything, the claim code included, and
  one button opens the app's own store listing through `url_launcher`.
- The fact is one-way within a run: a later failure or a lowered minimum does not lift it. Only
  a new process of a newer build starts clean.
- An answer without `minimum_app`, or a failed read, changes nothing.

## Rejected

- `package_info_plus` and a native channel to read the build: the define is enough.
- A check on every resume: it could cut a **Session**.
- Reading before the first frame behind a spinner: the claim screen and the Choice already wait
  on the network.
- Comparing `x.y.z`: the stores order builds by number.

## Consequences

- Builds made before this one, and every build made without the define, never see the screen.
  The store workflows pass `BUILD_NUMBER` (ENG-1752).
- A raised minimum reaches a team at its next Choice or launch.
- The iOS listing URL carries the app's Apple ID.
- `url_launcher` is a second package outside ADR 0018's list.
