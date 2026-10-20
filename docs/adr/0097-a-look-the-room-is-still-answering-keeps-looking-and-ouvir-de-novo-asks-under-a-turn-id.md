---
status: accepted
date: 2026-10-20
amends: 0063
---

# A look the room is still answering keeps looking, and «Ouvir de novo» asks under a turn id

This amends ADR 0063 without editing its decision; it adds "amended by 0097" to its status
line. The Definer settled it on the ticket (ENG-1372) on 19 and 20 October.

## Context

The One look read the room's "still answering" (202) as nothing found, so a turn or an
Opening the room was still drafting called a person. The room's line said again on
«Ouvir de novo» was not a turn (ADR 0063: no turn id, never looked at), so a slow one met
the busy watchdog with nothing in flight and halted, and a lost one fell to the offline
face.

## Decision

- **A look the room is still answering looks again every two seconds**, under the busy
  watchdog the give-up armed. The watchdog running out decides it as nothing found. Two
  seconds is half the rate the server's own wait on a claimed Opening looks at, since the
  tablet's look crosses the network.
- **What the look then finds follows who asked for it.** A team turn, or a line said again
  on the team's tap, plays as One look finds always play. An Opening rests silent with
  «Ouvir de novo» armed: nobody asked to hear it.
- **«Ouvir de novo» asks the room under a turn id of its own**, a new one on every tap. Its
  network failure, the client's 305 s give-up and the watchdog give it up like a turn, with
  one look; the room stores nothing under that id, so an empty look over it is the normal
  outcome and rests with «Ouvir de novo» still armed. A refusal is still a refusal of a
  request, counted, not a turn's.
- **The Definer's "look that belongs to the resume" has no path in the app.** A relaunch
  asks nothing, not even an Opening the room is still drafting; the only request after it
  is the team's tap on «Ouvir de novo», which plays.

## Considered Options

**Keep the say-it-again outside the turn path and give it its own watchdog rule.** Rejected:
it would be a second give-up beside the One look, and the turn path already holds every
failure it can meet.

**Keep a turn id in flight on disk so a relaunch looks at it.** Rejected for now: a new
capability the ticket does not ask for; the relaunch stays silent without it.

## Consequences

- ADR 0063's "not a turn, with no turn id, nothing written, and never looked at" no longer
  holds for the line said again; "nothing written" still does.
- A look that lands on another server instance than the turn answers 404 instead of 202 and
  is decided as today.
