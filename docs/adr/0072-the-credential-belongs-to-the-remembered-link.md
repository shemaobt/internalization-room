---
status: accepted
date: 2026-10-09
---

# The credential belongs to the remembered link

## Context

ADR 0017 keeps the device credential in the Keychain, which outlives an uninstall, while the
rest of the **Device link** lives in a file that does not. After a reinstall the tablet found
no link but still held the credential of the device it used to be. It presented that
credential, never collected its own, and the server served it as the older device, so
unlinking the new device on the Desk did not revoke it.

## Considered Options

Forcing every tablet whose vault does not say which device its credential is for back to a
fresh **Claim code**. Rejected because every tablet linked before this change is in that
state and is working.

## Decision

The vault records the device id each credential was collected for, and a credential counts
only for the device the link file names. With no device in the file, or another one, the
vault is forgotten and the link flow collects a fresh credential once the code is spent. A
credential with no recorded device is taken as the file's device and recorded so. This
replaces the line in ADR 0017 saying the credential survives a reinstall: it survives in the
Keychain but is no longer presented.

## Consequences

A tablet that a build without this check already relinked while it presented an older
device's credential is not healed by this change: its credential has no recorded device, so
it is adopted for the device the file names. Only unlinking the older device on the Desk
corrects it.
