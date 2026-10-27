---
status: accepted, amended by 0137
date: 2026-10-21
supersedes: 0074, 0050 (in part)
amends: 0018, 0053, 0089, 0093, 0107
---

# The session screen tells no failure, and the Reach is gone

This supersedes ADR 0074 and, in part, ADR 0050 (the Reach; its invariant 12, the Outbox's
own retry, stands), and amends ADRs 0018, 0053, 0089, 0093 and 0107 without editing their
decisions: it adds "superseded by 0108", "superseded in part by 0108" or "amended by 0108"
to their status lines. The Definer settled the rules on ENG-1356 (Definition of 19 October,
corrected 21 October, and the answers of 21 October).

## Context

Marcia's rule is «never expose the failure mechanics to the team». Ours spoke two fixed
failure lines she never wrote, «sem conexão» and the microphone line, drew a cloud-off,
server-off or microphone-off face on the circle, and swapped the whole screen for a
microphone gate that never opened the room. The Reach, the region that knew the room had
fallen on a way in, existed to drive that face, its notice, its probe ladder and the resend
on the return. Her app shows the wordless person sign where a dead microphone leaves the
team, and nothing else.

## Decision

- **No failure line is spoken, and no offline or blocked face is drawn.** The tablet
  bundles no clip for either line.
- **There is no gate, and the room opens whatever the permission.**
- **The Reach is gone.** A network failure that is no turn's lets its Step go and changes
  nothing else. A way in that fails (the Choice, a passage or a Panorama with no session)
  rests at the invite, and the team's next tap asks again through the door it already has.
  There is no probe, no ladder, no radio watch and no resend. The Outbox keeps its own
  retry (ADR 0050, invariant 12).
- **Only the conversation's microphone on the Conversation or the Panorama raises the
  sign:** a refused start at once (row 5 of ADR 0093, wired for the first time), a failed
  start the second time in a row (row 6), and a start of the conversation's microphone
  resets the count. The tablet reports how many times in a row each microphone failed, and
  the failure policy alone decides which one counts. Every other microphone failure, on
  the Scene rehearsal, the Rehearsal, the Back-translation and the Raised hand's note, is
  silent; the policy still logs every one but the Scene rehearsal's, which only gives the
  Channel back (ADR 0089).
- **A tap over the speaking voice does nothing until the tablet knows it may record:**
  a refused permission, or one the platform never answered. A start heard later marks the
  permission granted.

## Considered Options

**Keep the way-in ladder until ENG-1371.** Rejected: the team's tap already asks again on
every way in, so nothing dead-ends without it.

**Count every microphone owner toward the sign, as before.** Rejected: her app counts the
session circle's microphone only.

## Supersedes and amends

- 0074: its subject, the reach check before a way in, is gone.
- 0050 in part: the Reach region, its fall, its return and the Pending request.
- 0093: the way in no longer falls; row 5 is raised; the microphone rows read the owner and
  the Station.
- 0107: its consequence «a tap on that face retries» has no face left to tap.
- 0089: the Rehearsal and the Back-translation are silent too.
- 0053: «Reach and the Pending request are gone» now holds.
- 0018: nothing reads `connectivity_plus` any more; its removal is left for a later change.

## Consequences

- A passage opened with the server away rests at the invite until a tap, and a silent
  server costs the request's own timeout instead of a six-second health ping.
- The Desk sees no difference: its «precisa de uma pessoa» queue follows the call, which
  only the sign makes.
