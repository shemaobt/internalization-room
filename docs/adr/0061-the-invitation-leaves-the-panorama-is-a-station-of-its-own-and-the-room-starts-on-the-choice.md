---
status: accepted
date: 2026-10-06
amends: 0053
supersedes: 0046 (in part: what it says of the Invitation)
---

# The Invitation leaves, the Panorama is a Station of its own, and the room starts on the Menu

This amends ADR 0053 without editing it; it adds "amended by 0061" to its status line. Henok
decided on 6 October, and the Definer settled it on the ticket (ENG-1282), that the app
opens on the passage choice and always opens the passage the team chose, as Marcia's does.

## Context

A tablet that had never heard a book opened on the Invitation: a welcome, the book's
Panorama, then an entry button to the Choice. The Choice was reachable only after the
Panorama's first line. When the tablet asked for the Panorama or a passage, the app followed
whatever pericope the room's answer named, so the room, not the team, sometimes decided where
the team landed. A passage the room refused to open was dimmed and skipped for the rest of
the visit. And the Choice that opened after the Closing could read the finished passages
before the write of the passage just finished had landed, and showed it unfinished.

## Decision

- **The room starts on the Choice.** The machine is born on the Choice (the `Menu` Station),
  and the room started over arrives there from every Station. Opening the room opens the
  Choice only while its Wheel is unread; anywhere else it changes nothing.
- **The Panorama is a Station reached from the Choice.** Tapping the Panorama, the book's first
  entry, arrives at the Panorama Station and voices the Panorama there. It shows the circle
  only, with the hand. After its line, a tap on the circle records the team and the next one
  sends the turn to the Panorama session, as the Invitation's panorama step did. The Panorama
  carries no done mark.
- **A tap opens exactly the entry tapped.** The app never swaps to another pericope named in
  the room's answer.
- **No entry is dimmed, skipped, reordered or hidden.** A passage the room refuses to open
  returns the team to the Choice with the entry in place and still tappable. The Wheel halt
  stands only for a Wheel that holds the Panorama alone.
- **A read of the finished passages waits for the write in flight**, so the Choice after the
  Closing shows the passage just finished.
- **The dev language button restarts the room from every Station.**
- **The round leave button reaches the Panorama** until ENG-1461 replaces it, so the Panorama
  is not a dead end.

## Considered Options

**Keep the Panorama on the Choice's screen, as the Wheel's spoke played it.** Rejected: the
Panorama's turn needs a place where a tap on the circle records the team, and the Choice's
circle says the entry aimed at.

**A Step for "the line was said".** Rejected: the Panorama has one fact to keep, and the
Invitation's Step enum leaves with it.

## Consequences

- ADR 0046's Station list loses "Invitation: welcome, panorama"; the Panorama Station has no
  Step.
- ADR 0040's "a button that does not apply is dimmed, never hidden" no longer reaches the
  refused passages: nothing on the Wheel is dimmed.
- A tablet's existing book mark stays in its ledger, unread. No stored data changes.
- The room asks for the Panorama by its alias and reuses the Panorama session within a
  launch, and a passage created after it still names it as the session before.
