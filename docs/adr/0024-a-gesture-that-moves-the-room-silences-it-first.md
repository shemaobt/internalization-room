# A gesture that moves the room silences it first, in one place

## Context

The room has two independent players: the rehearsal's (`PlaybackRepository`, one sounding
instance) and the **Guide**'s voice (`FacilitatorVoiceService`, its own instance, its lines
serialised against each other). Neither touches the other, so two sounds at once are always
a **Take** under a line or a line under a take.

Only `_clearAll` silenced both, and it is called by the gestures that leave a passage. Every
phase change inside the **Back-translation** was a bare `copyWith`. So the approval press
played Marcia's approved **Process line** over the last listening; the circle tap in the
findings phase repeated the verdict over the **Stretch** that was sounding; the next
**Part** started under the one before it; the failed-part fallback to the **Rehearsal**
silenced nothing; and no microphone path stopped the Guide, so the room listened to the
team while still talking to them.

A second defect sat under the first. The retro's hold on a clip is a pause, fired
unawaited. just_audio's `pause()` opens with `if (!playing) return;`, and during a load
nothing is playing yet — so a hold issued while a clip was still opening was a silent
no-op, and the `play()` waiting behind the load started the very clip the team had just
stopped.

ADR 0019 says no station of the room is a dead end; ADR 0021 says a stretch plays the place
it sits in.

## Considered Options

Silencing inside each gesture. Rejected: it is the defect. Thirty gestures move the room,
each one would carry its own two stops, and the ones that were added were added one bug at
a time.

One shared player for the Guide and the rehearsal, so a new source always replaces the old
one. Rejected: the **Conversation** and the rehearsal need the two independent, and the
voice's serialisation would queue the rehearsal behind whatever line was being said.

Awaiting the silence before every sound. Rejected: latency on thirty gestures for an order
the player already guarantees — just_audio flips `playing` synchronously, and a stop
interrupts a load rather than queueing behind it.

Stopping the rehearsal player on every transition, without exception. Rejected on evidence:
`PlaybackRepository.stop()` clears `_openedLength`, which is the length the listening
ceiling counts down and the length `_fimDeParte` measures a part's end by. Three gestures hold a clip
the room comes back to — the scissors, the circle that closes a capture, and telling a
stretch again from the cord — and stopped, the part they return to would be measured by a
player that no longer answers for it: the ceiling would fall back to the generic six
minutes and the cord would shrink under the team. The playback double hid this: its `stop`
kept answering `playingLength` for a clip it had stopped, so the suite read green over it.

## Decision

**Every gesture that moves the room to another action silences it first, through one
private method of the notifier that every transition passes.** It closes the open span of
the **Listening ledger** exactly the way a hold does, stops the Guide's voice, silences the
rehearsal player and clears every flag that says something is sounding, so the next tap
finds nothing playing. It never cancels the room's timers, never bumps the epoch and never
touches the recorder: those belong to `_clearAll`, which leaves a passage rather than moving
inside one. `_clearAll` calls it instead of its own two stops.

**Only a play/pause toggle on the sound itself is exempt** (ENG-742): a second tap on the
same listen button pauses, a third resumes, and neither counts as a transition.

**The rehearsal player is stopped, except where the gesture holds a clip the room may come
back to** — the scissors, the circle tap that closes a capture, and telling a stretch
again. The first two leave the very **Part** they are standing in, and the next listening
carries it on from where it stopped; stopped instead, the room would lose the length the
listening ceiling and the end of the part are measured by. Telling a stretch again holds
for the same reason when it is reached from the cord, where the part is what is in the air.
Reached from the grid the clip is the **Stretch**'s own slice or the telling, which nothing
resumes, and there the hold is merely harmless — it is kept so one gesture has one
behaviour rather than two. The Guide is stopped either way, and the silence takes one flag,
named for that fact.

**The microphone opens on a silent room**: in the rehearsal, in the back-translation and in
the conversation, the silence runs before the recorder starts. **A part goes in the air on
a silent room too**, and the silence sits inside the one method that puts one there, so the
crossing at a part's boundary, the last listening of a checked passage, the next part and
the landing on a part nobody heard all pass through it — the screen's crossing is a branch
of the listen button, not the `proximaParte` the ticket's matrix names, and that branch was
the first symptom the ticket reports.

**A stop is not a pause, and the room reads the playhead before it stops.** just_audio
extrapolates `position` only while the player is playing: `pause()` writes the playhead
down before it stops playing, `stop()` does not, so a read taken after a stop answers with
the stale place the clip was opened at. The division point of a stretch is read above the
silence, and the span of the **Listening ledger** is closed above it too. In the hold branch
the order is the old one, because there the pause has already frozen the playhead.

**What the clip owed the room dies with the clip.** A stop clears the playback callbacks,
as leaving a passage does. Left armed, the listening ceiling of a part that was still
loading fires a whole clip later, on a room that has long since moved on, and ends a part
under the team.

**A hold that arrives during a load wins over the load.** `PlaybackRepository` counts the
holds asked of it and reads that count after the awaited load: when a hold arrived while
the source was opening, the open does not play and leaves the player stopped. The opening
still announces itself with the length it measured, because the listening ceiling and the
measure of the part in the air both hang off that announcement and a clip that never
announces itself strands them. A `PlayerInterruptedException` raised by the load because of
our own stop is caught at that one boundary and read as the clip not playing — never as
this tablet failing to play the team's own voice, which calls for a person.

A tap the room ignores is not a gesture that moves the room, and silences nothing: the
circle tap does nothing in `playing`, `thinking` and `conferida`, and silences only in
`capturing` and `findings`.

## Consequences

Thirty gestures are re-routed through one line each; the ledger's rules, the toggles'
hold and resume, the ceiling, the **Outbox** and the **Resume point** are untouched.

The playback double gained a stop counter, now clears what it answers for `playingLength`
when it is stopped, and now answers `position` with the place the clip was opened at once
it has been stopped — the three ways it used to flatter the room, as the real one does.
That is what turns the rejected option above from an argument into a measurement: a blanket
stop fails four tests that were green before, and reading a playhead after a stop fails two
more.

The harness keeps one ordered log of sound — the two players and the recorder write to it —
so a test asserts that the room went quiet before its next sound without one double reading
another, and without asserting which private method ran.

`proximaParte` and `retellChunk` have no caller in the presentation layer and are reached
only from tests; they keep their silence and their rows, because the ticket's matrix names
them and a button may be wired to either tomorrow.

Two tables, one per station, list the ticket's matrix by name and fail if a row is missing,
so a transition added later that does not silence is a red test rather than a bug the team
hears.
