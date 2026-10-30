---
status: accepted, amended by 0103 (2026-10-30, ENG-1868: the tablet's own fixed lines follow the Room language, as in her app)
date: 2026-10-15
supersedes: 0077 (in part: the last bullet of its Decision, «Fixed and process lines stay on the Room language»)
---

# Everything spoken stays with the session's language

## Context

The team can now choose the Room language on the Choice while a session is left open. The
way back to that session keeps its Session language (ADR 0077), and the server names the
turn's fixed lines in it. A tablet that played the lines it asks for in the Room language
spoke a session in one language and its acknowledgement, its fail-safe and its approval in
the other, and warmed one language while playing the other.

## Decision

- Inside a session (the Conversation, the Scene rehearsal of ADR 0083, the Panorama, the Rehearsal, the
  Back-translation and the Closing) the Guide's replies, the lines the server names for a
  turn and the lines the room names for a verdict or a fail-safe play in the Session language,
  and so do the recorded assets (offline notice, microphone blocked, stranded take). A
  retry of an entry opens it in the language it was opened in.
- The lines the tablet itself plays follow the Room language, as in her app (frozen 18fa7c4,
  where the instant acknowledgement and the recording screens' P, N and X lines use the
  interface language): the instant acknowledgement, her process lines (P), the First listen
  and Ensaio Final lines (N) and the external check's lines (X). They are warmed and played
  in the same language, the Room's.
- On the Choice the team is in the room, not in a session, so a spoken line there follows
  the Room language, whether the way back is live or not. A session left open does not
  decide what the Choice says.
- The screen still follows the Room language (ADR 0077).

## Consequences

After the way back, the screen can be Portuguese while the Guide stays English; the acknowledgement and the tablet's own process lines are Portuguese, as on the screen. The warm of
a line and its play ask for the same language, so a warmed line is the one that is heard.
