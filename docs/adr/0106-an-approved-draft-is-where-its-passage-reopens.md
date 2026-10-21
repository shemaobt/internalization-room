---
status: accepted
date: 2026-10-20
amends: 0063 (in part: a session found on no row asks its Opening when not Opened), 0064 (in part: a relaunch with no row lands on the Canvas)
---

# An approved draft is where its passage reopens

This amends ADR 0063 and ADR 0064 without editing their decisions: it adds "amended by 0106"
to their status lines. The server half is ADR 0071 of the API (ENG-1235): the team's **Draft**
is its live session of the passage, and the Session read says `approved` while the passage's
latest release is still the packet the session composes now.

## Context

The approval forgets the Resume point and closes to the Choice, so a re-entry opened the
session from no row. The room then landed on the Conversation at rest, or asked the Opening of
a session it had never opened, under any warning still standing: the team met its finished
passage as a conversation at zero.

## Decision

- **A Session read that says `approved`, with stretches told, lands on the approved draft**,
  whichever door brought it: the open from the Choice, a relaunch onto the Current session, or
  a resume from any row. The landing is the Back-translation, checked, with «✓ aprovado como
  rascunho final (v{n})» where the approve button stands. The Opening is never asked there, and
  the Resume point is written on the Back-translation.
- **A forced approval lands the same**, checked, even over a telling-back the check never
  passed: that the approval was forced stays on the record for the consultant and the packet,
  and nothing on the tablet changes it (the Definer, 2026-10-20).
- **A tablet whose Outbox still holds anything of the session that changes the packet lands
  where it stood**: a take, a stretch or a frase told again. It un-approves the draft once it
  reaches the room, so the approved draft is not where the team is.
- **The parts come from the room when the tablet holds none.** A room that cannot hand them
  over leaves the frases silent and listening dimmed; it raises no halt and shows no sign. The
  Back-translation row that landing writes holds no parts, and a row like it never reads as
  nothing to restore: the next entry fetches the room's rehearsal, as any resume short of its
  files does.
- **No Warning mark on the approved draft.** The room's warning is not lifted: the Desk still
  sees it and attends it.
- **The badge is what the newest applied Session read says** (ADR 0048), and only a read sets
  or clears it. A landing numbers its read once the parts are down, so a Watch beat it raced
  never outranks it. Whether the badge is drawn, in place of the approve button and the Warning
  mark, is decided where it is drawn: in the checked phase, and only while nothing of this
  session waits in the Outbox (its takes, its stretches, a frase held to be sent).
- A read with no `approved`, a server that does not send it among them, lands as before.

## Considered Options

**Keep the Resume point on the approval.** Rejected: a second tablet, or a reinstall, has no
row, and the room is the one that knows the draft is approved.

**Lift the warning on an approved draft.** Rejected: a warning is the Desk's to attend.

## Consequences

- A Choice entry of an approved passage downloads its parts whenever the tablet holds no Resume
  point for it, the tablet that approved included: the approval forgets the point, and with it
  which files on the tablet are the parts.
- The value lives in the Retro screen's notifier fields (ADR 0046's written exception), not on
  the machine, until after the 2 November freeze.
- Which Station a read lands on stays a branch of the notifier's entry until the entry decision
  moves into the machine.
- The tablet reads only the approval's version; the rest of the field is the server's record.
