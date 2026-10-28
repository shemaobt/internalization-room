---
status: accepted
date: 2026-10-28
amends: 0137 (in part: a failed open with a passage left lays that passage back instead of resting on the Choice)
---

# The passage left waits under the Choice, and a failed open lays it back

This amends ADR 0137 without editing its decision: it adds "amended by 0143" to its status
line. Her app is the bar: the session stays in memory under her picker (`app/page.tsx:407`),
the chevron only shows it again (`:408`), and an open that answers no session falls back to it
(`:786`), the Panorama included (`:980-981`).

## Decision

- **A leave from a Canvas holding a session keeps that Canvas in memory.** What the team saw
  and could do there comes back as it was: the session, the necklace, the moment, the last line
  for «hear again», the warning it stood under. Only one is kept, the last one left.
- **The chevron lays it back and asks the room for nothing.** No wheel, no session read, no
  scenes, no inbox: the watch is armed as on any opened Canvas and the session is held on disk
  again, so a relaunch lands where it did before the leave. Offline it works the same.
- **An open from the Choice that brings no session lays it back too.** A pill the room cannot
  be reached for, a refused pill, a resume whose read fails and a session the room turns out
  to have lost during the open all land on the passage left, as hers does. With no passage
  kept they rest on the Choice as ADR 0137 decided.
- **What is kept goes when another passage opens.** An open from the Choice lets it go when it
  ends anywhere but back in it; the next leave replaces it; the room letting its session go
  takes it with the session; a new life starts with nothing kept.
- **Unchanged.** A Panorama left still returns through the machine as before (ADR 0062), a
  Canvas with no session still returns through the resume, and the left entry's own pill still
  enters through the resume and asks the room.
