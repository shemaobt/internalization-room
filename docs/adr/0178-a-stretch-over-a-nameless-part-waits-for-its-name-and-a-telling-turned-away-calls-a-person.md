---
status: accepted
date: 2026-11-02
amends: 0068, 0093, 0146, 0160
---

# A stretch over a nameless part waits for its name, and a telling turned away calls a person

This amends ADRs 0068, 0093, 0146 and 0160 without editing their decisions, and adds
"amended by 0178" to their status lines. Decided with Jonatas on 29 October and 2 November
(ENG-2015). It departs from Marcia's app on purpose: hers reads «não entendi» for any failed
send, a 401 included, and has no nameless part because she sends by clip key.

## Decision

- **«não entendi» means the room heard the stretch and found no words.** Every other reason
  is told for what it is.
- **A stretch told over a part the room has not named yet is a Held stretch**, no longer a
  telling not understood (amends 0146 and 0068). It stays on the tablet with «enviando…» on
  the Back-translation's status line, the words ENG-1774 gave a take in flight. The tablet
  looks for the part's name at once, and the stretch goes with no tap once the name is
  adopted, as a tapped stretch would. The circle stays live: telling it again lets the held
  recording go, and only the newest one is sent. «terminei» and «regravar a frase N» rest
  while a stretch is held. Leaving the Back-translation, translating a frase again or any other
  way the pending translation is let go drops the held stretch, and it is never sent after.
  It lives in memory only; a relaunch loses it.
- **A telling the room turns away for the tablet (UNAUTHORIZED, FORBIDDEN, DEVICE_REVOKED)
  calls a person**, at the telling door and for a stretch told again (amends 0093: the six
  cases gain this one). Its recording is let go. Where the sign rises is ADR 0160's rule: not on
  the Back-translation, which shows neither «não entendi» nor the sign, but once the team
  reaches the Conversation. Every other refusal at the telling door is still a telling not
  understood.
- **That halt outlives a line the room serves, heard to its end on the Back-translation**
  (amends 0160, item 4). The verdict the team hears before «pronto» says nothing about the
  tablet's refusal, so it does not let the call go.
- **A late failure never deletes a Borrowed translation.** The tablet keeps the file whenever
  it lets a pending translation go and that translation is borrowed.

## Consequences

- On the base this was built on, a late answer of a stretch the busy watchdog gave up on is
  already dropped, because the give-up moves the generation; the borrowed guard is the
  ticket's invariant, kept for any path that reaches it.
- A part never named on this visit keeps «enviando…» until the team tells the stretch again,
  leaves or starts over. Nothing calls a person for it.
- DEVICE_REVOKED still reaches the device link, which ends the life and returns to the claim
  code; this decides only the instant before.
