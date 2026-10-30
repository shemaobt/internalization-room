---
status: accepted, amended by 0131 (2026-10-22: a take of this visit reads «enviando…», a refused take of this visit offers no tap, only a tap sends a spent take, and a part beyond the last scene is no longer retried by itself: its take is told and sent by the tap on its own row after the scenes, which records nothing), amended by 0166 (a row whose send ended on a wait reads failed with its tap; an earlier visit's take sent by the tap reads «✓ salvo»)
date: 2026-10-20
amends: 0087, 0047, 0049, 0084
---

# An unsent take is told on its Scene row and sent by the team's tap, and no voice tells a stranded recording

This amends ADRs 0087, 0047, 0049 and 0084 without editing their decisions; it adds
"amended by 0103" to their status lines. The Definer settled it on 19 October (ENG-1420).

## Context

A take the Outbox could not deliver was told by a spoken courtesy line, «gravação presa»,
once per passage, after eight unanswered tries, a refusal for good, a lost file, a set-aside
manifest, a failed write of the Resume point or a keep the Outbox could not take. The
Rehearsal showed nothing but a word in a bead's label, and the team had no way to send a
take now: only the Outbox's own clock retried it. Marcia's app shows a take still on the
computer, with its length and «enviar agora», and a failed send with «falhou — toque para
tentar de novo»; it never speaks a failure. Her rule and ENG-1356's take the spoken
failure lines out of the room.

## Decision

- **An Unsent take shows on its Scene row.** A take of this session still in the Outbox,
  waiting, failed or refused for good, or kept by this visit and not put in the Outbox. A
  row speaks only for the newest pass of its part: a row behind a newer pass the room holds
  is not shown and never sent again, and its file stays on the tablet. A row whose file is
  not on the tablet, whatever the Outbox wrote about it, is not an unsent take; its row shows
  what the room holds. The count of unsent takes the approved draft waits on is these rows'
  own.
- **A visit is this app run of the session**, whatever the team leaves and comes back to
  in it; only a relaunch makes a waiting take one of an earlier visit. A take whose newest
  recording this visit did not put in the Outbox is from an earlier visit: the home shows her notice «Uma gravação
  ainda está neste computador e não foi enviada.» and, on its row, «Cena N · m:ss — enviar
  agora», the length measured on the tablet from the audio it holds. A take of this visit
  whose send failed shows «falhou — toque para tentar de novo». A take of this visit still
  on its first try shows nothing new.
- **Either tap sends the part now**: every Outbox row of the part's newest pass is given its
  tries back and the Outbox flushes, in the order recorded (ADR 0025); a take refused for
  good is sent once more. A keep that never reached the Outbox is put in
  it again. The tap does nothing while a microphone records on the home.
- **The automatic retry is gone** (0087, amended 28 October, ENG-1777): the team's tap is the only way a take is
  sent.
- **No voice tells a stranded recording.** The line, its kind and its clip in both languages
  are gone. A take refused for good is told by its row, not the voice (ADR 0087). A scene
  take refused for good keeps the scene screen's not-kept words at the moment; nothing tells
  it at launch until ENG-1424.
- **Her words on every recording home control**: the circle «Gravar», «Gravar de novo» or
  «Parar» by the act its tap performs; the wood play «Ouvir» or «Parar»; the green check
  «Enviar a gravação»; the advance disc «Traduzir a gravação», or «ouvir e conferir o
  Ensaio Final» after a join. Our own labels for them go.

## Considered Options

**Keep the line and add the row.** Rejected: the ticket and ENG-1356 forbid spoken failure
lines.

**One notice block with every button in it, as her app.** Rejected: the Definer put
«enviar agora» on its row.

**Drop the automatic retry.** Rejected until Marcia rules; done since (0087, amended 28 October, ENG-1777).

**A visit is each arrival at the Rehearsal.** Rejected: a failure of this run would turn
into an earlier visit's take on the way back from a finding, with no event the team caused.

## Consequences

A Resume point write that fails, a manifest set aside and a part kept with no session are
no longer spoken. The first two are logged and silent; the third shows as a failed take on
its row for the rest of this visit; its tap fails the same way; when the passage reopens as
another session the take is not offered, and its file stays on the tablet, never deleted, like
the Outbox rows of a session the room let go of (ADR 0087). A whole recording, which no
Scene row holds, is never shown, whatever happens to its upload. A part beyond the last
scene has no row and shows nothing; the Outbox still retries it. Tablets holding takes in
an Outbox an older app wrote show them through the notice after the update, and nothing
is deleted.

The visit's own rows, the keeps that never reached the Outbox and the send-now gesture stay
in the notifier, like the scene's own retry, until the Outbox's lifecycle moves into the
machine; that is a debt against the room's core (AGENTS.md), taken knowingly.
