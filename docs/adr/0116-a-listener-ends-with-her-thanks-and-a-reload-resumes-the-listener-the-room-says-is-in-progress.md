---
status: accepted (amended by 0136, amended by 0138)
date: 2026-10-23
---

# A listener ends with her thanks, and a reload resumes the listener the room says is in progress

Her app at Tripod-Internalization 18fa7c4 is the bar (`ExternalCheck.tsx`: `enterDone`,
`postFinish`, `anotherListener`, `finishCheck`, the resume). The Station is ADR 0114, the
listener's first steps ADR 0115; the doors are shema-api ADR 0083 (a listener's facts, the
finish, the first finish kept).

## Context

A listener's retelling landed and the station stood still: nothing ended a listener, nothing
told the room they were done, and a reload or a restart forgot the listener in progress, so a
stranger halfway through was asked to begin again under a new number.

## Considered Options

- **The tablet's own Step as the resume.** Rejected: the room decides what is done. A retelling
  the room stored whose answer was lost would be asked again.
- **The Step stored beside the number.** Rejected: every rule of where to stand follows from
  the room's record of the listener; a stored Step would never be read. The Station in the row
  says where to stand.
- **Her "same tab" memory, gone with the app.** Rejected: a reload and a restart both resume;
  the Resume point is the house's durable memory (ADR 0046, ADR 0077).
- **Every listener in the check's open answer, her shape.** Rejected: one listener's facts are
  all a resume needs, and the open's answer stays ADR 0114's.
- **«Outro ouvinte» back to «Novo ouvinte» first, hers.** Rejected: «Outro ouvinte» asks the
  next number at once.
- **The resend of the finish holding the team until it lands.** Rejected: hers moves on; a
  lost finish reads on the Desk as started and not finished, which is what the room knows.

## Decision

- Until the frases arrive (ENG-1431), a listener ends when the retelling lands: X-thanks in the
  Session language, the check mark, «Agradecemos sua ajuda.», «Outro ouvinte» and «Terminar a
  checagem». The finish goes up once, `completed: true` (the Definer's Q72); both
  buttons send it again only when the room never acknowledged it, and a resend that fails
  holds no one.
- «Outro ouvinte» starts the next number exactly as «Novo ouvinte» does. «Terminar a checagem»
  goes back to the Back-translation and reads the session again, so its count of listeners is
  the room's. Nothing closes the check.
- The tablet remembers the listener in progress in the Resume point as version and number, from
  the number the room gives until «Outro ouvinte» or «Terminar a checagem». The back control
  keeps a listener whose retelling landed and lets go of one whose retelling did not (the
  Definer's Q74): the next entry asks a new number, and the empty listener stays on the room
  started and not finished. A retelling still in the air when the team leaves decides when
  it answers: kept by the room, the listener stays in progress and the next entry is their
  thanks; not kept, they are let go. A relaunch, which is no deliberate leave, still resumes. A
  remembered listener of another version is forgotten.
- A relaunch whose row stood on the check, and a tap on «Checagem externa», ask the room for
  that listener and land silent: finished → the thanks, nothing resent; a retelling stored →
  the thanks, and the finish goes up; else → the retelling, circle open. A read that fails
  stays on the Back-translation with her open-failed words and the listener remembered; a
  listener the room does not know is the session gone.
- The approved landing (ADR 0106) writes its Back-translation row before it goes on to the
  check, so a crash between the two relaunches on the Back-translation.
- The launch sweep deletes the listener retellings a killed app left, as it does the frases.

## Consequences

`em_curso.json` gains an optional `listener`; older rows read as no listener. The Back-
translation reads the session on every leave of the check. Another tablet remembers no one of
this tablet and takes the room's next number. A listener whose retelling landed reads
complete on the Desk.
