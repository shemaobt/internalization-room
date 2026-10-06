---
status: accepted
date: 2026-10-06
amends: 0053
---

# The microphone answers the machine, and the take comes back on it

This amends ADR 0053 without editing it; it adds "amended by 0057" to its status line. The
Definer and the Orchestrator settled it on 6 October while the microphone left the notifier
(ENG-1455).

## Context

The effect runner now opens, closes and discards the microphone through the Recorder port.
ADR 0053 did not settle four things.

First, a gesture that closes the microphone needs its take, and the take is the recorder's
answer to an effect the runner runs.

Second, an opening and a close are answered at different moments. An opening can answer a
minute late, while the platform asks for the permission. A close answers within moments, and
its gesture waits on it.

Third, the notifier guarded a late start in two ways. A start that answers after the
generation moved closes the Channel if it is still the newest, and is discarded if it
started. A start that answers after a halt landed, or after its capture was closed, is
discarded.

Fourth, the notifier opened the recorder with an owner it derived again from the Station,
not the one the machine opened the microphone for.

## Decision

- **The microphone answers in one event.** The runner answers the machine with
  `MicAnswered`, naming a `MicAnswer`: started, refused, failed, closed (with the take, or
  none), discarded (the room's `CloseAndDiscardTheMic`) or abandoned (a late start that had
  started). A start only records itself. Every other answer gives the Channel back the way
  `MicClosed` does, through the same handler. A refused or failed microphone is that
  answer, not a row of the failure policy: a recorder is not the room.
- **The machine keeps how the microphone last answered**, as it keeps how the last line
  ended. The notifier reads it on the transition and does the Station's work there. It
  hands the take to the gesture waiting on it. On a refusal it undoes the listening and
  shows the permission gate. On a failure it undoes the listening and counts toward a halt.
  On a start it resets that count. On a discard it undoes the listening.
- **Two gesture events reach the recorder.** `MicClosing` asks for the take: `reduce`
  answers it with `CloseTheMic` and leaves the Microphone open until the recorder answers,
  so no waiting line drains into a microphone still recording. `MicDiscarded` gives the
  Channel back at once and asks for `DiscardTheMic`. The plain `MicClosed` stays as the
  Station's own close.
- **An opening is stamped when it opens; a close when it comes back.** A stale opening is
  dropped by `reduce`. A take always reaches the gesture waiting on it.
- **The late-start guards stay where they were, moved, not widened.** The runner keeps
  which start is the newest. A late start that is still the newest closes the Channel; if
  it started, the runner discards it and answers abandoned. A start that answers after a
  halt landed, or after its capture was closed, is discarded: the runner asks the Station
  whether it still keeps the start. `CloseAndDiscardTheMic` discards only when the
  microphone was open, or when a conversation, question or panorama start is still in the
  air, as the Station says.
- **The recorder opens for the effect's Microphone owner.** It equals the derived one on
  every door, except the question, which the recorder treats as a conversation.
- **The Recorder port** starts a take for an owner and answers started, refused or failed;
  stops and hands back the file, or nothing; discards; and signals a call taking the
  microphone. The runner listens to that signal once, and the Station hears it through
  `hearTheMicrophoneTaken`, as it hears the hold and the run of a part.

## Considered Options

**Refused, failed and closed as fields of `MicClosed`.** Rejected: the Station's own close
would carry an answer it never has.

**The runner's own bookkeeping decides the late discards for every start.** Rejected: a
question sent, or a rehearsal take finished, while its start is still in the air would
discard a recorder that today keeps recording. That is a behaviour change, and it belongs
to its own ticket.

**`micTaken` read from the machine.** Rejected: more state and another generator arm, for no
behaviour.

## Consequences

- `EffectHost` opens, stops and discards nothing. It answers two questions about a start
  and hears the call that takes the microphone.
- Two closes in flight hand back their takes in the order the recorder answers them.
