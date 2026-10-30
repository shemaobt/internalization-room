---
status: accepted, amended by 0168 (the verdict's sound no longer raises a halt that waits)
date: 2026-10-29
amends: 0029, 0036, 0044, 0159
---

# A halt raised on the Back-translation waits for the Conversation

This amends ADRs 0029, 0036, 0044 and 0159 without editing their decisions. It marks 0029 and
0036 "Amended by 0160" under their titles and adds 0160 to the status lines of 0044 and 0159.

Marcia's handoff is drawn only on her canvas (`app/page.tsx:1063`, at 18fa7c4). Her Drafting,
which holds her back-translation, returns before the canvas (`:944`) and keeps no phase, so
nothing on it raises the handoff. A verdict whose sound fails there goes back to rest
(`app/components/Drafting.tsx:1540-1543`): no second try, no handoff, nothing else silenced,
no capture touched. Her verdict is kept before it plays (`:1537`), so «ouvir a resposta de
novo» still offers it (`:2413`). ENG-2009 brings ours to hers. Her frozen app wins over these
ADRs and over Henok's rulings of 25 September.

## Decision

1. **A halt raised on the Back-translation is not drawn there.** It waits for the Canvas, as
   ADR 0159 decided for the Scene rehearsal and the Checagem externa. On the Back-translation
   such a halt comes from the verdict's sound failing twice (it calls a person), from the
   build guard, or from an `Error` in a hand-off (neither calls).
2. **It cuts nothing.** No sound is silenced: a part, a stretch, a translation or a verdict
   plays on. No capture closes: the microphone stays open and the circle's tap sends the take.
   The circle, «terminei», the approval and the way back still answer.
3. **It rises only on the Conversation, as the halt it was.** «Pronto» after the approval
   takes the team straight there. Then the sign rises, and it calls a person only if the
   halt did: one from the build guard or an `Error` still calls nobody, and its tap reads
   nothing (ADR 0125). If two halts wait, one that calls is never quieted by one that does
   not. Every other way out (back to the Ensaio, the external check) drops it. Hers never
   raises it at all; criterion 1 of ENG-2009 asks for the wait, so it stays. The same
   holds for a halt waiting from the Scene rehearsal or the Checagem externa.
4. **A line the room serves, heard to its end on the Back-translation, lets the waiting
   halt go.** A verdict whose sound failed twice and is then heard through «ouvir a
   resposta de novo» leaves nothing waiting, so the Conversation does not call a person for
   a reply the team already heard. A bundled fixed line says nothing of the room and lets
   nothing go.
5. **A verdict whose sound failed twice is still offered by «ouvir a resposta de novo»**, as
   hers, unless it is the fail-safe verdict, which is never remembered.

## Considered Options

**Drop the halt outright on the Back-translation.** That would match hers on the one path
where the two differ, «pronto» to the Conversation. Rejected for now because ENG-2009's first
criterion names the wait, and a build that cannot reach the room would otherwise never tell
anyone.

**Keep the sign there, as ADRs 0029, 0036 and 0044 did.** Rejected: it is not hers, and it
silenced and closed things her screen keeps going.

## Consequences

ADR 0029's withheld sound on the way in, ADR 0036's undone capture and ADR 0044's lift replay
and its guard over a cut, a pending translation or a retell are no longer reached by a halt
raised on the Back-translation. A blocking halt can still be carried onto it when it was
already standing as the team arrived, from the Ensaio or a resume. There those rules still
apply.

## Amends

- 0029: a halt met on the way in no longer withholds the sound; the part plays.
- 0036: a halt that lands inside a capture on the Back-translation no longer closes it.
- 0044: «a halt silences every station» no longer covers the Back-translation, and the lift
  replay there is reached only by a halt carried in.
- 0159: item 3 is reversed. Item 2's «once raised on the Canvas it calls for a person» now
  holds only for a halt that called; one from the build guard or an `Error` rises calling
  nobody.
