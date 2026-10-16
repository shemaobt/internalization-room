---
status: accepted
date: 2026-10-16
amends: 0083, 0014
---

# The team's scene is a tap on the scene question, read at the record tap

This amends ADRs 0083 and 0014 without editing their decisions; it adds "amended by 0088" to
their status lines. The Definer settled it on 16 October (ENG-1344).

## Context

In Marcia's app a passage of two or more scenes first asks «Qual cena vocês vão ensaiar?»,
and the scene the team taps becomes the label of the next scene rehearsal. A wrong label puts
a rehearsal under the wrong scene for the join, the voice and the consultant, without the team
noticing, so it is never guessed. The tablet held no scene of the passage: no ids, no titles.

## Decision

**The Scene label is the team's tap, read at the tap that starts the recording**, before the
microphone permission is asked. It travels with the take through the Outbox, and a retry of the
upload sends the take's own label, never the screen's. The question highlights one scene and
never picks it. One scene is the label silently; no scene list means no label, and the take is
recorded as before.

**The passage's scenes come from a door of their own**, `GET /sessions/{id}/scenes`, in passage
order with their titles in the session's language. Its failures, of any kind, go through the
Failure policy as one event the machine answers with nothing, as the raised hand's do (ADR
0071): no halt, no call for a person, no fall. ADR 0083's sentence that every failure at a scene
door, a timeout included, raises a halt does not hold for this door.

**The list never stands between the team and its recording.** The open waits for it at most
4 seconds (with the stacked change that brings the waits; until then the open waits for the
list's answer or failure), an idle record step asks again 2 s and 8 s after a miss and then never, and «gravar o
ensaio da cena de novo» asks once more. A list that arrives late is taken, but never relabels a
take already started and never takes the circle away while the microphone opens. A tap within
600 ms of the question appearing, or of the pick, is ignored, so a double tap cannot pick and
record at once.

**Her words are written on this screen.** The question, its buttons («cena N» and the title,
with a numbered badge) and the chip «cena N · título» above the circle are a named exception to
ADR 0014, under the moment label's reason (D8 (a), «A palavra está sempre escrita»). VoiceOver
reads each one's written words; the chip's name adds the question a tap on it goes back to, as
hers does.

## Considered Options

- Reading the scenes from what the tablet holds. Rejected: it holds none.
- Folding the scenes into the scene rehearsal list's answer. Rejected: that list's failure would
  take the scenes with it, and each retry would read every rehearsal again.
