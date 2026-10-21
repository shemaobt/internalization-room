---
status: accepted
date: 2026-10-21
amends: 0019, 0046, 0053, 0093, 0097
---

# A tap clears the person sign, and nothing the Desk does moves the tablet

A team under a blocking Halt waited on the Desk: the sign lifted only when a Session read
stopped saying `needs_person`, when a long press found the call had not landed, or when a
long press told the server a person arrived. A facilitator who never came, or a call that
never landed, held the team indefinitely. Marcia's handoff is a wordless wash the team
clears with a tap. The Definer settled the rules on ENG-1354 (Definition of 19 October,
amended 21 October, and the decision comment of 21 October); shema-api ADR 0076 makes the
Desk's visit a record on the server side.

## Decision

- **The team's tap is the only way out of the sign.** It returns the room to rest, with
  the Warning beneath standing again when there was one. Nothing is replayed and nothing
  is resent. The tap resumes a look the sign held. The only hand-offs it takes are the
  ones a halt held back: entering a passage whose session never opened, and reading the
  Wheel on a Choice that has not read it.
- **No other lift.** A Session read under the sign only updates the Warning beneath. The
  long press over the sign is gone, and with it the «person arrived» call. A call that
  lands marks nothing on the halt. The long press over the offline face stays, for
  ENG-1356.
- **The sign is drawn as a wash** over the whole screen: the Shema mark and two outlined
  figures, no words, no sound. The circle fades and leaves the semantics tree, so the
  wash alone carries «Um momento para uma pessoa» to VoiceOver. The passage button fades
  too, on every screen.
- **A failed look is a failure.** A look that fails on the network or on a refused device
  reaches the failure policy through its own door: over an Opening it rests at the quiet
  invite, over a spoken turn it shows the sign, and while the room is still answering it
  looks again. A 404 is still a turn the room holds nothing of.
- **The one-call-in-the-air flag is released by any end of the call**, thrown or not.

## Amends

- 0046, invariant 11: the gesture under the sign is the tap, and it always clears it.
- 0053: «only the team's tap clears it» now holds; the Warning stays.
- 0093: «a lift sends nothing» is the tap's rule; a Session read neither raises nor clears
  the sign.
- 0097: a held look resumes on the tap.
- 0019: the Back-translation's checked screen no longer keeps its way out under a halt. That
  exception served a sign nobody on the tablet could clear; the wash takes every tap anyway.

## Consequences

- The Desk's arrival line (`personArrivedAt`) stops receiving new values: no tablet tells
  the server a person came.
- A tap no longer brings the reach back. A sign raised while the room was out of reach
  leaves the offline face after the tap, and a tap on that face retries.
- The build guard's tap reads the Wheel. On a real broken build the tablet never links, so
  it shows the claim code and never the room; the guard's sign is reached only in tests.
