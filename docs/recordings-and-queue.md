# Recordings and the outbox

## Nothing here deletes audio a team made

Every capture — conversation utterances, questions, Rehearsal takes, back-translation
stretches — is written under the app's documents directory. Nothing else is fetched into
it today; a part fetched back from the room would land there too, because the resume point
refuses to pick a session back up unless every part's file is still on disk. A recording a
part was replaced with is left beside the one it replaced. That is the rule: audio a team
recorded is never removed, and a second directory would only be a second thing to keep
alive.

Capture survives interruption. A call, an alarm or another app taking the microphone pauses
the take, and the recorder comes back on its own when the interruption ends rather than
staying paused for the rest of the Rehearsal. While the microphone is held elsewhere the
room stops drawing a live capture, but it keeps saying which touch ends the take, because
the take is still open.

## The outbox

The room needs the server: every turn, every verdict and every line the **Guide** says is
made there, and none of it happens without a connection. What the outbox answers is a
connection that comes and goes, never a session worked without one.

Takes and stretches waiting to reach the server are copied into the outbox, whose manifest
survives the app closing. Each row names its file rather than an absolute path, so the
outbox still finds the audio after a restore or a reinstall changes the container prefix.
The copy is kept after upload: the Rehearsal and the back-translation are the team's
product.

Each row's last attempt is stamped in UTC, and the stamp alone is read leniently while every
other field is read strictly. Why that asymmetry is worth having is in ADR 0016.

Writing a recording off is a guess about the disk, never a verdict. A row whose audio the
outbox could not find is looked at again on every flush, and the moment the file is back at
the path it reads, it is sent. Audio that is genuinely gone still falls out, so the outbox
still empties, and the team is still told.

## The resume point

The outbox directory also holds the resume point: where each passage was left, so leaving
one lands the team back there rather than at the start. It carries the place of every
stretch mended by the Long way, for the reason ADR 0007 gives. It follows the
outbox's own rule — each take stored by name and rejoined against the recordings folder at
read time — so a restore, a reinstall or a new tablet never leaves the whole Rehearsal
pointing at a container prefix that is gone. Rows written by earlier builds carried the
whole path and are still read.

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
