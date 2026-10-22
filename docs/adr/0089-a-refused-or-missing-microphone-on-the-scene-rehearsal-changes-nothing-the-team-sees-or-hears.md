---
status: accepted, amended by 0108
date: 2026-10-16
amends: 0083
---

# A refused or missing microphone on the scene rehearsal changes nothing the team sees or hears

## Context

On the scene-rehearsal screen of her app (Rehearsal.tsx:420, :458 at 18fa7c4) a refused
permission or a microphone that fails to open sends the record circle back to rest, with no
message. In her answers of 1 October she kept those silent failures as built. Ours covered the
whole room with the full-screen microphone gate, spoke its line, and counted a failed start
towards calling a person, whatever the Station.

## Decision

1. On the **Scene rehearsal**, a refused or failed opening of its **Microphone** only gives
   the **Channel** back. It records no refusal of the permission, does not count towards a
   **Call for a person**, and does not reset the Conversation's count; nor does a scene start
   that opens, as the count belongs to the Conversation's circle. The **Microphone
   answer** carries the owner of the start it answers, and the rule reads that owner, not the
   Channel or the Station when the answer arrives: a start the team closed with a second tap,
   or that a halt discarded, still answers as the scene's.
2. The permission check on return to the app neither covers the Scene rehearsal with the
   gate nor speaks its line there. Leaving the Station with the permission refused shows the
   gate on the Canvas.
3. The Canvas keeps its own rule: a refusal gates and speaks, and two failed starts in a row
   call a person. The Rehearsal and the Back-translation keep the gate.

## Considered options

- **The shared gate on every Station.** Discarded: it changes what the team sees during a
  scene rehearsal, which her app does not.
- **A person count per Station.** Discarded: her screen counts nothing, so a count of its own
  would still bring a person in where she brings none.

## Consequences

A team whose permission is refused for good sees the scene rehearsal exactly as it was and
can tap the circle as often as it likes: nothing is said, nothing is recorded, and the Desk
gets no call. The permission check on return still learns the refusal, so the way back lands
on the Canvas's gate and its line. Every Microphone answer now carries its owner, and a rule
that belongs to one Station reads that owner rather than the Channel at the moment the
answer arrives.
