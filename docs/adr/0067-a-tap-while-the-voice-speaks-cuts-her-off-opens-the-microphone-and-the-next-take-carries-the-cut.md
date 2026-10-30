---
status: accepted, amended by the one-reply Opening (2026-10-12: the Opening is her single reply, with no two-movement script; ENG-1303, shema-api #712, this app's #320), by ENG-1901, by ENG-2039 and by ENG-2108
date: 2026-10-07
amends: 0053, 0013 (in part: the first tap also cuts the voice), 0024 (in part: the interruption's stop is the machine's), 0046 (in part: the invariant)
---

# A tap while the voice speaks cuts her off, opens the microphone, and the next take carries the cut

Superseded in part by the one-reply Opening (ENG-1303; shema-api #712, this app's #320): the
Opening is now her single reply, with no two-movement script. The decision below that a cut
ends "both movements of an Opening" and remembers the Scene with its Panorama reads as a cut
in the one reply, which ends the line; the rest of this record stands.

Amended by ENG-1901 (2026-10-28, João's rule of 26 October: Marcia's frozen app 18fa7c4
wins): the Panorama's circle no longer ignores the tap. Hers has one gesture handler for
every session, the Panorama included, and a tap while she speaks stops her and opens the
microphone there too (`app/page.tsx:843-874`). `Interrupted` reduces on the Panorama as on
the Canvas, with the same rules: her opening, her reply and «Ouvir de novo» are cut, the
acknowledgement with the reply queued is cut at its start, and the Panorama's next take
carries the cut. Wherever this record says the interruption reduces only on the Canvas,
read the Canvas and the Panorama; the thinking voice and the note still ignore the tap.

Amended by ENG-2039 (2026-10-29, the same rule): the capture guard this record leans on
is hers, `MIN_TAKE_MS = 700` (`app/page.tsx:24` at 18fa7c4). Its window counts from the
recorder's start, not from the tap: a stop tap under 700 ms of recorded time is ignored
and the take goes on (`:896`), and a take shorter than the window is a ghost: nothing is
sent and the circle returns to its rest (`:812`). Hers also drops an empty take; this
room drops any take under 800 bytes, the floor ADR 0046 keeps, so a long take lighter
than that is thrown away here and sent in hers. Both hold on the conversation's and the
Panorama's takes, and on the take a cut opens; a tap while the recorder is still
starting does nothing, because nothing has been recorded yet. The raised hand's question
is not one of them: it keeps counting from the tap, because its second tap always ends
it and is never ignored.

Amended by ENG-2108 (2026-10-30, the same rule): the raised hand's question is held to no
time floor at all. Hers drops a note only when its file is under 800 bytes
(`app/page.tsx:363` at 18fa7c4); the note's stop tap has no window (`:841`), and
`MIN_TAKE_MS` is read by the conversation take alone (`:812`, `:896`). The hand keeps the
800-byte floor and asks nothing about how long the question ran, so a short real question
reaches the facilitator's desk here as in hers. The window and the ghost rule above stay
the conversation's and the Panorama's.

This amends ADRs 0053, 0013, 0024 and 0046 without editing their decisions; it adds
"amended by 0067" to the status lines of 0053 and 0046 and a note under the titles of 0013
and 0024. The Definer settled the rules on the ticket (ENG-1447) on 7 October; the
Orchestrator settled the mechanism and the invariant the same day. The server half (shema-api #643) reads three optional form fields on a turn.

## Context

On the Canvas, a tap while the Guide spoke was ignored: the team had to wait her out before
the circle would listen. In Marcia's app a tap stops her where she is and opens the
microphone, and the take that follows tells the server it followed an interruption, and
where. No ADR said in words that the tap was ignored.

## Decision

- **The tap on the Canvas's circle while the Guide speaks cuts her and opens the
  conversation's microphone, as one gesture event**, `Interrupted`. It reduces only on the
  Canvas, with no blocking halt, and only while a guide or approved line speaks, or the
  instant acknowledgement speaks with the reply queued behind it. Its effects are
  `[StopTheSound, OpenTheMic]`, in that order.
- **The interruption's silence does not pass through the one silence of ADR 0024.** Its
  bookkeeping is the Station's quieting (what was heard, the playback callbacks, the
  cursor), and its stop is the machine's `StopTheSound`; no `GestureSilenced` is
  dispatched.
- **The cut point is measured on the voice player before the stop.** `at` is the line's
  position; `of` is the line's length only when the player knows the clip's real duration,
  that is for a clip it opened whole, from a file on disk or from the app's own assets,
  never the estimate a streamed clip is bounded by. Until her line is open, the player
  answers no position and no length, and a stop that lands before then ends the line
  unsaid: it never plays.
- **The cut rides the microphone and then the take, and leaves with the take's send.** A
  take the capture guard refuses, a discard, a refusal and a generation move drop it. No
  field of the notifier holds it.
- **A cut line counts as heard** (`Said.cut`). The reply is remembered whole for «Ouvir de
  novo», and the turn settles as played: the end of the passage, the network health and the
  calm count. Its cue for the team to talk among themselves is not given: they already
  spoke over her.
- **A cut ends the whole line, both movements of an Opening included.** The movement being
  spoken gives `at` and `of`. A cut in the first movement remembers the Scene with its
  Panorama and does not say the Scene, whether the Opening is said for the first time or
  heard whole again.
- **The acknowledgement:** a tap while the instant acknowledgement plays with the reply
  queued cuts the acknowledgement and drops the queued reply. It reports `at = 0`, and `of`
  only when the reply's length is known, and remembers the reply.
- **The thinking voice, the Panorama's circle and the note keep ignoring the tap.**
- **ADR 0046's invariant "the microphone never opens under a sound" is sharpened** to
  "`OpenTheMic` over a sound only when a `StopTheSound` comes before it in the same effects". That is the
  order `_startListening` already gives in two events back to back; one event carries both,
  so no queued line drains into the silence between them.

## Considered Options

**`GestureSilenced` then `MicOpened`, as `_startListening` does.** Rejected: between the
two events the Channel is silent, and a queued line can drain into it; the reply waiting
behind the acknowledgement would start under the microphone the tap is opening.

**The runner measuring the cut when it runs `StopTheSound`, and answering the machine
afterwards.** Rejected: the measure must precede the reduce that carries it, or the event
would carry no cut. ADR 0066's "port work is the runner's" holds for the stop, not for the
reading; the Station reads the Sound port before it dispatches.

**A notifier field holding the cut until the next send.** Rejected: every way a microphone
ends without a take would need its own clearing, and a missed one sends a stale cut.

**`of` from the streamed clip's estimate.** Rejected: it is read at the slowest plausible
bitrate to bound a wedged line, so it errs long, and the server would store it as a fact.

## Consequences

- The Canvas's circle has a gesture while the Guide speaks; ADR 0013's first tap also cuts
  the voice.
- A turn after an interruption carries `interrupted=true`, `interrupted_at_ms` and, when
  known, `interrupted_of_ms`. A server without them ignores the fields.
- The voice player answers its line's position and length to the room.
