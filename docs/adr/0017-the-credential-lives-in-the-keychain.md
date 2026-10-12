---
status: accepted, amended by 0072
---

# The device credential lives in the Keychain

## Context

Once a **Facilitator** spends a **Claim code**, the server hands the tablet a credential of
its own, exactly once, and afterwards keeps only its hash. It had been kept in the same file
as the rest of the **Device link**, where a reinstall lost it and a backup could carry it
onto another tablet.

## Considered Options

The secure store's default accessibility. Rejected because a poll that starts at boot must
still find the credential before anyone has unlocked the tablet. Also rejected: reading an
unavailable vault as an empty one, which would have made the app ask for a fresh credential,
be told the first one is already out, and erase the whole link.

## Decision

The credential lives in the iOS Keychain, reachable after the first unlock on this device
and never leaving it. It survives a reinstall; a backup restored onto a different tablet
cannot hand that tablet a credential the server issued to another row. The vault
distinguishes absent from unavailable, so a read that fails before first unlock is never
read as "never collected".

## Consequences

Drawing the credential is a once-in-a-lifetime act per tablet, so the server's answers are
read as permanent or temporary rather than as retryable or not: told the credential is
already out, or that the device is unknown, the tablet forgets both the device and the team
and asks for a fresh code; told the row is not claimed yet, or met with a network failure,
it keeps everything and tries again. A response lost on the way back is indistinguishable
from a credential already spent, and is treated as spent. A file written before the vault
existed is migrated once, and forgetting has to erase both places.
