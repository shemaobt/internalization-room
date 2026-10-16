---
status: accepted
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
  Back-translation and the Closing) every spoken line plays in the Session language: her fixed and process
  lines, the lines the server names for a turn, the Panorama and the back-translation
  verdict, and the recorded assets (offline notice, microphone blocked, stranded take). A
  retry of an entry opens it in the language it was opened in.
- On the Choice the team is in the room, not in a session, so a spoken line there follows
  the Room language, whether the way back is live or not. A session left open does not
  decide what the Choice says.
- The screen still follows the Room language (ADR 0077).

## Consequences

After the way back, the screen can be Portuguese while the voice stays English. The warm of
a line and its play ask for the same language, so a warmed line is the one that is heard.
