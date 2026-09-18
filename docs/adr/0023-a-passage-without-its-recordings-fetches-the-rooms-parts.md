# A passage resumed without its recordings fetches the room's parts

## Context

A **Resume point** names the files of the rehearsal the team left. A restore, a reinstall
or another tablet leaves the row naming files that are not there any more, and the room
still holds every one of them: the **Part**s went up as they were recorded.

The tablet refused such a resume. It rewrote the row at the **Conversation** with no takes
in it and sent the team there — so the rehearsal the room was holding could never be
reached again, and a team that had told half the passage back recorded it a second time
over stretches the session still had. A **Back-translation** row asked the room to throw
its stretches away and start over, or landed at the approval with nothing to play.

ADR 0022 kept the takes listing and the take-audio URL for exactly this, and ADR 0019 says
no station of the room is a dead end.

## Considered Options

Asking the room to restart the telling-back, which is what the retro branch already did.
Rejected by Henok on 17/09: it is cheaper and symmetric, and it throws the team's
recordings away — the one thing this family of tickets exists to stop.

Refusing the rehearsal and sending the team straight to the back-translation, where the
audio could be fetched. Rejected: it decides for the team which station they are on, and
a rehearsal row says they are not in the telling-back.

Rewriting the row at the conversation when a file is missing, as before. Rejected: it is
the defect. A row with no takes makes the next opening find nothing to restore, and the
rehearsal is out of the team's reach for good.

Halting for a person when the room holds no rehearsal at all. Rejected: a room with
nothing behind this passage is not a failure and not a rehearsal to come back to. The
conversation is where a passage with nothing behind it starts, and the row is left alone
so a room that does hold the rehearsal can still hand it over.

## Decision

A passage reopened past the conversation whose files are not all here fetches the room's
current **Part**s and lands at the **Resume point** the team left — the rehearsal or the
back-translation — with the stretches the room holds.

The current parts are the newest `ensaio` recording under each number, in the order the
room lists them: the server's own rule, so a part recorded again is the one the team gets
back (ADR 0020). A telling-back is never one of them.

**A part is numbered by its place in that row, not by the number the room holds.** The two
agree for every rehearsal this tablet sent up — it sends the number and the scope from the
same count — and where they cannot, the place is what a part is addressed by everywhere
else in this room: the cord draws it there, a **Stretch** sits on it there (ADR 0021), the
**Ruler** measures it there, and recording it again finds it there. A recording the room
does not number is therefore the part of the place the listing brings it in, rather than a
take outside the row of parts, which would be played by nothing and measured by nobody.

A file still on the tablet under a current part's name is kept as it is: it is the team's
own recording, and fetching a copy would spend their network on what they already have.

**A fetch that fails calls for a person and keeps the resume point.** The listing, one
part's audio or the disk — any of them leaves the row byte for byte as it was, opens no
session turn and asks no restart. Parts already kept may stay on disk; they are not
written into the row. The way out is the one ADR 0019 names, and the next opening tries
again and lands the team where they stopped.

A link that is merely down calls for a person here too, rather than showing the offline
circle the rest of the room answers `RoomUnavailable` with. The ticket names it — "room
unavailable, timeout, one part of three" — as one case with one answer, and the reason to
keep it one is that the team is standing in front of a passage they have worked on, and a
room with no written word cannot tell them that half of it is here and the rest is not. A
facilitator can.

The two answers that retire a session — no such session, no such passage — are not fetch
failures and do not halt. This is the first call that names the remembered session on a
resume, so they arrive here now, and they go on to the handlers that start the passage
clean: swallowed, every opening would ask a dead session for a rehearsal and call a person
with nothing to resolve, which is the dead end ADR 0019 forbids.

**The row is rewritten only with the recordings the room gave**, never without them
because a file is missing.

The restart of the telling-back is retired on this tablet: the branch that called it, its
client route and its answer are gone, and nothing else called it. The server's route stays
where it is, now with no caller.

## Consequences

`RoomRepository.restartBackTranslation` and `BackTranslationRestart` are gone. The
take-audio URL ADR 0022 kept unread now has its caller.

`TakeView` reads `kind` off the wire. The rule that a recording the listing numbers stands
for a part is still the contract ADR 0022 leans on for placing a stretch; here `kind` is
read as well, because a telling-back played as part of the story would tell the team their
own explanation back.

The **Listening ledger** is kept by file, so a fetched part starts with nothing heard and
the team listens again before *terminei* — the same rule a part recorded again follows.

A fetched part carries the room's own take id and no **Outbox** row, which is the shape
`_pathForTrecho` already resolves. Nothing is queued for it: it is already in the room.

Numbering by place and ADR 0022's placement read the same fact two ways, and they disagree
the moment the room lists a rehearsal recording it does not number: the placement resolves
a stretch by the room's ordinal against a scope name this now numbers by position, so every
part after the unnumbered one is one place off. No tablet produces such a listing — a
rehearsal take goes up with its number — and reconciling them means rewriting the placement
ADR 0022 just settled, so it is left written down here rather than half-changed.

A fetch that failed leaves its parts on disk under names the row never learned, so the next
attempt fetches them again, over the link that failed.

A resume whose files are all here asks the room nothing, exactly as before.
