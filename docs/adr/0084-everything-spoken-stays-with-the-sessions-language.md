# Everything spoken stays with the session's language

Supersedes the last sentence of ADR 0077's Decision, «Fixed and process lines stay on the
Room language». The rest of ADR 0077 stands.

## Context

The team can now choose the Room language on the Choice while a session is left open. The
way back to that session keeps its Session language (ADR 0077), and the server names the
turn's fixed lines in it. A tablet that played the lines it asks for in the Room language
spoke a session in one language and its acknowledgement, its fail-safe and its approval in
the other, and warmed one language while playing the other.

## Decision

- Every spoken line plays in the language of the session in force: her fixed and process
  lines, the lines the server names for a turn, the Panorama and the back-translation
  verdict, and the recorded assets (offline notice, microphone blocked, stranded take).
- The Panorama speaks the language it was opened in. Before a session exists, and on the
  Choice, the Room language decides, so a session left open does not decide what the Choice
  says.
- The screen still follows the Room language (ADR 0077).

## Consequences

After the way back, the screen can be Portuguese while the voice stays English, as in her
app. The warm of a line and its play ask for the same language, so a warmed line is the one
that is heard.
