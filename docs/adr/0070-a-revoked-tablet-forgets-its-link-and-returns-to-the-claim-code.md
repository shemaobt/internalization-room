---
status: accepted
date: 2026-10-09
---

# A revoked tablet forgets its link and returns to the claim code

## Context

The app ships no shared key: the device credential is the only thing a tablet sends, and
the server lets nothing else through a team door. Unlinking a tablet from the Desk revokes
its credential, so that tablet's next request is answered 403 `DEVICE_REVOKED`, and every
request after it as well. Until now that answer halted the room like any other 401 or 403
and kept the link, so a relaunch walked back into the same halted room.

## Decision

Revocation is the one refusal that forgets the link. Whichever door is answered
`DEVICE_REVOKED`, the tablet drops its credential, its link and its Current session, and
leaves the room at once for the claim screen, which waits for a fresh code and shows it
when it arrives; while the code cannot be minted, the screen keeps waiting and asking.
The room it was in is built afresh, so the next link opens it the way a first launch
does. Any other 401 or 403 still halts the room and keeps the link: it does not say the
link ended.

The revocation is heard where every answer arrives, not door by door: some doors let a
refusal pass by their own rule, and some still decide their failures outside the failure
policy, so a per-door route would leave a revoked tablet working until the one door that
noticed.

A take refused because the tablet was turned away, revoked or unauthorized, is not given
up: the flush stops and the take waits for the next link. The takes queued from an
earlier launch leave only after the credential is presented.

## Considered Options

- Halt the room and keep the link, as every other refusal does: rejected. A revoked tablet
  stayed on the person sign until someone relaunched it, and a relaunch still believed in
  the link, so it never showed the code a facilitator needed.
- Keep the halted room up until the fresh code arrives: rejected. Behind the halt the room
  went on sending requests that nothing opens any more, and each take it sent was lost.

## Consequences

- A tablet that never collected a credential cannot reach the room after this change: it
  is linked again from the Desk.
- Disposing the session notifier must not read its own state: the screen rebuilds it on a
  revocation, and a read during that rebuild builds it again inside its own disposal.
