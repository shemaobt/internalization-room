---
status: accepted
date: 2026-11-02
amends: 0135
---

# An unsent take belongs to the team that recorded it

## Context

A re-link is a revocation followed by a new code, a new device id and a new credential, also when
the tablet goes back to the same team. The room answers the same 404 for another team's session as
for a gone one. ADR 0135 kept takes from crossing teams by emptying the Outbox on every
revocation, which deleted a team's unsent work in silence. Henok's rule (30-10): unsent takes stay
on the tablet, never go to the new team, are kept under the old team until a re-link to it, never
cross teams, and are never deleted in silence.

## Decision

An Outbox row records the team it was recorded under, as the link's `project_id`: the credential
changes on every link and never comes back, while the project is the team. The tablet sends,
lists, counts and lets go only the rows of the team it is linked to now; every other row stays on
disk with its copy, untouched, until the tablet is linked to that team again.

A revocation no longer empties the Outbox nor deletes its copies. It stamps every row without a
team but with a session with the team being left, read from the link file before the link is
forgotten; when that file cannot say the team, the row is stamped «team unknown», which no team
ever matches, so it is never sent, never listed and never deleted. A row with neither a team nor a
session is stamped «team unknown» too, never the team being left (below). A take kept while the revocation lands is kept the same
way. Only the copies no row names are deleted, except those a quarantined manifest may still name
(ADR 0087). The recordings folder is still swept (ADR 0135).

A row without a team was written by a build before this one. One with a session is the current
life's, as ADR 0135 left every re-link with an empty Outbox. One without a session may be a row an
older build let go under another team, so no team can claim it: the first life begun with a
team stamps it «team unknown», and until the stamp is written it is never counted as the current
team's (Henok, 03-11). A stamp the disk refuses is tried again at the next launch.

A Resume point (`em_curso.json`) belongs to the team that wrote it the same way: it records the
link's `project_id` as `team`, written only when set, and is kept under a key that names the team.
The tablet reads, lists, rewrites and forgets only the points of the team it is linked to now, so a
re-link to another team never asks the room for the old team's session, and the 404 that would have
answered erases nothing. The old team's point waits on disk until the tablet is linked to it again,
and then resumes the passage where it stood. A point with no team was written by a build before this
one and is the current team's, as an untagged Outbox row with a session is (ENG-2144).

The row's shape grows by two optional keys, written only when set: `team` and `team_unknown`. They
sit beside `swap`, written only by the recording home's swap and read as false when missing
(ENG-2079).

## Considered Options

- Key the row by the credential: rejected, a credential never comes back, so the take could never
  go up again.
- A size or age limit on held takes: rejected, a limit is a deletion in silence (Definer, 02-11).
- Tell another team's 404 from a gone session's: impossible, the room answers both alike.

## Consequences

- An older build reads the manifest by key and ignores both. A downgrade sends a row at once under
  the current link: under another team, its session answers 404, it is let go to its passage and
  sent into that team's session of the passage. A downgrade is not a supported path.
- After a downgrade and an upgrade, the rows the older build rewrote carry no team again.
- Takes of a team never linked again, and «team unknown» rows, stay on disk with no bound and no
  way to reach them yet (a finding for the close).
- No sign on screen shows takes held under another team (Henok, 30-10).
