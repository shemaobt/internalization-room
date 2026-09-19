# The player answers every gesture in the order the team made it

## Context

ADR 0024 settled that a hold arriving during a load wins over the load: the player counts
the holds asked of it and reads that count after the awaited load, so a pause the real
player swallowed — just_audio's `pause()` opens with `if (!playing) return;`, and during a
load nothing is playing yet — still stops the clip the team meant to stop.

A count of holds only ever grows, so it answers one question: *did a hold arrive?* It
cannot answer the one the team asks next. A **resume** does not touch the count, on the
reasoning that a resume asks for the very clip it is resuming. Under a load that reasoning
fails: play, hold while the source is still opening, resume, and the load comes back to a
count that still says held. The clip never sounds and the third tap does nothing — the
team taps a third time on a **Stretch** and hears silence.

The same window has a second hole. Every open begins by stopping the player, which
interrupts a load already in the air; just_audio raises `PlayerInterruptedException` for
it. Read through the hold count, an interruption with no hold behind it is a device
failure, and the room answers a device failure by calling for a person. So a second play
asked before the first clip finished loading — a **Take** over a take, a stretch over a
stretch — halted the room and made it call for a person, over a sound the team
itself had just asked for.

ADR 0019 says no station of the room is a dead end, and a **Halt** raised over an ordinary
gesture is the deadest end there is.

## Considered Options

**A resume that re-opens the source.** Rejected: a second load for a clip already loading
is the very corruption the measuring player exists to avoid (ADR 0024), and the team would
wait through two openings for one tap.

**Reading every interruption as silence.** Rejected: an interruption with nothing of ours
behind it is this tablet failing to play the team's own voice, and swallowed, it would
leave the room waiting on a clip that is never coming. That is the case the call for a
person is for.

**Deciding it in the notifier.** Rejected on evidence: the notifier sees a bare event on
`failures` and never the exception that caused it. To tell a superseded open from a broken
file there, the repository would have to hand the cause up, which is the repository's own
rule leaking into the station that consumes it.

## Decision

**The player answers every gesture in the order the team made it, and the last gesture
wins over an awaited load.** `PlaybackRepository` keeps the player's *wanted* state
instead of a count: a pause or a stop holds it, a play, a playRange or a resume wants it.
When an awaited load returns, the open plays only if the player is still wanted. This
keeps ADR 0024's rule — a hold during the load holds — and amends the paragraph that
states it (that ADR's "A hold that arrives during a load wins over the load"), because a
resume given after that hold now undoes it and the load's trailing play runs.

**An open a later open of ours superseded is silent, and is no failure.** Each open takes
its own generation. A load interrupted while a later open of ours has already started
returns having announced nothing and reported nothing: no measure, no opening, no entry on
`failures`. What the clip owed the room dies with the clip, so no listening ceiling and no
measure of the part in the air hang off a clip that never played. A load interrupted with
no open and no hold of ours behind it is still a failure, and the room still answers it
with a call for a person.

A stop keeps the job ADR 0024 gave it, and keeps it against a resume: it clears what the
clip measured, a load settling behind it writes nothing back, and it does not sound even
if a resume has asked for sound in the meantime. A resume undoes a hold; the clip the
room stopped is not the clip it comes back to.

Most gestures reach the player through the one silencing of ADR 0024, so most second
sounds arrive behind a stop. The ones that do not are the chain that plays the whole
rehearsal back, part after part, and the listen on a pending take once its ceiling has
fired. The rule lives in the repository rather than in either of them, so a gesture added
later that opens over a load is already answered.

## Consequences

The hold count is gone. `_stops` stays, because a stop is still the half of a hold that
also forgets the measure.

The playback double gained the load window **per open** rather than one window for the
player: a clip the team superseded and a clip that is merely slow were the same thing to
it, and every test of a second sound queued behind the first one's window. One window is
armed at a time, as the one knob that arms it always did. It also stopped
flattering the resume — it used to make sound come out of a clip whose source had not
finished opening, and of a clip that had never been opened at all. That is the third
flattery this player's double has had to give up, after the two ADR 0024 names.

A team that taps listen twice in a row now hears the second sound, and the room stays in
the station they are working in. The tablet still calls for a person when it truly cannot
play their voice.
