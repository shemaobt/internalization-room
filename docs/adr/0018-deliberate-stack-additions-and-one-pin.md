# Two packages outside the stack list, and one version pinned

## Context

The inherited guidelines named a closed stack. Three departures from it are deliberate and
would otherwise read as drift a later reader would tidy away.

## Decision

Connectivity detection is a dependency, because the room must be able to say it has no
connection before the **Team** taps, not only after a request has already failed. Keeping
the screen awake is a dependency, because nothing else can hold it and the team leaves the
tablet untouched for minutes at a time. And the iOS path provider is pinned one version
back: the newer one ships a native framework signed ad hoc, which iOS refuses to install.

## Consequences

The pin is load-bearing rather than cosmetic — lifting it produces a build that installs
nowhere — so it stays until the upstream signing is fixed. The two additions raise the
toolchain floor, which is what the toolchain note in `AGENTS.md` records.
