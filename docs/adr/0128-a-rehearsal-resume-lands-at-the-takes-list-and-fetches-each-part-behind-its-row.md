---
status: accepted
date: 2026-10-23
amends: 0023
---

# A Rehearsal resume lands at the takes list and fetches each part behind its row

This amends ADR 0023 without editing its decision. The rules are ENG-1762's and Henok's
decision of 22 October.

## Context

A passage reopened on the Rehearsal on a tablet that no longer holds its recordings read the
room's takes list, then fetched every missing part, measured them, and only then landed. Each
fetch may wait up to the long timeout, so on a slow link the circle thought for minutes before
the recording home showed, and one part the room would not hand over sent the team back to the
Choice. Her app shows the rows at once and streams a row's audio when it is played.

## Decision

- A Rehearsal resume lands on the recording home as soon as the room's takes list answers.
  Every current part the room holds shows on its Scene row from that moment.
- A part the tablet does not hold is a **Part on its way**: it is one of the rehearsal's parts,
  in its place among them, under a name that is no file. Its listen stays dark until its
  recording is here.
- The parts on their way come down one at a time, in part order, each under the long timeout,
  and the busy watchdog is re-armed for each, starting once the Session read has said where the
  team stands. Each lights its row as it lands, and the Resume point names it at once, so a part
  this tablet holds is never fetched again.
- A part whose fetch fails keeps its row and the next tap on its listen fetches it again. No
  words, no sign, no person called. A part the room answers is gone (its 404) leaves its row
  with no part, and a recording made there goes above the room's pass, as before.
- Nothing plays the rehearsal, sends it on or joins its parts until every part is here: the
  wood play and the advance disc stay dark, and the machine refuses the way out of the
  Rehearsal while a part is on its way. Recording a scene again is never held back; the room's
  copy that lands after it is discarded.
- A file still on the tablet under a current part's name is kept as it is and never fetched.
- The Resume point is rewritten once every part has been tried. Any write in between names the
  parts on their way, so an app closed meanwhile fetches them again on its next opening.
- A Back-translation resume, the approved draft's landing and the refusal re-read still fetch
  every part before they land.
- An approved draft the room reads after a Rehearsal landing lands at once (ADR 0106); the parts
  on their way keep coming down behind it in the same order, and a frase over a part not yet
  here stays silent and dimmed until that part lands. A part the room lost stays under the
  draft, its frases silent; dropping it is the Rehearsal's rule only.

## Considered options

- Stream the audio as her app does. Rejected: out of the ticket's scope.
- Land at the listing but fetch every part at once. Rejected: the ticket asks for one at a time,
  in part order, and three long waits sharing one slow link only make each later.
- Keep the parts on their way out of the rehearsal until they land. Rejected: a stretch
  addresses its part by its place among the parts (ADR 0022), so a part landing later would
  shift every stretch after it; the circle would record over a part the room holds; a Resume
  point written meanwhile would forget it.
- Darken «Gravar de novo» on a part on its way. Rejected: the rule holds back play, send and
  join only, and on a silent server the team could never record that scene again.
- Let a Back-translation resume land first too. Rejected for now: the Back-translation plays a
  part on landing, and landing before its bytes needs its own rule.

## Consequences

- A fetch failure on a Rehearsal resume no longer sends the team to the Choice.
- A Back-translation resume still waits for its parts, up to the long timeout per part.
