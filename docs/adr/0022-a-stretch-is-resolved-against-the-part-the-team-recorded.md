# A stretch is resolved against the part the team recorded

## Context

ADR 0008 answered a **Mend** by having the server assemble a new recording of the whole
**Part** — the original with the wrong **Stretch** cut out and the mended one in its place
— which the tablet downloaded and installed under the part's own scope. The part became
the file the server had built, and every stretch of it was a slice of that.

Marcia's rule of 07/09 and ADR 0021 took the mend away: the unit re-recorded is the unit
the team rehearsed. The server's ADR 0025 says the rehearsal that reaches Refine is the
team's own recording, and the module that assembled passages is gone with it. What was
left on the tablet was a cold-resume walk with no producer: a session told back before
this still answers with a stretch addressed to a recording this tablet has no part for,
and the walk fetched that file and swapped it in under the part's scope.

## Considered Options

Keeping the download as a fallback for sessions told back before this. Rejected: it
installs, under the part's own scope, a file the team never performed — the very thing
Marcia refused — and ADR 0025 has removed the side that produced it.

Dropping the placement too, and letting such a stretch fall to the part its predecessor
sits on or off the cord altogether. Rejected: the **Necklace** is the only place a team
who cannot read sees where their work went, and a band drawn over the wrong part is a
worse answer than none.

## Decision

The tablet resolves every **Stretch** against the **Part** the team recorded, never
against a recording the server assembled. Nothing is downloaded for a stretch.

A resumed **Back-translation** whose stretches name a recording this tablet holds no part
for asks the room's takes listing once and reads each such recording's ordinal, which is
the number this tablet gave that part when it sent it up. Those stretches are placed on
that part and play the part's own recording at the **Place** they sit in (ADR 0021). A
recording the room does not number, and a listing that does not answer, leave the reading
as it was; neither stops the team. A resume whose stretches all sit on recordings this
tablet holds asks the room nothing.

The scope the room gives such a recording is not read. Any recording the listing numbers
answers for the part of that number, whoever recorded it and whatever assembled it, and
that is what places the stretch. The rule therefore rests on the room numbering only
recordings that stand for a part, which is the contract the takes listing already keeps.

Supersedes ADR 0008.

## Consequences

`KeptScope.composed`, `TellingAgain.composedTakeId` and the swap that installed an
assembled file under a part's scope are gone. `keptTakes` is only ever the recordings this
tablet made, so what the team hears on a stretch is always a voice from this room.

The takes listing, the take-audio URL and the take view's ordinal stay. The listing is now
read for placement rather than for a download, and the URL reaches no caller: it is kept
as the door a tablet holding a session's stretches and none of its files will fetch the
room's own parts through.

A stretch on a recording the room cannot number sits on no part: it is not drawn on the
cord and the play steps over it, which is where an unplaceable stretch has always landed.

A stretch keeps the seconds the room gave it inside the recording it names, and those are
now read against the part's own file. A recording assembled around a mend is not the
length of the part it was built from, so a stretch near the end of one can ask for seconds
past the end of the part: its band runs into the next part on the cord and the player is
asked for a range the file does not reach. Accepted rather than clamped — the seconds the
room holds are the only account of where that stretch is, and cutting them would move a
band without anyone deciding where to.
