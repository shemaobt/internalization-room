---
status: accepted
date: 2026-10-29
amends: 0154 (the check waits for every part to reach the room; in part: a part that landed without this tablet learning its name), 0025 (a recording learns its name on a flush)
---

# A part that landed while the app was closed is named from the room's listing, and every name adopted is saved at once

This amends ADR 0154 and ADR 0025 without editing their decisions: it adds "amended by 0163"
to their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October).
Settled on the ticket (ENG-2082).

## Context

A rehearsal part learned the room's name for it from the Outbox alone: the row that landed
in this process, kept in memory, and the manifest drops a row the moment it lands. ADR 0154
wrote the consequence down as accepted: a part that landed without this tablet learning its
name, which a relaunch can leave, still counts as unheard on the check. A name adopted was
written to the Resume point only by the next save, so a relaunch before one restored the part
nameless again, and ENG-1986's visit-to-visit naming held only while the process that saw
the landing lived. Her parts are always the server's clips, keyed by the server
(`app/components/Drafting.tsx` reloadDraft, `:350-355`, at 18fa7c4): a part on her check is
never nameless, so its stretches are cut by part and its listening counts whatever process
sent it.

## Decision

**A kept part with no take id and no Outbox row waiting for it takes the take id the room's
listing holds as current at its number and pass, on the next listing read, and every
adoption writes the Resume point at once.** The resume reads the listing for this when a
kept part is nameless off the Outbox, after landing, and the recording home's lay-in names
such a part over the listing it has already read. The tablet's own file stays the part;
nothing is fetched. A part the Outbox still holds is left alone: its name is its own landing,
as ADR 0025 says, and a take another tablet sent at its number is never borrowed. The Resume
point is written under the station the row already says, never under where the team stands,
so a relaunch straight into a passage, which lands on the conversa, keeps the row on the
rehearsal.

ADR 0154's last rule now reads: a part whose upload has not landed keeps the check closed; a
part that landed without this tablet learning its name is named from the listing and counts
as any other. ADR 0025's name-on-a-flush stands and gains a second source: the listing, for a
part the Outbox no longer holds.

## Consequences

The check after any relaunch counts a landed part heard and cuts its stretches by part. A
name-only listing read that fails lands the team as before, with the part nameless until the
next read; the session read that follows decides a gone session. The reads that serve a swap
or a join keep their own naming, and the orange dot still chooses the plan over the recording
home when every part is nameless, recorded as a finding for a follow-up ticket.
