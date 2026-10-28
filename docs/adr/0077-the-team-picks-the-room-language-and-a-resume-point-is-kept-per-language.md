# The team picks the room language, and a Resume point is kept per passage and language

Supersedes ADR 0015. Amends ADR 0031 (a row created in another language no longer drops it).

Superseded in part by ADR 0084: the last bullet of the Decision, on fixed and process lines.

Amended by ENG-1866 (2026-10-28): the second bullet of the Decision. Choosing a language on
a Choice that holds its Wheel no longer reads the Wheel again from the room. As in her app,
the words change where they stand: the list stays on screen, no thinking circle shows, and
nothing is asked of the room, offline too. Only the passages started in the language chosen
are read again, from the tablet, and a read that fails leaves the list as it was. The choice
is still a machine event that moves the generation, so a read for an earlier choice is never
applied; the Wheel is read again from the room only while the Choice holds none.

## Context

The tablet took its language from the device's settings, falling back to English, and the
choice could only move in a debug build, by starting the room over. A tablet set to English,
Spanish or Japanese gave a Brazilian team an English session with no way out, while in her
app a session is Portuguese unless the team taps «EN» on the passage menu, and each passage
keeps one session per language. The server already keeps one session per team, passage and
language (ENG-1236), but the tablet kept one Resume point per passage: a session opened in
the other language overwrote it, and coming back to the first language lost where the team
had stopped.

## Decision

- The **Room language** is the team's choice on the tablet, remembered across launches, and
  Portuguese when nothing was chosen. The device's language never decides it. The choice is
  read before the room launches, so nothing reads a choice still on its way from the disk.
- Choosing a language changes the screen at once and the language of the sessions opened
  from then on. It never starts the room over: the way back to the entry left stays. On the
  Choice it is a machine event that moves the generation and reads the Wheel again, so a
  Wheel read for an earlier choice is never applied.
- A session's language is fixed at the tap that opens it and never moves. The way back to an
  entry, a relaunch onto the Current session and a retry of the same entry all open it in
  the language it was opened in, whatever the Room language is now. A relaunch lands on the
  Current session whatever its language (ADR 0064): a tablet updated from the app that took
  the device's language keeps its English Current session until the team leaves it.
- A **Resume point** is kept per passage and language. A row the shipped app wrote, keyed by
  passage alone, is read as the row of the language it carries, and is left as it was until
  the team's next transition in that language; a row with no language answers for none and
  marks nothing started, and leaves with the passage's next transition. A passage is started
  only in the languages it holds a Resume point in.
  Closing a passage forgets only the closing session's language.
- Fixed and process lines stay on the Room language, as in her app.

## Consequences

One passage can hold two Resume points and the server two sessions, one per language. The
server's floor for a request that names no language is Brazilian Portuguese too.
