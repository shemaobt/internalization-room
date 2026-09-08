# The room picks its language once per run

## Context

Everything the room says is generated or bundled per language, and the tablet has to pick
one. Nothing on a team screen is written, so this is not localisation in the usual sense:
what the choice decides is which bundle the fixed lines come from, and which language the
app asks the server for.

## Considered Options

Re-reading the device locale as the session goes. Rejected: a team hearing the language
change under them mid-**Passage** is worse than either language would have been.

## Decision

The tablet reads the device's locale once per run, narrows it to a language the room
speaks, and falls back to English for anything else. The choice is never re-read.

## Consequences

A tablet set to a language the room cannot speak still works, in English. The one way the
choice moves mid-run is the developer skip bar in a debug build, which exists so a developer
can hear all three without reinstalling; no build a team uses can reach it.
