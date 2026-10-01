---
status: accepted
date: 2026-10-01
amends: 0047, 0050, 0051
---

# A closed passage is asked once, and a key in flight three times

This amends ADRs 0047, 0050 and 0051 without editing their text; it adds "amended by
0052" to their status lines. Henok's decisions of 29 and 30 September, settled by the Definer on
1 October (ENG-1185), close two refusals that the room re-sent without end.

**A passage closed is its own event, with the Session gone's destination.** The server
refuses the call for a person with `PASSAGE_CLOSED` when the passage is already finished
(shema-api ADR 0044). The ask is never sent again, under any key. The room leaves the
passage as it does for a Session gone (ADR 0046 invariant 6, ADR 0051): the Watch ends,
the microphone closes and is discarded, everything of the session goes from the tablet,
any standing halt is cleared with no call and no stop-call, and the Choice opens. Unlike a
Session gone, the server still knows the passage and says it is finished, so the room adds
it to the finished passages before the Choice reads them, and the Wheel shows it closed.
A passage the server says is closed is closed on the tablet wherever the room stands when
the answer lands: if the team has already left it, its session's files and rows still go
and the Wheel still shows it closed, and only the leaving is skipped.

**A session the server no longer accepts, gone or closed, leaves nothing on the tablet,
wherever the room stands.** Whether the room learns it from the call, a door, the Outbox or
a resume, it lets go of that session the same way: its Resume point, wherever in the book
it is, its Outbox rows and their files, and its kept takes, and the session is never
opened again. Only that session's: a newer session in the same passage keeps its place,
and the passage opens afresh from the Wheel. The Outbox rows and the files go whatever
the Resume points answer, even when they cannot be read. Only when it is the session the
room stands in does the room also leave it for the Choice.

This widens ADR 0051, which let an older session's gone discard only its Outbox rows and
copies: the Resume point goes too, and the passage then opens afresh. It squares with the
option 0051 rejected, a reopening that silently starts a fresh session: a reopening that
meets the gone session still opens the Choice, so the team is told; only the next tap,
with nothing of the session left, starts fresh. An answer about an earlier session never
swallows the call the room owes the session it stands in now. Every other refusal
of the call keeps the ladder; a network failure keeps the Reach.

**A key in flight is sent three times.** ADR 0050 sends a request again under the same key
when the server answers `IDEMPOTENCY_KEY_IN_FLIGHT`, and only the busy watchdog bounded it.
After the third such answer under one key, the room takes the answer as a network failure:
the room goes out of reach, and the request waits with its key and is sent again under it
when the room comes back. The server's in-flight window is seconds, and three tries spaced
on the room's ladder cover it.

**A door says whether it names the session.** No door defaults it; a door that names none
answers a 404 as a Refusal, never as a Session gone (ADR 0051).

## Considered Options

**A closed passage dispatched as a Session gone**, after the notifier marks it finished.
It would behave the same. Rejected for the record only: the machine's history and the
invariant tests name the event the server sent, so a reader of either can tell a passage
the server finished from a session it forgot.

**No ceiling on a key in flight, leaving it to the watchdog.** Rejected: the watchdog
raises a halt and calls a person over what is the server still working.
