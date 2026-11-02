---
status: accepted
date: 2026-11-02
amends: 0172 (play on a take paused with no pausa)
---

# Play on a take paused with no pausa resumes where it paused, and an ended one starts over

On the scene rehearsal's translate step, a take paused with no pausa pending played on
from the frontier, the place where the translation stopped, on the next play. ADR 0172
named the difference from Marcia's app at Tripod-Internalization 18fa7c4 and left it for
its own ticket (ENG-2095). Hers resumes the chain where it paused
(`app/components/Rehearsal.tsx:663-666`, `togglePlay` → `c.toggle()`;
`app/lib/chainPlayer.ts:187-194`, `play()`), and only a chain that ended starts over from
the beginning.

- A take paused with no pausa plays on from where it stopped, wherever that is: the
  pause tap that could mark no pausa because the tail past the frontier was too short
  for a frase, a playback that failed, the team's own translation stopping the take,
  «manter a tradução de antes» leaving the player inside an earlier frase's replay
  (before the frontier) or at a pause moved later (past it). Hers resumes the element
  where it stands in every one of those; so does the arm.
- A take that played to its end with no pausa left — the untold tail too short for a
  frase, so no pausa was marked at the end — starts over from the beginning, as hers
  (`play()` on an ended chain calls `start()`), not from the frontier as the ticket read
  it. The end is read with `isAtTheEnd`, the 50 ms the sent step has used since 0172.
- A take never listened still plays from the frontier, as her `playFromFrontier` does on
  a chain with nothing loaded.

## Consequences

- The circle on a take paused with no pausa still plays from the frontier. Hers marks a
  cut where the take paused when that is past the frontier (`Rehearsal.tsx:572-581`); that
  difference is older than this record and is left for its own ticket.
- A take whose natural end did mark a pausa (a tail long enough for a frase) is unchanged:
  play drops the pausa and plays on from it, as 0157 and 0172 left it.
