# A halt that lands inside a capture closes it

## Context

ADR 0029 decided what a halt met on the way into the **Back-translation** does: it
withholds the sound and nothing else, because nothing of the team's own is in flight at
that door. A **Capture** — the open microphone between the scissors and the tap on the
circle — is different: it is the team's own act in flight, a recording that has started
and has nowhere written yet. `_haltForAPerson` touched neither the recorder, nor the
phase, nor the outbox; while a capture stood open under a halt, the microphone kept
listening for the whole halt, and the tap that eventually closed it sent everything
recorded during the stop — the team's own halted wait — up as a **Stretch**.

Every other path that stops a recording because the room moved already deletes the
partial audio: leaving the passage, withdrawing the hand's question, the panorama's and
the conversation's listening. None of them keeps it. `_undoTheListening()` is the
unwinding one of them already uses — the recorder that never started — and it puts the
phase and the voice back exactly where a capture leaves them.

## Considered Options

**Keeping the piece for the team to decide on their return.** Rejected: a capture halted
mid-word is not a **Take** the team chose to keep, and every other interrupted recording
in this room is discarded, not offered back. Keeping this one alone would need a screen
of its own for a recording nobody asked to review.

**Refusing to halt until the capture closes.** Rejected: a blocking halt exists because
somebody has to come and look, and holding it behind whatever the team happens to be
recording at that moment defeats the reason it blocks.

## Decision

**A blocking halt that lands while `state.btPhase == BtPhase.capturing` discards the
recorder and undoes the listening before anything else the entry does.** `_haltForAPerson`
gains one guarded step at its top, before `_leaveThinking()` and before the voice
changes: `_recorder.discard()` (stop-and-delete, the same primitive `_clearAll` and the
hand's withdrawal already use) and then `_undoTheListening()`, which puts the phase back
to `playing` and clears the clip's halo. No epoch bump, no `_clearAll`, no call on the
**Outbox**: the watch and the outbox both keep running exactly as they did before the
halt. After the Desk attends, the circle is already back at the invite with nothing
standing, so a tap sends nothing and the scissors open a fresh capture.

The guard is on the phase, not on which gesture opened it: a capture reached from the
findings screen (`traduzirDeNovo` while `btPhase == findings`) is undone the same way,
because `_finishChunkCapture` itself already resolves every one of its own exits to
`btPhase: playing` regardless of which screen opened the capture — "the phase the capture
started from" is the `playing` state a capture interrupts, not the screen the mic was
opened from, and this decision does not change that.

Undoing the phase is not the whole of undoing the capture. `traduzirDeNovo` arms
`_trechoTraduzidoDeNovo` in the same gesture that opens the capture — choosing the mend
*is* opening the microphone on it — so a halt that discards this capture must forget the
mend too, or the next, ordinary tap of the scissors would silently send its recording as
a correction of a stretch the team never chose to touch again, with that stretch's own
bounds rather than the cursor's. The analyst's door (`_levarAoTrechoNaoTraduzido`) arms
the same field in an earlier, separate gesture — it only leads the team to the stretch and
plays it, leaving the capture to the scissors that follow — so a halt discarding *that*
capture must leave the arming standing, exactly as a denied or failed start already does:
the team's next tap on the scissors is still answering the question the analyst asked.
One flag, set where each of the two callers of `_startChunkCapture` already knows which
case it is, tells the guard which of the two a discarded capture was.

## Consequences

The other halts this tablet raises are untouched: the room-decided halt inside
`_finishChunkCapture`'s own no-audio branch already stops the recorder and sets
`btPhase: playing` before calling `_haltForAPerson`, so the guard finds nothing left to
discard; the recorder-that-never-started path already runs `_undoTheListening()` itself;
and the conversation's and rehearsal's own recorders are never in `BtPhase.capturing`, so
the guard never touches them. A warning changes nothing (ADR 0032): it never calls
`_haltForAPerson`, so the capture is never interrupted by one.

The recorder double's `discard()` was an empty no-op with nothing to read; it now logs
`recorder:discard` into the room's one ordered log of sound, beside `recorder:start`, so
a test can read that the microphone closed the way it reads everything else the room
does — from outside, never from a private method.
