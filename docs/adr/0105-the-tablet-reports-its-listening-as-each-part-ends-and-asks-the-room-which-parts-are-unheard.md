---
status: accepted, amended by ENG-1852 (2026-10-29: after her P2 at «terminei» nothing plays until the team presses play, as hers), ENG-2054 (2026-10-29: «terminei» and the line under it follow the room's count, not the last part's end) and ENG-2109 (2026-10-30: beside the room's count, every part played here or told)
date: 2026-10-20
---

Extended by 0123 (every recording asks the room on every entry; every part unheard is the First listen, N0 on a joined recording and P0 on one no join touched, which ENG-1206 gave the first entry; the mark that a part was recorded again is gone, and a listen on a recording no join touched shows no «ainda falta ouvir», as hers).

# The tablet reports its listening as each part ends and asks the room which parts are unheard

The Listening ledger lived only in memory and reached the room only with «terminei», so an
app that left in the middle of a listen lost every part heard before it, and after a part
was recorded again playback started at the first untold ground with no word of why. The
room now adds reports up per take and answers every report on ADR 0070's listen door with
the parts it still counts as unheard (shema-api ADR 0074). The Definer settled the rest on
the ticket (ENG-1419) on 19 and 20 October.

## Decision

- **The tablet reports the ledger on the listen door** as each part ends, on the
  Back-translation or on the Rehearsal, when it leaves the Back-translation or the passage,
  and when the app is paused in the background. «terminei» still carries it on the check.
  A report never closes a span still open, except the app going away, which stops the
  sound: that report closes the span at the position it reached. A failed report changes
  nothing the team sees or hears.
- **The ledger holds what sounded**, from where the sound started to where it stopped, on
  the Back-translation and on the Rehearsal alike. One start opens at the part's nought: at
  the cursor, when that cursor stands on ground already told back of that part, because that
  ground was heard when it was told. Any other start (a lifted halt, a landing, a replay from
  the middle) opens where the sound starts.
- **The room is the only counter.** Which parts are unheard is always its answer; the tablet
  adds only a part the room has not named yet, which nobody can have heard.
- **Entering the Back-translation no longer forgets the ledger**; leaving the passage does.
  Listening on the Rehearsal therefore counts.
- **After a part is recorded again**, the next entry into the Back-translation asks the
  room. Some parts still heard: her P2 is said, and only the unheard parts play, in row
  order, each from its beginning, stopping after the last with «terminei» lit. Every part
  unheard: her opening line P0 and the whole recording, every part from its beginning. In
  both, the screen says «ainda falta ouvir um trecho da gravação» until the last of those
  parts has played, a stretch told back meanwhile included. No answer, or a room too old to
  name the parts: today's path.
- **A refusal for unheard parts** (`PART_UNHEARD`, her P2) plays nothing: see the
  amendment below. A verdict that names unheard parts with no refusal, which only a room
  older than 19 October sends, starts nothing: see the second amendment below.
- The replay has no rule for a blocking halt: under ADR 0093 none of her six cases can land
  while it plays, and a Session read saying `needs_person` changes nothing.
- The reports, the mark and the replay's list live in the notifier beside the Retro screen's
  other fields, under ADR 0046's written exception, until that screen moves to the machine.
- The mark that a part was recorded again arms only once this passage's Back-translation
  was entered in this life, a resume that landed on it included: a scene recorded again on
  the Rehearsal before the first entry leaves that entry on today's path, with no P2 and no
  P0, because the first entry is the first listen's (ENG-1408).
- The mark lives in memory only: a relaunch between the recording and the entry takes
  today's path, without P2.

## Considered Options

**Count on the tablet.** Rejected: two homes for the gate's rule, and the dossier, the
release and the tablet could disagree.

**Persist the ledger on the tablet.** Rejected: the room's merge per take keeps what was
reported, and a second tablet on the session would not see a ledger kept on the first.

## Consequences

- One small request per part end. It is never awaited.
- Against a room without ADR 0074 the reports replace each other, so the app must reach
  production after it.

## Amendment · 2026-10-29 (ENG-1852)

Her frozen app is the rule (João, 2026-10-26), and hers plays nothing after the refusal: it
writes «ainda falta ouvir um trecho da gravação», says P2, reads the passage again, once more
1.5 s later when the first read is not complete, and clears the line once the room counts
every part heard (`Drafting.tsx:1515-1527`, at 18fa7c4). «terminei» stays dark meanwhile,
because her check needs the passage heard (`Drafting.tsx:2340`).

So after a `PART_UNHEARD` refusal at «terminei» nothing plays. The line stays, under
«terminei» too, and «terminei» is dark. The play control then replays the recording from its
first part, every part in passage order, whichever part the room named and whether or not
this tablet holds it, as ADR 0123 rule 7.1 does after an incomplete listen. When the last part
ends the line clears and «terminei» lights. Right after the refusal the listen door is asked
once with nothing to report, and once more after 1.5 s if a part is still named; an answer
naming none clears the line and lights «terminei» with nothing played. An answer that comes
back after the team has pressed play changes nothing: the replay's last part clears the line.

The refusal's replay keeps living in the notifier beside the Retro screen's other fields,
under ADR 0046's written exception.

## Amendment · 2026-10-29 (ENG-2037)

No room sends a verdict that names unheard parts without a refusal any more: since
19 October the room names them only on `PART_UNHEARD` (tripod-backend 3d6b3481), and hers
has no such answer at all, only the 409 the amendment above follows (`Drafting.tsx:1515`, at
18fa7c4). The rule that played every part such a verdict named, in row order, is withdrawn.

A verdict that names unheard parts with no refusal, or untold parts at all, is read as the
verdict it otherwise is: the parts it names start nothing, and nothing goes in the air on
their account. The untold parts were refused on their own until that same day; that refusal
is gone from the room, and the tablet no longer reads the field. A `PART_UNHEARD` refusal keeps the amendment above.

Amended by ENG-2054 (2026-10-29, João's rule of 26 October: Marcia's frozen app 18fa7c4
wins): the end of the last part no longer lights «terminei» or clears the line under it on its
own. Both follow the room's answer to that part's report, as hers follows `heardComplete`
(`Drafting.tsx:2340`, `:2343`): a room still naming a part unheard keeps «terminei» dark and
the line drawn, and an answer naming none lights it, a replay still playing included. The
refusal sets that count to not heard until the room answers again. Wherever this record says
the last part's end clears the line and lights «terminei», read that the room's answer does.
The status line that a refusal writes is not changed here.

Amended by ENG-2109 (2026-10-30, the same rule): the room's answer is one of two terms, as her
`canCheck` reads `bReady && heardComplete`. Beside it, every part must have been played on this
screen since the telling began — not in the First listen, whose end is where her record is
forgotten (`startTell`, `Drafting.tsx:955`) — within her slack of 750 ms or half the part, or
have its told ground reach its length (`computeBReady`, `:898-910`). The Listening ledger
answers which parts were, counting from the telling's start while its report to the room keeps
every span, and the state carries them as `btPartesOuvidasAqui`. A room's answer counting every part heard
on an earlier day no longer lights «terminei» or clears the line on a fresh screen by itself.
