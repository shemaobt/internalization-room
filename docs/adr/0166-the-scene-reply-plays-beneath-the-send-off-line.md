---
status: accepted
date: 2026-10-30
amends: 0101 (in part: where the reply plays), 0165 (in part: the send-off line stays inert)
---

# The scene reply plays beneath the send-off line

This amends ADR 0101 without editing its decision; it adds "amended by 0166" to its status
line. The Definer settled it on the ticket (ENG-1907) on 29 October, and her frozen app wins:
the reply is voiced while «foi para a voz» flashes, and the screen closes 1.4 s later
(`page.tsx:711-720`).

## Decision

- The scene turn's reply starts playing the moment it arrives, while the send-off line is on
  the screen.
- The screen still closes after 1.4 s, onto the Conversation, and the close does not cut the
  reply: it neither silences the room nor moves the generation, as the way back that carries a
  held turn (0165) does not.
- The send-off screen stays inert through the 1.4 s, as 0101 and 0165 decide.

## Consequences

The Station change at the close is the second that keeps the generation. A reply that cannot
play still follows the Failure policy.
