---
status: accepted, amended by 0052
date: 2026-10-01
amends: 0039, 0047
---

# A gone session leaves no file, and only a door that names it says so

This amends ADRs 0039 and 0047 without editing their text; it adds "amended by 0051" to
their status lines. ADR 0046 made the Session gone one event with one destination, the
Choice. Henok decided on 29 and 30 September, and the Definer refined on 1 October
(ENG-1175), what it takes with it and where it can come from.

**Everything of the session goes from the tablet, its audio included.** The Resume point's
row, the session's Outbox rows, stored or pending, and their copies, the kept takes' files,
the pending translation, the Listening ledger, the Step's timers and the pending request
with its key. A row in the air when the gone lands finishes its call, is never written back,
and its copy is deleted after. A gone that an older session's Outbox row meets discards that
session's rows and copies only, and the room stays where it is. The Reach and the retry
survive, because the Outbox is the room's and not the session's. A standing halt is cleared
with no call for a person. The audio is gone for good: the server no longer holds the
session it belonged to, so nothing could ever deliver it.

**Only a door that names a session can say it is gone.** The passages listing, the claim
code, the credential, the link and a session creation that names no session before it
answer a 404 as a Refusal with `NOT_FOUND`. A creation that names the session before it,
the panorama's, answers a 404 as that session gone: the room lets the panorama go and
creates the passage again without it, so the team's pick still opens a passage and nobody
is called. A gone lets go of every session the room holds that it names, the panorama's
included. This closes what ADR 0039 left to the executor: a 404 on the passages listing
read as gone sent the room to the Choice, whose first call is that same listing. The device
link reads `NOT_FOUND` where it read the gone, and starts over or shows a new code.

## Considered Options

**Keep the kept takes and the stored rows' copies**, for a person to recover by hand.
Rejected by Henok: invariant 6 says nothing of the session survives, files included, and a
recording nothing can deliver is a file the tablet carries forever.

**A reopening of a session the server forgot starts a fresh session of the same passage**,
as before. Rejected: one destination is the Choice, and the fresh session hid from the team
that their work there was gone.

## Consequences

ADR 0047's "A Session gone on an upload keeps spending an attempt until the Session gone
slice (ENG-1175) discards the session's rows" no longer holds: the Outbox discards that
session's rows on the gone itself.

Leaving a passage by the way out keeps the Reach too: the room that leaves is the room that
fell, and its retry is still armed.
