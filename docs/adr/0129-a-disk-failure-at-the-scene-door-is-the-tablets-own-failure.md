---
status: accepted
date: 2026-10-22
---

# A Disk failure at the scene door is the tablet's own failure, told on the scene screen, and one take is kept by one write at a time

## Context

The scene door fetches a scene rehearsal's take, or one of its frases, from the room and
keeps it on the tablet's disk. When that keep failed, the notifier decided it as a network
failure at the scene door. Since ADR 0108 a network failure that is no turn's changes
nothing, so a disk that could not keep the audio left the scene screen silent, and the team
was not told why the rehearsal did not open.

Two keeps of one take could also run at once: the open's reopen of an unsent rehearsal was
still in the air when the team tapped that same row. Both wrote the same staging file, the
first rename moved it, and the second rename threw. That throw reached the same catch, so a
take already in place read as a failure.

ADR 0089 (a scene microphone failure changes nothing) and ADR 0108 (no failure line is
spoken, no failure face is drawn) stand. The Definer settled the word on ENG-1706.

## Decision

- **A Disk failure at the scene door is the tablet's own failure.** The Failure policy
  decides it on the tablet, never as a room result. On the Scene rehearsal the machine
  tells the screen; on any other Station it does nothing. It never raises a Halt and never
  calls a person.
- **The scene screen carries the disk word**, «não deu para guardar o ensaio da cena neste
  computador», on the Step it stands on: as the semantics of the record and listen steps,
  which stay wordless, and as her line on the translate step. It is never spoken and adds
  no control: the team's next tap on the row fetches again. A take the room did not keep
  keeps its own word and retry on the record step.
- **The word stands until the team's next gesture.** Every gesture of the team clears it
  before the gesture acts, whatever it is: a row, a frase, a scene, the circle.
- **The failure lands only on the rehearsal it was fetching.** A keep that fails after the
  team moved the screen on tells nothing.
- **One take is kept by one write at a time.** A keep of a name already being written gets
  that write's result, the same file or the same failure. Once the write settles the name
  is free, so a later keep writes again.

## Considered Options

**A fifth room result for the disk.** Rejected: no room call produces it, and it would
force a case into the Outbox and the device link, which never meet a disk, and amend
ADR 0047's four results for a failure the glossary already files under the tablet's own.

**A spoken disk line.** Rejected: ADR 0108 and her rule «never expose the failure
mechanics».

**Sharing the download in the notifier.** Rejected: it needs a new notifier field per
Life, and the collision is in the write, which every keep of fetched audio shares.

**A staging file of its own for each keep.** Rejected: one take is written through one
staging file at a time.

## Consequences

A Disk failure on the scene screen calls no one and leaves the screen where it stood, with the
word. The failure log names it «o disco falhou». The kept retellings and the sentence
downloads also keep through the one write per name, and keep their own failure handling;
they are not scene doors.
