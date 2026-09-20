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
count that still says held, so the open returns without ever telling the player to play.

That leaves ADR 0024's own sentence untrue. It says the open "does not play and leaves the
player stopped", and after a resume the player is not stopped: the resume's `play()` is
not swallowed the way the hold's `pause()` is — during a load nothing is playing, so it
passes just_audio's `if (playing) return;` — and it lands on a platform the opening's own
stop deactivated but the load has already reactivated, `_active` being set synchronously.
So it sends the platform a play request, and the clip sounds when the source is ready.
Read in the source of just_audio 0.9.46, not measured on a tablet: the ticket reports a
third tap that plays nothing, and the Test by hand is where that is confirmed.

What the room had, then, was two answers to one gesture: a repository saying the clip is
held and a player already playing it. The rule and the sound had come apart, and the
double had come apart from both — it made sound come out of a clip whose source had not
finished opening, so no test could see either half.

The same window has a second hole, and this one the room hears. Every open begins by
stopping the player, which interrupts a load already in the air; just_audio raises
`PlayerInterruptedException` for it. Read through the hold count, an interruption with no
hold behind it is a device failure, and the room answers a device failure by calling for a
person. So a second play asked before the first clip finished loading — a **Take** over a
take, a stretch over a stretch — halted the room and made it call for a person, over a
sound the team itself had just asked for.

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
states it (that ADR's "A hold that arrives during a load wins over the load", and its
"leaves the player stopped"), because a resume given after that hold now undoes it and
the load's trailing play runs. The repository and the player stop giving two answers to
one gesture: what the room says is held is held, and what it says is wanted sounds.

**An interruption with a hold behind it that a resume has undone is a failure again.**
The hold count marked a clip held for ever, so a device interruption arriving after a
resume was read as our own gesture and swallowed; the room waited on a clip that was
never coming. Read through the wanted state, only a hold still standing excuses an
interruption.

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
armed at a time, as the one knob that arms it always did. It also stopped flattering the
resume — it used to make sound come out of a clip whose source had not finished opening,
and of a clip that had never been opened at all — and stopped answering for the measure
of a clip a stop had cleared while its source was still loading. Those are the fourth,
fifth and sixth flatteries this player's double has had to give up, after the three ADR
0024 names. The double is now pinned directly, by its own tests, and not only through the
room that reads it: a double nobody measures is a double that drifts back.

A team that taps listen twice in a row now hears the second sound, and the room stays in
the station they are working in. The tablet still calls for a person when it truly cannot
play their voice.
