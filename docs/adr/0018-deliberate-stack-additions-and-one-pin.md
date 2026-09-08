# Two packages outside the stack list, and one version pinned

## Context

The stack this app inherited was a closed list, and three departures from it would otherwise
read as drift a later reader would tidy away. Two are packages the list never named; the
third is a version held back.

## Decision

`connectivity_plus` is a dependency, because the room must be able to say it cannot reach
the server before the **Team** taps, not only after a request has already failed.
`wakelock_plus` is a dependency, because nothing else can hold the screen and the team
leaves the tablet untouched for minutes at a time. And `path_provider_foundation` is pinned
to 2.5.1: 2.6.0 pulls a native asset whose framework ships ad-hoc signed, which iOS refuses
to install.

## Consequences

The pin is load-bearing rather than cosmetic — lifting it produces a build that installs
nowhere, and the failure arrives at install time rather than at build time — so it stays
until the upstream signing is fixed. It is held to the same version another Shemá app
uses, so the two move together. The two additions are the reason a reader finding them
outside the stack list should leave them there.
