# Recordings and the outbox

## Nothing here deletes audio a team made

Every capture — conversation utterances, questions, Rehearsal takes, back-translation
stretches — is written under the app's documents directory. A passage the server composed
around a mend is fetched and written there too, under the composed take's own name, because
the resume point refuses to pick a session back up unless every part's file is still on
disk. The older recording the mend was cut out of is left beside it. That is the rule:
audio a team recorded is never removed, and a second directory would only be a second thing
to keep alive.

Capture survives interruption. A call, an alarm or another app taking the microphone pauses
the take, and the recorder comes back on its own when the interruption ends rather than
staying paused for the rest of the Rehearsal. While the microphone is held elsewhere the
room stops drawing a live capture, but it keeps saying which touch ends the take, because
the take is still open.

## The outbox

Takes and chunks waiting to reach the room are copied into an outbox with a manifest that
survives the app closing. Each row names its file rather than an absolute path, so the
queue still finds the audio after a restore or a reinstall changes the container prefix.
The copy is kept after upload: the Rehearsal and the back-translation are the team's
product.

Each row's last attempt is stamped in UTC. A stamp sitting ahead of the tablet's own clock
counts as already due — otherwise a clock moved backwards, or a timezone change across a
restart, would leave every queued recording waiting on a moment that never comes, and
silently, because a row that is merely never ready is neither exhausted, lost, nor stalled,
and those three are the only states the room says out loud. A stamp that is not text at all
reads as no stamp, so the row comes due now. Only the stamp gets that tolerance: every
other field is read strictly, and a bad one still sets the whole manifest aside, because a
row whose file or session cannot be read points at nothing the queue could send.

Writing a recording off is a guess about the disk, never a verdict. A row whose audio the
queue could not find is looked at again on every flush, and the moment the file is back at
the path the queue reads, it is sent. Audio that is genuinely gone still falls out, so the
queue still empties, and the team is still told.

## The resume point

The outbox directory also holds the resume point: where each passage was left, so leaving
one lands the team back there rather than at the start. It carries the place of every
stretch mended by the Long way, because that is the one thing about a telling-back the
server cannot hand back. It follows the outbox's rule for the same reason — each take is
stored by name and rejoined against the recordings folder at read time, so a restore, a
reinstall or a new tablet never leaves the whole Rehearsal pointing at a container prefix
that is gone. Rows written by earlier builds carried the whole path and are still read.

A resume point whose recordings are genuinely absent is rewritten, at the Conversation and
with no Rehearsal in it, as it fails: the next opening then finds nothing to restore and
goes straight through instead of running the same failed resume every time. It is rewritten
rather than dropped because the session identifier lives only there, and dropping the row
would abandon that session on the server the moment the team closed the app before reaching
the Rehearsal. That is also why a resume point that cannot be written speaks. It shares a
disk with the outbox, so it borrows the outbox's stranded-recording line rather than adding
a second one, and that line is guarded to play once per session so a failing disk never
becomes a chant. A resume file that exists but cannot be parsed is never used as the base of
a write — the rows of every other passage are in it — so the write refuses and speaks
instead of reporting a place it never saved.
