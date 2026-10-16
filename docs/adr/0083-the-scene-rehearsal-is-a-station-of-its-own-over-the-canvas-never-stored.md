---
status: accepted
date: 2026-10-14
amends: 0053
---

# The scene rehearsal is a Station of its own over the Canvas, never stored

## Context

The red microphone opens the **Scene rehearsal** screen from the **Conversation** at rest,
and «Voltar para a passagem atual» brings the team back to the **Conversation** as it was. In
her app the screen sits over the canvas. The room needed to decide whether that screen is a
**Step** of the Canvas or a **Station** of its own, and whether a relaunch can land on it.

## Decision

The scene rehearsal is a **Station** of its own, the stage `cena`, added to ADR 0053's list
of Stations. Only the Canvas answers the scene rehearsal opened with it; every other Station
ignores that arrival, and the Scene rehearsal answers the way back with the Canvas. Like
every Station change, both arrivals move the **Generation** (ADR 0058), so an answer that
was on its way when the team crossed is dropped. Its **Steps** (record, translate, places
unknown, sent) are substate held beside the Station, as the Back-translation's are.

The scene rehearsal is never stored as the session's **Resume point**: a stored `cena` reads
as the Canvas, and a relaunch lands on the **Conversation**. The rehearsal itself lives on
the server (shema-api ADR 0059), and the red microphone reopens this session's unsent one
from there.

Every failure at a scene door goes through the Failure policy at its own door. A gone
session, a code that stops the room and a network failure follow the house policy, as at
every other door, and a timeout raises a halt as anywhere else. Any other refusal changes
nothing and is never counted toward the refusals that call a person. A refusal that says
the rehearsal moved on without this tablet reads the list again: one already sent is shown
sent, and a restart that landed while its answer was lost opens on the attempt the room
holds. The doors that name a rehearsal read a 404 as a refusal, because the server answers
a gone session and an unknown rehearsal with the same code, and that refusal reads the list
again too. The list asks for the session, so a gone session surfaces there at once, and an
unknown rehearsal just finds no match; a missing rehearsal never ends a live session.

A door's answer moves the screen only while it still shows what it showed when the door
was asked, with no microphone open; an answer that arrives after the team moved on is
dropped. Places are measured against the take this tablet holds.

## Considered Options

A Step of the Canvas. Rejected: the screen silences the room, owns its own microphone and
its own way back, which is what a Station is under ADR 0053, and the Checagem externa is
already the precedent for a Station that sits over another.

Storing `cena` as the resume point. Rejected: the server already keeps the rehearsal, a
reopened screen rebuilds itself from it on any tablet, and a stored screen would land a
relaunched team on a microphone instead of on their **Conversation**.
