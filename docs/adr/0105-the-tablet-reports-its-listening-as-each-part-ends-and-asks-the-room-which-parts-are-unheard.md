---
status: accepted
date: 2026-10-20
---

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
  and when the app goes to the background. «terminei» still carries it on the check. A
  report never closes a span still open, and a failed one changes nothing the team sees
  or hears.
- **The room is the only counter.** Which parts are unheard is always its answer; the tablet
  adds only a part the room has not named yet, which nobody can have heard.
- **Entering the Back-translation no longer forgets the ledger**; leaving the passage does.
  Listening on the Rehearsal therefore counts.
- **After a part is recorded again**, the next entry into the Back-translation asks the
  room. Some parts still heard: the screen says «ainda falta ouvir um trecho da gravação»,
  her P2 is said, and only the unheard parts play, in row order, each from its beginning,
  stopping after the last with «terminei» lit. Every part unheard: her opening line P0 and
  the whole recording. No answer, or a room too old to name the parts: today's path.
- **A refusal for unheard parts** plays every part it names in row order, crossing from one
  to the next. After the last, the crossing into the following part stays offered, as it
  did after a single landing.
- A blocking halt during the replay withholds the sound as it does on any entry; the lifted
  halt plays the part and the replay still stops where it would have.
- The reports, the mark and the replay's list live in the notifier beside the Retro screen's
  other fields, under ADR 0046's written exception, until that screen moves to the machine.
- The mark that a part was recorded again lives in memory only: a relaunch between the
  recording and the entry takes today's path, without P2.

## Considered Options

**Count on the tablet.** Rejected: two homes for the gate's rule, and the dossier, the
release and the tablet could disagree.

**Persist the ledger on the tablet.** Rejected: the room's merge per take keeps what was
reported, and a second tablet on the session would not see a ledger kept on the first.

## Consequences

- One small request per part end. It is never awaited.
- Against a room without ADR 0074 the reports replace each other, so the app must reach
  production after it.
