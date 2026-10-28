---
status: accepted
date: 2026-10-28
amends: 0062 (in part: the pause that held a kept take across a leave), 0139 (in part: the pointer that deferred its removal)
---

# A leave holds no take, and the way back brings none back

This amends ADR 0062 and ADR 0139 without editing their decisions: it adds "amended by 0142" to
their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the
ticket (ENG-1940).

## Context

ADR 0062 said the leave paused a kept take and the way back laid it down again, paused where it was.
ADR 0139 took the ≡ off the recording step, so `leaveThePassage` is tapped only on the Conversation
and the Panorama, where no take is ever held. Its Consequences said the held take was reached by
nothing and left its removal to a follow-up.

- `page.tsx:407`: her `openPicker` pauses the players and opens the menu. Nothing is held for later.
- `page.tsx:413`: her `exitDrafting` returns to the canvas and holds nothing either.

## Decision

- **A leave holds no take.** ADR 0062's clause «The pause holds a kept take only, and only while the
  chevron can return: the take comes back paused where it was» no longer holds. The way back enters
  the passage through the resume and nothing else.
- **The rest of that bullet stands.** A facilitator reply that is playing is still stopped, stays
  unheard, and the hand offers it again.
- **ADR 0139's pointer is closed.** The held take it said nothing reaches is gone from the code.

## Consequences

- `LeftEntry` no longer carries a take, and nothing between the leave and the way back lays one down.
- `TheHeldPartReturns` stays: the Back-translation's pause nudge lays the part it took off the player
  back down with it. That nudge never crossed a leave.
- Nothing stored changes; the way back still lives in memory and dies with the launch.
