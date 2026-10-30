---
status: accepted
date: 2026-10-30
amends: 0101 (in part: where the reply plays), 0058 (in part: a second Station change keeps the generation), 0165 (in part: the reply landing during the 1.4 s line waits for the close)
---

# The scene reply plays beneath the send-off line

This amends ADRs 0101, 0058 and 0165 without editing their decisions; it adds "amended by
0167" to their status lines. The Definer settled it on the ticket (ENG-1907) on 29 October, and her frozen app wins:
the reply is voiced while «foi para a voz» flashes, and the screen closes 1.4 s later
(`page.tsx:711-720`).

## Decision

- The scene turn's reply starts playing the moment it arrives, while the send-off line is on
  the screen.
- The screen still closes after 1.4 s, onto the Conversation, and the close does not cut the
  reply: it neither silences the room nor moves the generation, as the way back that carries a
  held turn (0165) does not. A halt raised meanwhile lands at the close and silences the
  line, as any halt on the Canvas.
- The send-off screen stays inert through the 1.4 s, as 0101 and 0165 decide.

## Consequences

The Station change at the close is the second that keeps the generation (0058). A reply that cannot
play still follows the Failure policy.
