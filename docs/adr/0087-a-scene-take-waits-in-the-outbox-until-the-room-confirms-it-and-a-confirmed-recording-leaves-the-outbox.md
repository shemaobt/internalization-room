---
status: accepted, amended by 0104 (2026-10-20: the scene take announces its recording time, length and fingerprint) and 0103 (2026-10-20: a take refused for good is told by its row, not the voice)
date: 2026-10-16
amends: 0083, 0025
---

Extended by 0120 (a join row carries `origin` and the rehearsal's fingerprint)

# A scene take waits in the Outbox until the room confirms it, and a confirmed recording leaves the Outbox

This amends ADRs 0083 and 0025 without editing their decisions; it adds "amended by 0087"
to their status lines. The Definer settled it on 16 October (ENG-1347).

## Context

The scene take went straight to the keep door. A failed keep left the screen on the record
step with nothing said, the take orphaned in `recordings/`, and nothing ever sent it again;
a tablet closed mid-keep lost it. Marcia's app holds the take, says «guardando o ensaio da
cena…» while it goes, and on a failure shows her words with «falhou — toque para tentar de
novo», which resends the same recording. The **Outbox** already carries every other take
across failures and relaunches. It also kept every row the room had stored, for good.

## Decision

- **The scene take goes up through the Outbox,** as a row of kind `cena` with its scene
  label, leaving through the scene-rehearsal keep door. The rows of one session leave in
  the order recorded, as a part's do (ADR 0025); a row refused for good holds nothing.
- **The confirmation is the keep door's answer with the rehearsal.** The tablet announces
  no size or duration: the room measures the take, checks the bytes it stored, and gives
  the same bytes sent twice the same rehearsal, so a resend after a lost answer never mints
  a second one. The tablet never counts a number.
- **Not confirmed, the take waits** in the Outbox under the Outbox's own rules, and the
  screen shows her save-failed words with the retry and the circle. A retry resends that
  row with its tries given back, still behind an earlier scene take of the session. A take
  over the room's 25 MiB is never sent: the Outbox refuses it for good without a byte, and
  the screen shows her too-large words with the same retry. Reopening the red microphone
  while a take of the session still waits to go up shows that take before the room's unsent
  rehearsal. A take refused for good is not waiting: it stays in the Outbox and on the
  tablet, the house's stranded-recording line tells it, and the red microphone reopens the
  room's unsent rehearsal (the Definer, 16 October). A take the room confirms on any flush
  while the screen shows it not kept opens on translate.
- **The keep's failures are the Outbox's,** not the Failure policy's at the scene door
  (ADR 0083 no longer covers the keep): a gone session leaves for the Choice, a code that
  stops the room turns it away, a network failure falls. A keep that fails never calls a
  person.
- **A confirmed recording leaves the Outbox,** of every kind, with its copy in `guardadas/`.
  The room's names for the rows confirmed in this app run stay in memory, so a recording
  still learns its name and the machine still sees a part land. Rows an older app wrote as
  stored are shed on the next write.

## Consequences

The row carries the name of the team's own take, and the Outbox renames that take to the
rehearsal's name before the confirmed row leaves the manifest. A tablet killed in between
still holds the row, sends it again, gets the same rehearsal for the same bytes, and names
the take then: a reopening never downloads a take the tablet holds. Nothing the team
recorded is deleted on the way: the Outbox deletes only its own copy. The team's keep or
retry makes due every scene take of the session waiting ahead of it, except one refused for
good. A row refused for good, a take too large for the room included, holds no one behind
it even within the pass that refused it, a part's recording as much as a scene take
(this narrows ADR 0025, whose pass held the rest of a part behind any row that did not
land).
