---
status: accepted
date: 2026-10-09
amends: 0018
---

# The reach asks the room first, and the radio only names a fall

ADR 0018 took `connectivity_plus` so that "the room must be able to say it cannot reach the
server before the Team taps". This amends that reason only: the radio it reads names a fall,
and never decides one. It adds "amended by 0074" to 0018's status line. Nothing else in 0018
is edited.

## Context

The check that says whether the room is in reach read the radio first and asked the room
only if the radio saw a network. On iOS, `connectivity_plus` stops its path monitor when the
last listener of its change stream leaves, and a check made right after reads no network at
all. Coming back from a fall cancels exactly that listener, so the way in that asked the room
again a millisecond later was told there was no network, fell again without a request, and
never asked for its session: on the device, only `/health` and no `POST /sessions` until a
relaunch (ENG-1527, hand test of 09-10, items 7.12 and 7.3).

## Decision

**A room that answers `/health` is in reach, whatever the radio reads.** The check asks the
room first. The radio is read only after the room did not answer, to name the fall: no
network, or a network with a silent room.

## Considered Options

**Keep the change stream listened to for as long as the room lives**, so the monitor never
stops. Rejected: it leans on how one plugin version manages its monitor, and it would make
every network change while the room is in reach a retry.

## Consequences

With the radio off, the check now makes one request before naming the fall; it usually fails
as soon as it is sent, and waits at most the ping's own timeout. A radio that lies can no
longer keep a room that answers out of reach; it can only choose between the two faces of a
fall, so a silent room checked right after a return may be named as no network.
