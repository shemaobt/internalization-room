---
status: accepted
date: 2026-10-16
amends: 0053
---

# «terminei» sends the scene rehearsal as a turn from its screen, retried in place

## Context

«terminei» sends a **Scene rehearsal** to the voice by reference (shema-api ADR 0063): a turn
id the tablet mints, and the attempt its frases follow. The server can refuse it with three
409s that do not mean failure: another tablet's send of the same scene rehearsal is still in
the air (`SCENE_REHEARSAL_SENDING`), it was already sent (`SCENE_REHEARSAL_SENT`), or the
attempt it closes moved on (`RESTART_OUT_OF_ORDER`). The Definer asked for `SENDING` and
`RESTART_OUT_OF_ORDER` to be retried and `SENT` to count as sent. On the tablet the Outbox
carries recordings, and a send carries none. Her app keeps the screen open while the send is
in the air and closes it on the answer.

## Decision

«terminei» is a turn on the house path, sent while the screen stays open: the screen waits
on it, «terminei» itself is the waiting control, and the way back does nothing until the turn
ends, because a Station change drops a turn in flight. On the answer the screen closes and
the reply plays on the Canvas as any reply. A lost answer gets the turn's one look. No scene
send starts while a person is called.

The 409s are retried in place, under the same turn id, inside the send: `SENDING` along the
house ladder up to three sends; `RESTART_OUT_OF_ORDER` once, after reading the list, closing
the attempt the room holds when the scene rehearsal is still unsent. That in-place retry is
the one place the send reads a refusal before the Failure policy does, and the guard that
keeps every other refusal inside the policy names this ADR for it. Any refusal that remains,
`SENT` included, goes to the Failure policy at the scene door under a rule of its own: the
room rests without calling a person, unless the code stops the room, and the list is read
again, so a scene rehearsal that went through another way reads «enviado». A list that
cannot be read while resending is decided at its own door, and the send ends on the refusal
it answered, never on the turn's one look, because the room did refuse the send.

A turn id with no reply is kept with the session's state until a reply plays or the screen
closes, across switching rows, and the next «terminei» on that scene rehearsal goes under it
again: the room answers a resend from the stored answer or joins the send in flight. A
relaunch mints a new one, as her app does.

A loss whose one look comes back empty halts and calls a person, as for any turn, and under
that halt the list is read once. When the row reads «enviado» and the turn id is still held,
the send goes once more under it: the one send allowed under a halt, because it reuses the
held id and mints nothing. The reply is kept and plays when the person lifts the halt, as any
late answer does. That send says no acknowledgement, since no one in the room made it, and
while the halt stands no row opens. A send that goes once more and is itself lost with an
empty look gives the held id up, so it ends on «enviado» with nothing played, as does a
row read «enviado» with no held id, after a relaunch.

## Considered Options

The Outbox. Rejected: it holds files to upload, and a send by reference is no file. Teaching
it a second kind of row for one door is a larger change than three bounded retries.

Closing the screen first and waiting on the Canvas. Rejected by the Definer: her app shows
the wait on the screen, and her failure lines (ENG-1424) belong there.

Holding the halt back after an empty look until the list is read. Rejected by the Definer:
the scene send is a team turn, and an empty look calls a person as for any turn.

## Consequences

The tablet's own restart cannot be in the air while «terminei» is live, so ADR 0063's
branch that waits for it has no path here; a moved attempt is always read from the room.
`RESTART_OUT_OF_ORDER` that resends reads the list twice: once to resend, once because the
answer it ends on is a refusal.
