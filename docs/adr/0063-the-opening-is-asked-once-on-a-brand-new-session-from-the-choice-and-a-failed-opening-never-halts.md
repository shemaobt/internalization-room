---
status: accepted
date: 2026-10-07
amends: 0053, 0048 (in part: the halt over an opening and the lift's re-ask), 0044 (in part: what a lift replays over an opening)
---

# The Opening is asked once, on a brand-new session, from the Choice, and a failed opening never halts

This amends ADRs 0053, 0048 and 0044 without editing them; it adds "amended by 0063" to
their status lines. The Definer settled it on the ticket (ENG-1280) on 6 and 7 October:
the voice opens a session once, on a brand-new session only; a resumed session stays
silent with «Ouvir de novo» offered; and a failed opening never stops the room. The
Orchestrator ruled that the Panorama's failed Opening stays calm too.

## Context

Entering a passage always ended by asking its Opening. On a session the team had already
talked in, the server answered by saying its last line again, so every return replayed a
line nobody asked for. A failed Opening was handled like any failed turn: a refusal, or a
lost Opening the One look did not find, raised a blocking Halt that called for a person;
the lift asked the Opening again under a fresh turn id, and a tap on the circle asked it
again while it was owed. A team whose Opening failed met the person sign, or a circle that
would not record them.

## Decision

- **The app asks a session's Opening only from the Choice's door, and only while the room
  says the session is not Opened.** The room says so on the session it creates and on the
  Session read. A session this entry did not find on disk asks iff the room's new session
  is not Opened; a resumed session reads the session once and asks iff it is not Opened.
  A server that does not say reads as not Opened. A Session read the network loses on
  the way in enters again from the same door when the room comes back.
- **A resumed session plays nothing.** It restores its beads and its halt from the Session
  read, or from the session the room hands back when another tablet opened it, lands at
  the invite, and arms «Ouvir de novo». Its first tap asks the room to say its last line
  again: not a turn, with no turn id, nothing written, and never looked at. The line is
  spoken as a line that arrives is: an Opening told in two movements says its Scene, and
  a reply says itself. It is then the one «Ouvir de novo» repeats.
- **The long press says both movements only when the line said again is an Opening told
  in two movements**, as on the first hearing; any other line has none.
- **A failed Opening rests at the quiet invite, with no sign and no sound.** A network
  failure or the client's give-up is looked at once: a reply that landed plays, and
  anything else lets the Opening go. A refusal lets it go too, unless its code stops the
  room, which still calls a person. A clip that will not play lets it go.
- **The next open from the Choice asks again** while the room has not opened the session.
  An Opening that reached the tablet but whose clip would not play is already in the room:
  the return lands quiet, and «Ouvir de novo» has the room say it. The tap and the lift no
  longer ask: after a quiet failure, a tap on the circle records a team turn, and a lift
  over an Opening asks nothing.
- **The Panorama's failed Opening stays calm too** (the Orchestrator's ruling), and its
  circle still asks it again before its line plays.
- **ENG-1371** ("a failed opening returns to the resting invite") is the same rule seen
  from the failure side, and is settled here.

## Considered Options

**A local flag for "opened".** Rejected: a second tablet, or a row lost to a reinstall,
would read it wrong. The room is the one that knows.

**Keep the halt over an Opening and the lift's re-ask (ADR 0048).** Rejected: a failed
Opening is not something a person has to resolve, and the team can speak without it.

**Replay the remembered Opening on «Ouvir de novo».** Rejected: a resumed session holds
no line on the tablet; the room says its last line as it built it for a team walking back.

## Consequences

- ADR 0048's "any halt over an opening is lifted by asking the opening again under a turn
  id of its own" no longer applies: an Opening's own failures raise no halt, and a halt
  that keeps an Opening (a refusal that stops the room) lifts with nothing asked.
- ADR 0044's lift replays nothing over an Opening.
- ADR 0053's Failure policy answers a refusal over an Opening, and an empty One look over
  one, by letting the Opening go instead of a Halt.
- A tablet mid-halt over an Opening at the upgrade lifts with nothing asked; the next open
  from the Choice asks.
- A reload never asks an Opening: only the Choice's door does.
