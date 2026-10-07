---
status: accepted
date: 2026-10-06
amends: 0053
---

# The call for a person runs in the runner, and the Station hears what is its own

This amends ADR 0053 without editing it; it adds "amended by 0060" to its status line. The
Definer and the Orchestrator settled it on 6 October while the call for a person left the
notifier (ENG-1454), in the shape of ADR 0059.

## Context

The call for a person goes out when the room halts, which is mostly when the network is bad,
so it is insisted on until the server says it has it. It has two forms: with the room's
session, and, for a halt with no session to name, by the tablet's own device id from the
device link. A long press on the person sign tells the server the facilitator arrived.

The Station keeps what the machine does not: whether the call landed, the order of its
reads (a read sent before the call landed must not lift the halt), and the passage in
course. A call may be answered after the room moved to another session; today that answer
acts on the earlier session, not on the room's.

## Decision

- **The call and the person-arrived mark run in the runner through the Room port**, and
  every failed result goes through the failure policy at the facilitator's door
  (`Door.person`). The call is decided under `asksAgain`: a refusal asks again on the
  ladder, nobody to reach passes, a closed passage is marked closed. The mark's network
  failure falls at the same door; its session gone, for the room's session, is decided with
  the Station's default context.
- **The runner keeps the one call in the air** and asks the Station two more questions:
  whether a call is wanted now (the room needs a person, the call has not landed, and no
  closed passage is being marked), before it sends one and again when an answered call
  lands; and the passage in course, when it sends one.
- **The Station hears what is its own.** A landed call sets its flag and, with a session,
  stamps the read order before the machine hears `TheCallLanded`; a landed call without a
  session sets the flag only. An answer for a session that is no longer the room's is heard
  with that session, the passage kept at send and the result, and the Station does what it
  did: a closed passage is written down for that session, a session gone lets it go. Only
  its network failure is decided in the runner, which then does not ask again. Otherwise
  the call stays in the air until the hearing ends, and the runner then calls again if a
  call is still wanted. A mark's session gone for an earlier session is heard the same way.
- **The call without a session reads the device id in the Room port's adapter.** The port
  answers the room's result, the tablet unknown or the room gone (nothing happens), or the
  device link unread (the host's ladder asks again). The policy never sees the last three.
- **Every answer of the family comes back where it was asked**, through
  `EffectHost.answerWhereAsked`, as it did when the notifier dispatched it in the zone of
  the dispatch that ran the effect.
- **The ladder, the stop and the closed-passage mark stay on the host** until ENG-1456. The
  ladder's timer is cancelled on every generation move, and runner timers survive one by
  design. The ladder's retry calls the runner's call.

## Considered Options

**The earlier session's answer through the policy.** Rejected: a closed passage or a
session gone would then close or end the room's current session instead of the earlier one.

**The device id as an argument the Station reads.** Rejected: the device link read is a system
boundary, and the runner would need a third answer from the host for it.

## Consequences

- `EffectHost` keeps no method that asks for a person or marks the arrival. It answers
  `callIsWanted` and `passageInCourse`, and hears through `hearTheCallLanded`,
  `hearTheCallLandedWithoutASession`, `hearAnEarlierSessionsCall` and
  `hearAnEarlierSessionGone`.
- One behaviour moves: when the device link cannot be read, the ladder's retry used to ask again without a
  session even if the room had one by then; it now asks with the session if there is one.
  No test sees the difference.
