---
status: accepted
date: 2026-10-22
---

# An outside listener is a number per version, and listener audio never meets a model

The Definer settled it on 22 October (ENG-1421, ENG-1422), after Marcia's spec of 5 September
(`docs/CHECAGEM-EXTERNA-SPEC.md` at 18fa7c4) and her rulings of 8 and 15 September.

## Context

The external check is the last step before Refine: people who did not translate hear the
approved passage and say what they understood. Her app numbers them per release, stores every
recording the moment it stops, and lets no model and no speech recognition near that audio.
Ours had nothing of it, and every other recording door on the room transcribes.

## Decision

- **One external check per approved version**, opened by the team with one tap and never
  closed or locked: a new version opens a new check; the version does the work of a gate.
- **A listener is a number**, the next of that version, strictly increasing, never reused,
  unique even when two tablets ask at once; no name, photo or sign-in is ever asked or stored.
- **Every listener recording is stored as it stops**, with its type, measured duration, size,
  fingerprint and time, attached to the listener only after the bytes are safe; a closed
  tablet loses nothing already said, and an abandoned listener reads «started, not finished».
- **Listener audio never meets a model**: no transcription, no recognition, no prompt, on the
  tablet, the Desk, the record, the dossier or the export. The door that stores it is a door
  of its own, so no flag can route it to the transcriber.

## Consequences

The Desk and the export read listeners from the same records. Storage grows with every
recording and nothing is deleted. The room protocol stays «um ouvinte por vez».
