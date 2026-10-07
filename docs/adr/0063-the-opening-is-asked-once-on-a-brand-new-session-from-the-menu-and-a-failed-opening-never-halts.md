---
status: accepted
date: 2026-10-07
amends: 0053, 0048 (in part: the halt over an opening and the lift's re-ask), 0044 (in part: what a lift replays over an opening)
---

# The Opening is asked once, on a brand-new session, from the Menu, and a failed opening never halts

This amends ADRs 0053, 0048 and 0044 without editing them; it adds "amended by 0063" to
their status lines. The Definer settled it on the ticket (ENG-1280) on 6 and 7 October:
the voice opens a session once, on a brand-new session only; a resumed session stays
silent with «Ouvir de novo» offered; and a failed opening never stops the room.

## Context

Entering a passage always ended by asking its Opening. On a session the team had already
talked in, the server answered by saying its last line again, so every return replayed a
line nobody asked for. A failed Opening was handled like any failed turn: a refusal, or a
lost Opening the One look did not find, raised a blocking Halt that called for a person;
the lift asked the Opening again under a fresh turn id, and a tap on the circle asked it
again while it was owed. A team whose Opening failed met the person sign, or a circle that
would not record them.

## Decision

- **The app asks a session's Opening only from the Menu's door, and only while the room
  says the session is not Opened.** The room says so on the session it creates and on the
  Session read. A session this entry did not find on disk asks iff the room's new session
  is not Opened; a resumed session reads the session once and asks iff it is not Opened.
  A server that does not say reads as not Opened.
- **A resumed session plays nothing.** It restores its beads and its halt from the Session
  read, lands at the invite, and arms «Ouvir de novo». Its first tap asks the room to say
  its last line again: not a turn, with no turn id, nothing written, and never looked at.
  The line it says is then the one «Ouvir de novo» repeats.
- **A resumed session's «Ouvir de novo» has no long press.** A line said again is one
  movement; the two movements of the Opening are not said again.
- **A failed Opening rests at the quiet invite, with no sign and no sound.** A network
  failure or the client's give-up is looked at once: a reply that landed plays, and
  anything else lets the Opening go. A refusal lets it go too, unless its code stops the
  room, which still calls a person. A clip that will not play lets it go.
- **The next open from the Menu asks again.** The tap and the lift no longer do: after a
  quiet failure, a tap on the circle records a team turn, and a lift over an Opening asks
  nothing.
- **The Panorama's failed Opening stays calm too**, and its circle still asks it again
  before its line plays.
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
  from the Menu asks.
- A reload never asks an Opening: only the Menu's door does.
