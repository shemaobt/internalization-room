---
status: accepted
date: 2026-10-07
amends: 0061 (in part: the room starts on the Choice), 0051 (in part: what a gone session takes from the tablet)
---

# The tablet remembers its current session and a relaunch lands on it while the room holds it

This amends ADRs 0061 and 0051 without editing them; it adds "amended by 0064" to their
status lines. The Definer settled it on the ticket (ENG-1281) on 6 and 7 October: a
relaunch lands on the Station the stored row names, and the record holds the session id,
the book, the pericope and the language only. The Orchestrator decided the launch reads the
session by id and never opens one, and that entering the Panorama clears the record.

## Context

A linked tablet always opened on the Choice (ADR 0061). The session the team was in came
back only when the team found its passage on the Wheel and entered it again, so a reload in
the middle of work meant hunting for their place by ear. The per-passage Resume point knew
where each passage was left, but nothing said which passage the tablet was in.

## Decision

- **The tablet keeps one Current session**: the session id, the book, the pericope and the
  language, in a file of its own beside the Resume points. It is written when the team
  enters the Canvas with a session, from every door. It is let go when the team goes to the
  Choice, when the passage closes (so a kill during the Closing lands on the Choice), and
  when the room no longer knows the session. The Panorama never writes it, and entering
  the Panorama clears it, as leaving to the Choice does: the tablet is then in no session.
- **The Current session belongs to the device link.** When the link starts over, the record
  is let go with it. The server reads a session for any linked tablet, with no team scope,
  so a tablet claimed by another team would otherwise land in the old team's session.
  Letting go is one call where the link is already forgotten; carrying the team in the
  record would make every launch compare it against a link that may still be on its way.
- **A launch reads the session by id, never by an open.** The record is read once per
  launch, the first time a linked tablet stands on the Choice with no Wheel read yet; a
  later resume of the app opens the Choice as before and never pulls the team into a
  passage. A record of another book or another language is let go and the Choice opens.
  Otherwise the room is asked for the session by its id. An open would hand back a fresh
  session after a Desk reset and hide that the session is gone.
- **The room answers: the team lands where it stopped, in silence.** The landing is the
  resume's own, handed the session the room read: the Station the Resume point names, or
  the Canvas when there is no row. It never asks the Opening, even of a session the room
  says is not Opened, so a session killed while its Opening drafted lands quiet with
  «Ouvir de novo» armed. A landing that waits for the room enters again with the same
  session when the room comes back, never a new one.
- **The room says the session is gone: it is let go and the Choice opens**, with no person
  sign and nothing said. The record goes with the session's Resume point and its Outbox
  rows (ADR 0051).
- **The network fails, or the room refuses: the Choice**, or its usual offline face. The
  record is kept for the next launch, and the Choice's own read decides the failure. The
  old Canvas is never shown.
- **The Wheel is read only when the team goes to the Choice.** A direct landing leaves it
  unread.
- A second call while the launch's read is in the air changes nothing.

## Considered Options

**Open the session (`createSession`) at launch.** Rejected: after a Desk reset the server
mints a fresh session for the passage, and the tablet would land on it as if nothing
happened.

**Keep the record inside the Resume points' ledger.** Rejected: every entry of that file is
read as a Resume point.

**Always land on the Canvas.** Rejected by the Definer: a team that stopped in the
Rehearsal or the Back-translation comes back there, as entering from the Choice does.

**Store the last line for «Ouvir de novo».** Rejected: the room says its last line again
(ADR 0063).

## Consequences

- ADR 0061's "the room starts on the Choice" holds only for a tablet that holds no Current
  session the room still knows.
- ADR 0051's gone session also takes the Current session that names it.
- A launch that lands reads the session twice: once to decide, and once in the resume.
- A tablet upgraded mid-passage holds no record; its first launch opens the Choice, and the
  next entry writes one.
