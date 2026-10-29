---
status: accepted, amended by 0052, 0071, superseded in part by 0093, amended by ENG-1197 (2026-10-19: a frase whose first telling fails on the network is a frase not understood, never re-sent), amended by ENG-1696 (2026-10-20: a frase told again too), superseded in part by 0108, amended by 0087 (2026-10-28, ENG-1777: the Outbox retry is gone; only a tap sends)
date: 2026-10-01
amends: 0046, 0049
---

# The Reach is a region, and the retry is the machine's

Amended by ENG-1197 (2026-10-19): a stretch told back for the first time whose send
fails on the network no longer takes the room out of reach and is not re-sent on the
return. Marcia's rule names a send failure among the frases nothing was understood of
(ENG-1197; her `Drafting.tsx:1221`): nothing is stored, the pause stays, and the screen
says «não entendi — traduzam de novo esse pedaço», so the team tells it again. That
answers the objection to the option rejected below: the team now sees the gesture they
owe. A key still in flight after three answers (ADR 0052) is not a failed send, and still
goes out of reach and out again under its key; the approval, a turn and the verdict keep
this ADR as written. A stretch told again follows the first telling since ENG-1696, below.

Amended by ENG-1696 (2026-10-20): a frase told again, at the correction door, whose send
fails on the network is a frase not understood too, as her app answers both tellings
(`Drafting.tsx:1221`): her line, the frase kept armed on the same stretch, nothing re-sent,
never out of reach, no person. So is the read that follows a telling refused because its
frase no longer counts, when that read fails on the network. The lost-answer recovery that
rested on the re-send is replaced: when the server stored a telling whose answer was lost,
the team's next telling of that frase is refused on the superseded id, the room reads the
frase standing on that exact slice and the telling goes on to it, so it lands at once as
that one frase, as hers does. The copy the Outbox kept of the lost telling leaves the queue
there, since it already is the frase on the server. A key still in flight after three
answers keeps ADR 0052's path here too.

This amends ADRs 0046 and 0049. It edits one sentence of 0049, in its Consequences: the
one that said the offline notice had no path under an open microphone until ENG-1174. That
sentence named this work as pending and would have been false the day it merged, so it now
says the notice waits there like any courtesy line. It also adds "amended by 0050" to the
status line of 0046 and of 0049. Nothing else in either is edited.

## Context

ADR 0046 named the Reach as one of the machine's four regions, but it stayed a field the
notifier wrote: the notifier owned the retry ladder, the network watch and the way back,
and nine doors swallowed a network failure. A rehearsal upload that failed left the room
reachable, and the Outbox drained only on an enqueue or a return, so a part waited about
fourteen minutes after the server was back (hand test of 28-09, item 3.4). Going out of
reach bumped the epoch, which abandoned whatever the team was waiting for, even when the
door that fell was one nobody was waiting on. Henok decided on 30-09 that the retry by time
is the machine's, that every door's network failure is one event, and that coming back
re-sends what was pending under its key; the Definer refined it on 01-10.

## Decision

**The Reach is a region of the machine: reachable or out of reach.** A network failure at
any door, the Outbox's, the Watch's, the inbox's and the coverage stream's included, is one
event, and the room goes out of reach. The device-link doors stay outside.

**Going out of reach cancels no wait.** It never bumps the epoch. Only the door that fell
stops its own flow; a turn in flight while the Watch falls still lands.

**The machine owns the retry.** Out of reach, it arms the retry on the room's ladder, and
the retry or the radio coming back asks for a probe; a probe that fails climbs the ladder,
and so does a fall after a return the room never answered.
Reachable with a part pending, it arms nothing: a part pending waits for the team's tap,
and the machine neither retries nor drains the Outbox (0087, amended 28 October, ENG-1777).

**Coming back drains the Outbox, reads the session at once, and re-sends the pending
request once.** What needs the server waits while a blocking halt stands: the pending
request stays pending until it is actually sent, and goes when the halt lifts with the room
reachable. The pending request is the one a Step was waiting on when its door fell: a
turn under its turn id, a stretch told back or told again under its `Idempotency-Key`, the
verdict, the approval, or the Station's own way in (the wheel, the opening, the start
over). It lives in memory. The key is minted when the Step first sends the request and
kept until the room settles it: an answer, a refusal with its code, or the session gone.
A 409 `IDEMPOTENCY_KEY_IN_FLIGHT`, a 429, a 5xx, a network failure or an abandoned wait
keeps the key for the next send; a 409 `IDEMPOTENCY_KEY_IN_FLIGHT` waits the ladder and
sends again under the same key. Any other 409, with another code or with none, is a
refusal and lets the key go, like every refusal: the server keeps no answer under a key
for a 409 (ENG-1170), so the next send finds nothing kept under either key, and the
team's next confirmation is a new request. A turn re-sent on the return goes once, without its own wait for resends.

**An open microphone outranks the fall.** The circle reads a blocking halt, then an open
microphone, then out of reach. Out of reach, a tap closes the microphone and keeps the
take; a turn closed out of reach waits as the pending request. The retry is offered only
from silence.

**The offline notice is said once per outage, and an outage ends when the room answers.**
A return the room never answered (the health check passes and the next request fails
again) is the same outage, and the notice is not said again. The notice is a courtesy
line: it waits under an open microphone or a gesture on its way, and leaves the queue
unsaid when the room comes back.

**A take refused with no code gets one more try.** The Outbox keeps the code each refusal
named. A take stranded on a bare `HTTP_<status>` is tried again on every drain the machine
asks for; one refused with a known code stays stranded. A manifest written before the
code was kept still loads, and its stranded rows stay stranded.

## Considered Options

**The return re-sends nothing, and the team's tap asks again**, as before. Rejected by
Henok: a lost answer then costs the team a gesture they cannot know they owe.

**The Outbox keeps a clock of its own.** Rejected: two clocks would decide two retries, and
invariant 12 could not be read off the machine.

**The outage ends at the probe.** Rejected: a server whose health check passes while its
doors fail made the room fall, come back and say the notice again every few seconds.

## Consequences

ADR 0049's sentence "the offline notice has no path under an open microphone until
ENG-1174" no longer holds: the notice now waits under an open microphone and is said, or
dropped, when it is free. ADR 0049's "the circle reads offline whenever the Reach is down"
is narrowed: not over an open microphone.

Every turn, stretch, verdict and approval that falls on the network is re-sent once per
return. A server that answers its health check and fails the request again sees one
attempt per return, on the room's ladder.

The keys are honoured only by a server that keeps answers under them (shema-api #599).
A server without it, or a key past its 24 h, receives the re-sent stretch as new, and the
room falls back on ADR 0047's path for a stretch that no longer counts.
