---
status: accepted
date: 2026-10-30
amends: 0064 (in part: the last line is stored for «Ouvir de novo»), 0097 (in part: the say-it-again is the fallback)
---

# «Ouvir de novo» replays the clip held on the tablet and asks the room only when it is gone

This amends ADR 0064 and ADR 0097 without editing their decisions; it adds "amended by 0164"
to ADR 0064's status line. The Definer settled it on the ticket (ENG-1963) on 29 October, and
her frozen app wins: it replays `lastAudio`, the exact clip just heard (`page.tsx:509`,
:901-905), and a reload replays it too (:107-113).

## Context

ADR 0064 rejected storing the last line for «Ouvir de novo»: the room said it again. Every
replay then cost a round trip, the audio could be produced again and differ from what the team
heard, and a relaunch needed the network.

## Decision

- **The line starts to count the moment it starts to speak.** The tablet pins the clip as the
  one «Ouvir de novo» gives back when it begins, so a line cut before it was heard is the one
  replayed, as her `speak` does.
- **A replay plays the clip held on the tablet and calls nobody.**
- **The last clip is kept on disk with the Current session**, one clip only, and dropped as
  soon as the team takes a turn: it survives a relaunch only while the conversation ends on a
  Guide turn.
- **Only when the clip is not on the tablet does «Ouvir de novo» ask the room to say it
  again**, under ADR 0097's turn id. A conversation with no stored clip asks the room as before.

## Consequences

- ADR 0064's rejected alternative "Store the last line" now holds, for the last clip alone.
- The Current session record gains the clip's address; a record written before it reads as
  holding none.
- When the replay shows, and that it survives a way back, stays with ENG-1977.
