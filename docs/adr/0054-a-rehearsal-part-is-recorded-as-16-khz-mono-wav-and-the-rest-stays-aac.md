---
status: accepted
date: 2026-10-06
---

# A rehearsal part is recorded as 16 kHz mono WAV, and the rest stays AAC

## Context

OBT Refine receives the team's **Rehearsal** as its deliverable. Marcia's app records that
draft on the tablet as uncompressed 16 kHz mono 16-bit sound and keeps every other
microphone, the telling-back included, compressed (`app/lib/wavRecorder.ts:1-15`, at
18fa7c4). Ours recorded every **Take** as AAC, so Refine got a lossy file.
The server could have transcoded each upload instead, but a lossy file transcoded is still
lossy. The tablet records the part without loss, or nobody can.

## Decision

A **Part** of the **Rehearsal** is recorded on the tablet as 16 kHz, mono, 16-bit PCM WAV,
in a `.wav` file, and goes up to the room declared as `audio/wav`. That holds the first
time it is recorded and every time it is recorded again on the **Long way**. The
**Capture**, a stretch told on the **Back-translation** or told again on the **Short way**,
stays AAC in `.m4a`, as in her app, while losing the room's own filters as the part does.
The **Conversation** turns and the questions stay AAC with every filter on.

A take fetched back from the room is named by what its bytes are, not by what the tablet
expects: a RIFF/WAVE header is kept as `.wav` and anything else as `.m4a`, because the
player chooses its parser by the extension. Takes already stored as AAC stay as they are.

## Consequences

Once WAV parts are stored, the room and Refine hold both formats for good, so this does
not reverse by flipping the encoder back. The `.m4a` that a reader finds on the
**Capture**, beside a `.wav` **Part**, is the decision and not drift. A WAV part is about
1.9 MB a minute. Past about 13 minutes one take passes the server's 25 MB cap, which the
parts of a rehearsal stay well under.
