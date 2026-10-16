---
status: accepted
date: 2026-10-16
amends: 0054
---

# A scene take is WAV, an accidental tap leaves nothing, and a recording made again keeps the one before

This amends ADR 0054 without editing its decision; it adds "amended by 0086" to its status
line. The Definer settled it on 16 October (ENG-1347).

## Context

OBT Refine receives the team's **Scene rehearsal** as well as the **Rehearsal**, and
Marcia's app records the scene take in the same raw format as the part. Ours recorded it as
AAC with the room's own filters on. A finger brushing the circle became a kept rehearsal, or
a **Part** that, when it held no bytes, raised a blocking **Halt** and called a person. And a
part or a translation recorded again deleted the recording it replaced, against her rule of
1 October that nothing the team recorded is deleted without her word.

## Decision

- **A scene take is recorded as a Part is**: 16 kHz, mono, 16-bit WAV, echo cancellation on
  and no noise suppression or automatic gain, declared `audio/wav` on the keep door, which
  also carries the scene's label when one is given. Only a tablet that answers it cannot
  encode WAV records it as AAC, with the same filters off. The Part keeps no such fallback:
  its format is the deliverable rule of ADR 0054.
- **An accidental tap leaves nothing.** A scene take or a Part whose WAV `data` chunk holds
  less than 0.3 s, or no readable one, or a compressed take under 800 bytes, is dropped in
  silence: nothing kept, nothing pending, no halt, no line, no person. Its file goes, since it
  is not a take. The audio is measured from the `data` chunk, not the file's size, because
  the platform writes chunks before it. A Part the recorder handed back no file for still
  halts. The Back-translation's **Capture** keeps its own rule.
- **A recording made again deletes nothing.** The Part and the translation it replaces stay
  on the tablet. A replaced translation still leaves the **Outbox**, so it never goes up as
  a telling of the whole passage.
- **A scene microphone has no maximum length.** Only the team's tap, the way back or a halt
  closes it.

## Consequences

The tablet keeps more audio than before, and it is never cleaned by the app. The room's
facilitator no longer sees a call for help when a team taps the circle by accident. Scene
takes already stored as AAC stay as they are; the room and Refine hold both formats for good.
