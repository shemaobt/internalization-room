---
status: accepted
date: 2026-10-06
amends: 0053
---

# The runner asks the Station for the session and the failure context

This amends ADR 0053 without editing it; it adds "amended by 0059" to its status line. The
Definer and the Orchestrator settled it on 6 October while the Session read and the reach
left the notifier (ENG-1453).

## Context

The effect runner now sends the Session read and asks the reach through the Room port, and
every failed answer goes through the failure policy there. ADR 0053 assumed the machine
would hold what the runner needs for that. It holds the Station since ADR 0058, but no
session and no Step, so the runner cannot build a failure context or name the session to
read from the machine alone.

The Station also keeps the order of its reads: a read older than one already applied is
dropped, and the stretches are taken only if the row is the one the read was sent over.
Other reads the Station sends itself share that order.

The probe and four Step asks shared one ask of the reach, so a Step and a probe in the air
together fall once.

## Decision

- **The runner asks the Station two questions through `EffectHost`**, as ADR 0057 asks
  `keepsTheStart`: `session`, the room's session or none, and `failureContext`, the
  Station's context for a door, a rule and, for the reach, how far the ask got. It asks each
  when it needs the answer: `session` when it sends a read and again when the read
  answers, dropping an answer for a session that is no longer the room's; `failureContext`
  when a failed answer returns, so the event carries the current generation. `generation`
  stays the runner's only constructor seam.
- **A failed read is decided at the Watch's door under `passes`.** The policy names the same
  events as before: a network failure takes the room out of reach at the Watch's door, a
  refusal passes, and a session gone tells the machine so.
- **The Station hears an answered read.** It stamps the read in its order when the runner
  sends it (`hearTheReadSent`) and applies the snapshot with that stamp when the room
  answers (`hearTheSessionRead`). An answered read reaches the machine as `SessionRead`,
  from the Station, and not through the policy: `TheRoomAnswered` would reset the notice
  for a read the Station then drops.
- **The one ask lives in the runner.** One ask of the reach is in the air at a time; a
  probe and a Step share it, and it falls once, only if a Step asked or the room is out of
  reach when it lands. The Step asks and the retry gesture reach it there.
- **The reach's face follows the machine.** It goes back to fine on the transition where the
  machine takes the room back, in the same state write, so a probe that finds the room
  answers only `NetworkReturned`.

## Considered Options

**Constructor seams beside `generation`.** Rejected after ADR 0057: the runner already asks
the Station through host questions, and a seam per question grows the constructor for each
one.

**The machine learns the session.** Rejected here: it needs an event for every write of the
session, which is a slice of its own.

## Consequences

- `EffectHost` reads no state and probes nothing. It answers `session` and
  `failureContext`, and hears a read through `hearTheReadSent` and `hearTheSessionRead`.
- The Station's other reads (the resume, the pull, the passage's own reads) stay in the
  notifier and share the order the runner's read is stamped in.
