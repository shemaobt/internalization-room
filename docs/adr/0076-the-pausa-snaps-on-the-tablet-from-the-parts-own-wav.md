---
status: accepted, amended by ENG-1231/ENG-1737 (2026-10-21: a part with no envelope keeps its pausa at least 0.2 s after the last one, and places none where the part has no room for 0.2 s; the scissors are gone, and the circle's first tap places the pausa)
date: 2026-10-13
amends: 0040
---

# The pausa snaps on the tablet, read from the part's own WAV

ADR 0040 says "the scissors only cuts". This amends that wording only: the scissors place a
**pausa**, which lands in the middle of the nearest silence of the part rather than at the
raw tap, and three controls move it and play it. The scissors still never translate. It adds
"amended by 0076" to 0040's status line. Nothing else in 0040 is edited.

## Context

A team taps a beat after a sentence ends, so a stretch cut at the raw tap often ended inside
the next word (pilot day 3). Marcia's app snaps the tap to the middle of the nearest gap in
the speech. Her server computes each take's loudness envelope and the browser fetches it.
Since ADR 0054 our rehearsal parts are 16 kHz mono PCM16 WAV files already on the tablet.

## Decision

**The tablet reads the loudness of the part from the part's own WAV file, once per part, and
snaps the pausa locally.** No envelope is fetched from or stored by the server. A part that
is not a PCM16 WAV has no envelope, and its pausa stays exactly at the tap, with no bounds
and no adjusting. A part heard to its end ends its stretch at the part's end, never at its
last silence. The rules (8 % of the 98th-percentile loudness, 150 ms, 1.5 s back and 0.25 s
ahead, a silence after the tap counting double, 200 ms from the cursor, 100 ms from the end)
are hers, kept in one pure module that the Ensaio Final check and the scene rehearsal reuse.

## Considered Options

**A server envelope, as hers.** Rejected: it adds a route and a stored artefact to shema-api
for data the tablet already holds, and a pausa would wait on the network in a room that has
to keep working while the server is out of reach.

## Consequences

Stretches stored from now on end in silences. Stretches already stored keep their ends. The
first pausa in a long part reads the whole file synchronously, which costs a moment on the
tablet. A part kept as m4a, from before ADR 0054, behaves as before.
