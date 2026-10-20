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
- **The parts come from the room when the tablet holds none.** A room that cannot hand them
  over leaves the frases silent and listening dimmed; it raises no halt and shows no sign.
- **No Warning mark on the approved draft.** The room's warning is not lifted: the Desk still
  sees it and attends it.
- **The badge follows every applied Session read**, newest first (ADR 0048), and goes as soon as
  the telling-back leaves its checked phase.
- A read with no `approved`, a server that does not send it among them, lands as before.

## Considered Options

**Keep the Resume point on the approval.** Rejected: a second tablet, or a reinstall, has no
row, and the room is the one that knows the draft is approved.

**Lift the warning on an approved draft.** Rejected: a warning is the Desk's to attend.

## Consequences

- A Choice entry of an approved passage costs the parts' download on a tablet that no longer
  holds them.
- The value lives in the Retro screen's notifier fields (ADR 0046's written exception), not on
  the machine, until after the 2 November freeze.
