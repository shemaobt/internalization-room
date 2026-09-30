---
status: accepted
date: 2026-09-30
amends: 0046
---

# The Watch beats for the whole session

This amends ADR 0046 without editing it.

## Context

ADR 0046 armed the Watch whenever the Halt is not none. Read as "only while the Halt is
not none", nothing read a halt the server wrote on its own (a Desk that stops a session the
tablet is idling in): the room found it only on its next turn. The Halt region also came
to the machine with a lift that a Session read can trigger, and a halt the tablet raises is
now watched from the moment it stands, before its call for a person has reached the server.

## Decision

**The Watch reads the session every beat for as long as a session is open, with or without
a halt.** A halt only the server wrote stops the room within one beat. Invariant 3 stays one
way: a halt never stands without the Watch; the Watch may beat with no halt at all. Henok,
30-09. The cost is one read per beat per tablet (thirty seconds today).

**A read that finds nothing standing does not lift a halt the server has not heard of
yet.** A halt the tablet raised knows whether the server has it: its own call for a person
landed, or a Session read carried it. A read that went out before the call landed says
nothing about that halt either, even if it lands after. Until the server has it, the long
press stays the local way out (ADR 0009).

**A Session read older than one already applied never applies its halt or its
stretches.** Beats do not wait for each other and every door reads the session, so reads
can land out of order; the newest one sent is the one that counts. A read also never takes
back stretches the row gained or changed after it went out. What only grows, the coverage
and the end of the passage, applies from any read, however late.

**A lift never re-sends the request that caused the halt under the same key.** A halt over
an opening that could not be fetched is lifted by asking the opening again under a turn id
of its own; the server would otherwise answer the remembered turn with the same missing
clip, and every release would halt again.

## Considered Options

**The Watch only while a halt or a warning stands.** Rejected by Henok: a halt the Desk
writes on an idle session would wait for a gesture the team has no reason to make.

**Arm the Watch only once the call for a person lands**, as before. Rejected: a halt whose
call keeps failing stood unwatched, against invariant 3.

## Consequences

The glossary's Watch now ends with the session, not with the halt.

The beat has one period, with or without a halt. Only the test harness can switch off the
beat with no halt: a beat that re-arms itself outlives every widget test that ends with a
session open.

After any halt over an opening (the invitation's, the panorama's or the conversation's),
the next ask for that opening goes under a fresh turn id, whether the lift asks it or the
next tap does. When the halt was not the clip's failure the server may write the opening
twice; a duplicate opening is cheap, and an opening that halts again on every release is
not.
