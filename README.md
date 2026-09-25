# Internalization Room

Voice-first Flutter tablet app for the internalization room of the Shemá oral Bible
translation flow. A team of oral translators works through a passage of Scripture without
ever being shown text: the room speaks, the team speaks back, and everything the room knows
about their progress it shows as beads on a cord.

There are **zero readable words on team screens**, and progress lives only in the necklace —
no numbers, no percentages, no lists.

## Where the design comes from

The visual language is the Claude Design prototype vendored at
`docs/spec/prototype/`, built on the Shemá design system. The interaction model follows the
client-validated *Tripod Internalization · Interaction Flows* document, vendored at
`docs/spec/interaction-flows.html`, with a text extraction beside it for searching. Both are
byte-for-byte copies of their sources; `docs/spec/README.md` records where each came from.

## The six stations

**Invitation** — the breathing circle welcomes the team, and the room's voice presents the
book and then the passage. Which passage a session is for is the room's to say.

**Conversation** — the team describes the passage out loud. Every element of the meaning map
the team engages warms a bead on the necklace; a tap on the hand records a question for the
facilitator, which becomes a knot on the cord.

**Rehearsal** — the team records the whole passage in its own tongue, listens, and either
records it again or keeps it. Kept recordings can be replayed before recording anew.

**Back-translation** — the team's own recording plays back by itself; the scissors cut a
stretch, a tap on the circle records its translation in the bridge language, and the green
check sends it and plays on. Once every stretch is confirmed, the advance disc runs the
check: it lands on a clean verdict, on findings, or straight at a stretch that was recorded
and never told back.
A finding that names a stretch asks the team where the error lives; a finding that names
none offers telling the whole recording again, or going back to the rehearsal to record
ground the passage still lacks.

**Choice** — the team picks the next passage from the wheel.

**Closing** — the cord closes into a circle and the beads glow slowly. It is not where the
team stays: the wheel reopens on its own, and a touch anywhere reopens it at once.

## Running it

`AGENTS.md` has the commands and the toolchain; `docs/setup.md` has signing, the
environment file and the developer shortcuts.

## Where the rest is

- `CONTEXT.md` — the glossary. Every term above is defined there.
- `docs/adr/` — why the room behaves as it does, one decision per file.
- `docs/setup.md`, `docs/backend-seams.md`, `docs/recordings-and-queue.md` — the conventions
  that are neither a decision nor a command.
- `docs/spec/` — the vendored prototype and interaction flows.
- `docs/doctrine/` — Marcia's `DOCTRINE.md`, vendored at a pinned commit of
  `Tripod-Internalization`. It binds every change to this repository, and `ACCEPTANCE_BAR`
  names the test behind each line of its §4.
