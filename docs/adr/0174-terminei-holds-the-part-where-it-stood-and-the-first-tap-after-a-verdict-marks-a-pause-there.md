---
status: accepted
date: 2026-11-02
amends: 0024 (the gestures that hold a clip)
---

# «terminei» holds the part where it stood, and the first circle tap after a verdict marks a pause there

This amends ADR 0024 without editing its decision: it adds "amended by 0174" to its status
line. Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket
(ENG-2132).

## Context

ADR 0024 stops the rehearsal player on every gesture that moves the room, and names three
that hold the clip instead: the scissors, the circle tap that closes a capture, and telling a
stretch again. «terminei» was not among them, so the finish stopped the part the team had been
listening to, and by the time the verdict landed no clip was running, paused, at its frontier
or ended. The circle's first tap after a finding found nothing to mark and did nothing; the
team had to press play, pause and tap again before a frase could be told. Her `runCheck` and
`approve` only pause the chain (`Drafting.tsx:1483`, `:1601`), the verdict plays on its own
element, and `onBtCircle` with no retell and no pending cut marks the cut at the chain's paused
position (`:1303-1311`), or the end cut when the chain stands at the take's end.

## Decision

**«terminei» joins the gestures that hold the clip.** A playing part is paused where it stood
and kept beneath the verdict line, which hands it back when it ends; a part already held stays
held; a part at its end is held at its end. After a verdict that leaves the team on the tell
step, the first circle tap marks a pause at that head, snapped as any pause is, and at the
part's end it is the end cut, as before. The pending pause itself is still dropped before the
room is asked (`setPendingCut(null)` in her `runCheck`), so the tap marks afresh. A verdict
that routes elsewhere — an untranslated stretch, a frase that awaits, a stretch sent back to be
told again — starts its own sound over the held part, exactly as it did over silence, and a
checked telling leaves the circle idle as before.

## Consequences

- After her P2 (a part unheard) pressed mid-part, «ouvir» goes on with the held part, as a held
  part already did under the armed replay (a169cd4f, from her toggling chain), rather than
  starting the first part from the beginning. When that part ends, the armed replay still
  starts from the first part; hers goes on with the next clip. That difference is left for its
  own ticket.
- A «terminei» pressed while a told frase replays over the held part pauses the replay with the
  part beneath it; the first tap after the verdict then does nothing, as the circle does during
  a replay today, and play resumes the replay, which hands the part back when it ends. Hers
  keeps the frase on its own element and cuts the chain. That difference is older than this
  record and is left for its own ticket.
