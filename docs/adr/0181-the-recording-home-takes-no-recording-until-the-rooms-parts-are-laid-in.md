---
status: accepted
date: 2026-11-05
amends: 0117 (a home opened over a room's parts waits until they are laid in)
---

# The recording home takes no recording until the room's parts are laid in

This amends ADR 0117 without editing its decision; it adds "amended by 0181" to its status
line. Henok decided on 4 November that the rows take no tap while the tablet does not know
what the room holds, and the Definer settled on the ticket (ENG-2162) on 5 November that this
means the parts laid in, not the listing's answer.

## Context

ADR 0117 rebuilds the tablet's parts from the room's listing on a relaunch. The home opens at
once and lays the listing in behind its rows: it reads the listing, then fetches each part's
clip, up to 310 s each. In the hand test of 4 November the home stood with empty, lit rows for
8 to 20 seconds while the room held the four parts, and a tap on «Gravar» would have recorded
over one. The reviewer measured the same on the three relaunch paths, where the listing
answers in time and «Gravar» stays lit until the clips land.

## Decision

- **From the home's opening until its parts are laid in, its rows are dimmed and take no tap,
  and the home says «pensando…».** The record controls, the sheet door and the grain controls
  wait, as they do while a grain switch is in the air. «Ouvir» plays what the tablet holds and
  stays live (ADR 0177).
- **The wait ends when the parts are laid in, or when the listing read fails.** A failed
  listing read opens the rows with what the tablet holds: the tablet then knows nothing of the
  room's parts.
- **A row whose clip failed to come down stays shut.** The listing named the part, so the
  room is known to hold it; the other rows open once laid in. The row's retry and «trazer de
  volta» stay available. The next opening of the home tries the clip again.
- **It holds on every opening of the home that reads the room**, not only after a relaunch: a
  grain switch to the whole, the read after a join, and the dot over parts the tablet holds.
  The wait is bounded by the listing's 20 s and the clips' own limits.
- **The lay-in belongs to the generation that opened the home.** A lay-in of another
  generation neither holds the rows nor opens them.

## Consequences

- A team that stays offline cannot re-record a part whose clip failed. A take over that part
  would go up as the next pass and make it the room's current part, since the room refuses
  nothing for a higher pass, so the row stays shut instead.
