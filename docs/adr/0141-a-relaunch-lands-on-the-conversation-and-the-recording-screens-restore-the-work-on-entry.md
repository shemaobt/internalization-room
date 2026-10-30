---
status: accepted, amended by ENG-1861 (2026-10-29: after a relaunch the dot counts only takes the room has received) and ENG-1964 (2026-10-30: a Choice pick lands on the conversation too)
date: 2026-10-28
amends: 0064 (in part: a relaunch lands on the Station its row names), 0138 (in part: what still counts as waiting in the Outbox)
---

# A relaunch lands on the conversation, and the recording screens restore the work on entry

This amends ADR 0064 and ADR 0138 without editing their decisions: it adds "amended by 0141"
to their status lines. Her app is the bar, and it wins over our ADRs
(João, 26 October). ADR 0064 recorded "Always land on the Canvas" as rejected by the
Definer; her app lands there.

## Context

A relaunch read the session the tablet held and landed on the Station its Resume point
named: the recording home, the Back-translation, the check. Hers never does. The reload
(`app/page.tsx:199-213`) reads the stored session and ends on `setView("session")`, the
conversation, with «Ouvir de novo» replaying the last Guide turn. The team walks back into the
recording through the orange dot, and Drafting reads its rows when it opens.

ENG-1833 already landed an approved passage on its conversation (ADR 0138), with two gaps. A
take of an older pass the room refused for good still counted as waiting in the Outbox, so the
passage reopened on the Back-translation. And a row on the Rehearsal stood on the recording
home for one Session read before the approval brought it back to the conversation; hers goes
straight to the conversation.

## Decision

- **A relaunch with a stored session lands on that passage's conversation at rest**, whatever
  Station its Resume point names: «Ouvir de novo» is armed, nothing is said or played, and the
  Opening is never asked.
- **The relaunch loads the takes the tablet still holds and fetches nothing.** The parts it no
  longer holds are not listed or fetched at the relaunch; the recording home the orange dot
  opens lays the room's parts in behind its rows, as it does for any passage. The relaunch
  writes no Resume point, so the Station, the takes and the listener it names are there for
  the next entry.
- **The orange dot then leads where it leads from a live session**: the recording home over a
  passage with a take that came from no join, the Ensaio Final plan otherwise (ADR 0117).
- **The recording home counts the Outbox before it takes the room's parts.** A take the launch
  sent from the Outbox while the team stood on the conversation is no longer waiting when the
  home opens, so a swap the tablet was closed on becomes the part there.
- **A relaunch never passes through the recording home**, so an approved draft relaunched on a
  Rehearsal row reaches its conversation without standing on the home for one Session read.
- **An Outbox take refused for good with the room's code does not keep an approved passage
  off its conversation.** It can never land, so it cannot change the draft. A take refused
  with no code still counts: the team's tap sends it again (ADR 0103).

## Considered Options

**Land on the conversation and fetch the missing parts behind it.** Rejected: each part that
lands writes the Resume point where the team stands, the conversation, and a row on the
conversation is never restored again.

**Load nothing at the relaunch and let the dot's home read everything.** Rejected: the home
writes the Resume point as it opens, and it would write it without the tablet's own takes.

**Read the session before every Rehearsal landing, from the Choice too.** Rejected: ADR 0128
lands a Rehearsal resume as soon as the room's takes list answers and brings its parts down
while the Session read is in the air; waiting on the read first undoes that. Entered from the
Choice, an approved draft on a Rehearsal row still stands on the home for one read. Hers lands
every choice on the conversation (`app/page.tsx:774-798`), which is a wider change than a
relaunch.

## Consequences

- ADR 0064's relaunch lands on the Station its row names no longer; the read by id, the
  let-go and the failures stand.
- The Choice still lands an unapproved passage on its row's Station, where hers lands on the
  conversation.

## Amendment · 2026-10-29 (ENG-1861)

**The orange dot then leads where it leads from a live session**, and that place is decided by
the room (ADR 0117, amended by ENG-1861): a take the relaunch loaded that never reached the room
no longer opens the recording home at once. The dot opens the Ensaio Final plan or the grain
choice the room's listing calls for, with that take offered on top under her notice, and the
recording home is reached from there by «Gravar cena por cena» or once the take is sent.

## Amendment · 2026-10-30 (ENG-1964)

**A passage picked on the Choice lands as a relaunch does**, on its conversation at rest with
the room's phase: a done passage reads done, with the dot lit. Hers lands every pick there
(`app/page.tsx:774-798`). The Choice no longer lands on the recording home, the check or the
telling-back, and no entry picks a telling back up at its cursor. The entry loads the takes the
tablet holds and fetches nothing; the recording home the orange dot opens lays the room's parts
in. A relaunch lands on the snapshot its launch already read, so a read that fails sends it to
the Choice and nothing after it can fail the landing. The Consequence that the Choice still
lands on its row's Station no longer holds, and neither does the approved draft standing on the
home for one read.
