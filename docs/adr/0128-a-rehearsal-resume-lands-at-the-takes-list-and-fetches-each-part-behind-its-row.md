---
status: accepted, amended by ENG-1964 (2026-10-30: no entry lands on the Rehearsal or the Back-translation)
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
  and the busy watchdog is re-armed for each, starting at the landing. Each lights its row as it
  lands, and the Resume point names it at once, so a part this tablet holds is never fetched
  again.
- A part whose fetch fails keeps its row and the next tap on its listen fetches it again. No
  words, no sign, no person called. A part the room answers is gone (its 404) waits for the
  Session read: on the Rehearsal it then leaves its row with no part, and a recording made there
  goes above the room's pass, as before.
- Nothing plays the rehearsal, sends it on or joins its parts until every part is here: the
  wood play and the advance disc stay dark, and the machine refuses the way out of the
  Rehearsal while a part is on its way. Recording a scene again is never held back; the room's
  copy that lands after it is discarded.
- A file still on the tablet under a current part's name is kept as it is and never fetched.
- The Resume point is rewritten once every part has been tried. Any write in between names the
  parts on their way, so an app closed meanwhile fetches them again on its next opening.
- Every resume onto an approved draft lands first the same way, whichever row it comes from: a
  row on the Back-translation with files missing reads the Session read first, and when it says
  approved the draft lands at once over the room's parts; a listing that fails there goes back
  to the Choice with the row untouched, as before.
- A Back-translation resume that is not an approved draft lands the same way (ENG-1788): as soon
  as the takes list answers, its frases drawn from the Session read, each dimmed and silent over a
  part on its way and lit as that part lands. Nothing plays and the circle stays dark until every
  part is here; the last part landing starts the uncounted floor. A part the room lost, or one
  that could not be fetched, holds the floor for the visit with its frases dark: the team is
  never sent to record it again from the Back-translation, and leaves by the menu. The refusal
  re-read still fetches every part before it lands.
- An approved draft the room reads after a Rehearsal landing lands at once (ADR 0106); the parts
  on their way keep coming down behind it in the same order, and a frase over a part not yet
  here stays silent and dimmed until that part lands; a tap on the frase of a part that could not
  be fetched fetches it again. A part the room lost stays under the draft, its frases silent.

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
- Let a Back-translation resume land first too. Rejected at first because it plays a part on
  landing; accepted by ENG-1788 with the floor held until every part is here.
- Play what the tablet holds and step over the parts on their way. Rejected: it rewrites the
  ruler.

## Consequences

- A fetch failure on a Rehearsal resume no longer sends the team to the Choice.
- A Back-translation resume no longer waits for its parts; only the refusal re-read does.

## Amendment · 2026-10-30 (ENG-1964)

**No entry lands on the Rehearsal or the Back-translation any more** (ADR 0141, amended by
ENG-1964): a passage picked on the Choice lands on its conversation, as hers. The resume no
longer lists the room's takes or brings parts down at entry, so no part is on its way when the
team lands: the parts on their way, their dark rows and their fetch one at a time are left
with no way in, and a follow-up slice of ENG-1964 removes their code. The recording home the
orange dot opens lays the room's parts in under their rows as its listing answers (ADR 0141). The telling-back is
opened from the home, and on entry it reads the frase that awaits from the room and brings back
the sentence the tablet holds, as hers does on every entry.
