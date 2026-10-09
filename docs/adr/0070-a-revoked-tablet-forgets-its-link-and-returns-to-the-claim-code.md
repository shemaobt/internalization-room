---
status: accepted
date: 2026-10-09
---

# A revoked tablet forgets its link and returns to the claim code

The app ships no shared key: the device credential is the only thing a tablet sends, so a
credential the Desk revoked leaves the tablet with no way into the room. Revocation is the
one refusal that forgets the link: whichever door is answered `DEVICE_REVOKED`, the tablet
drops its credential, its link and its Current session, and shows a fresh claim code; the
room it was in is built afresh, so the next link opens it as a first launch does. Any other
401 or 403 still halts the room and keeps the link, because it does not say the link ended.

The revocation is heard where every answer arrives, not door by door: some doors let a
refusal pass by their own rule, and some still decide their failures outside the failure
policy, so a per-door route would have left a revoked tablet working until the one door that
noticed.

The takes queued from an earlier launch leave only after the credential is presented: sent
before, they were refused and given up.

## Considered Options

- Halt the room and keep the link, as every other refusal does: rejected. A revoked tablet
  stayed on the person sign until someone relaunched it, and a relaunch still believed in
  the link, so it never showed the code a facilitator needed.
