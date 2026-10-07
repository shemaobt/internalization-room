# The room picks its language once per run

Amended by ENG-1268 (what the language decides): no fixed line is bundled any more, so the
choice no longer picks a bundle. It is the language the tablet asks the room for each fixed
and process line in, by family and position; the choice itself, its fallback and its
once-per-run rule stand.

## Context

Everything the room says is generated or bundled per language, and the tablet has to pick
one. Nothing on a team screen is written, so this is not localisation in the usual sense:
what the choice decides is which bundle the fixed lines come from, and which language the
app asks the server for.

## Considered Options

Re-reading the device locale as the session goes. Rejected: a team hearing the language
change under them mid-**Passage** is worse than either language would have been.

## Decision

Once per run, the tablet walks the device's ordered language preferences and takes the
first one the room speaks, falling back to English when it speaks none of them. The choice
is never re-read.

## Consequences

A tablet set to a language the room cannot speak still works, in English. The one way the
choice moves mid-run is the developer skip bar in a debug build, which exists so a developer
can hear all three without reinstalling; no build a team uses can reach it.
