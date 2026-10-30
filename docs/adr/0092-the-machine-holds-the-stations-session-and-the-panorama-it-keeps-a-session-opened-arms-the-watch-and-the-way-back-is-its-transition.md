---
status: accepted, amended by ENG-1977, amended by ENG-1900
date: 2026-10-20
amends: 0053, 0062
---

# The machine holds the Station's session and the Panorama it keeps, a session opened arms the Watch, and the way back is its transition

Amended by ENG-1900 (2026-10-30): the way back to a held passage is offered and live at once; the machine's waiting entry decides it. As in her app (`app/page.tsx:408`, `:950-956`), the chevron
shows whenever a passage is held under the Choice, is always live, and its tap lays the passage back with
no call to the room. The transition itself stands.

Amended by ENG-1977 (2026-10-30): the Panorama also comes back in silence when its line was cut
before it was heard but the tablet holds the line that began to speak; it offers «Ouvir de novo»
and asks the room nothing, as hers (openOnce.ts:83). The Decision below stands for every other case.

This amends ADR 0053 and ADR 0062 without editing their decisions; it adds "amended by 0092"
to their status lines. Settled on the ticket (ENG-1705), 19 and 20 October.

## Context

The machine held every region of the room but three facts of the session. The passage's
session lived in the screen state, the Panorama's session there too, and the Panorama's id
and language in a field of the notifier. «A Station's open arms the Watch» was three calls in
the notifier, and the way back (ADR 0062) was decided there, by a switch on the entry left.
Two rules answered "which session is this": the Station's, and the passage's or else the
Panorama's.

## Decision

- **The machine holds the sessions.** It holds the passage's session and the Panorama it
  keeps across the Choice: the Panorama's id, the language it was asked in, and its session
  once the room opened one. The Station's session is the Panorama's at the Panorama and the
  passage's anywhere else. The Choice keeps the Panorama and drops the passage's session; a
  new passage keeps the Panorama; starting over drops both.
- **A Panorama asked again** in the same language keeps its session; another language or
  another Panorama lets it go.
- **A session opened arms the Watch.** The room's answer to a Station's open is one event,
  stamped with its generation; its one transition holds the session and arms the Watch.
- **A session let go** leaves the Panorama when it is the Panorama's.
- **The way back is a transition.** Taking it, the machine decides: a Panorama whose line was
  said, on the session it still holds, returns in silence and arms the Watch; any other
  Panorama is asked for again in the language it was left in; a passage is entered again in
  its language. What the notifier still does for each is handed over to it (ADR 0066). The
  gesture keeps only the preparation every gesture makes before it moves the room: for a
  Panorama left, it silences the room and leaves the Step before the machine decides; a
  passage's entry does the same on its own way in.
- **One rule for the session.** Every question of "is this the team's session" asks the
  Station's session; any other is an earlier session.

## Considered Options

**Keep the passage's session in the screen state.** Rejected: two homes for "the session"
made two rules for it.

**A Station event for the way back, answered by every Station.** Rejected: seven Stations
for one decision the machine takes once, from the Choice.

**Reset the notifier's fields one by one instead of moving them.** Rejected for the reason a
Life is born whole: a field added tomorrow is missed.

## Consequences

- The one-session rule changes three edges, none of which the team sees or hears:
  - On the Choice, an answer that the Panorama left is gone or closed lets that Panorama go
    quietly, and the way back is no longer offered; the Choice is not discarded and read
    again.
  - On the Conversation while a passage's session is being created, such an answer no longer
    discards the passage being opened.
  - A passage left before its session exists never records the Panorama's session as its
    own.
- The screen state's copy no longer takes a session.
- A later slice adds session facts to the machine, never to the notifier.
