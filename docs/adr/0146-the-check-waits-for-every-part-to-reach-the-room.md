---
status: accepted
date: 2026-10-28
amends: 0140 (in part: rule 3's last sentence, a part whose upload has not landed)
---

# The check waits for every part to reach the room

This amends ADR 0140 without editing its decision: it adds "amended by 0146" to its status
line. ADR 0140 rule 3 let the check open with a part still in the Outbox and listed that part
as unheard, since the room had no take of it to name. Her app never opens the telling while a
take is held on the computer: `enterBt` returns unless every chain key is among the server
draft's clips (`allRecordedOf`, `app/components/Drafting.tsx:795`, `:1064`, at 18fa7c4), and
her «Traduzir a gravação» stays disabled until then (`:2545`). ENG-1955 brings ours to hers.

## Decision

- **No part waits in the Outbox, or the check does not open.** The Rehearsal weighs a third
  fact, every part sent, beside every scene having its part and every part being here, and
  answers the opening of the Back-translation only when all three hold. The fact is the
  Outbox's own: no scene row with a take still waiting to go up. It is weighed again each time
  the Outbox is counted, so a landing opens the way at once.
- **The home shows it.** The advance disc stays dark while a part waits, and «gravem todas as
  partes primeiro» counts only the parts the room holds, as hers counts the server's clips
  (`recordedCount > 0 && !allRecorded`, `:2494`, `:2546`).
- **ADR 0140 rule 3's last sentence** now reads: a part whose upload has not landed keeps the
  check closed. A part that landed without this tablet learning its name, which a relaunch
  can leave, still counts as unheard there.
- **Unchanged.** A relaunch onto a telling in progress still resumes it whatever the Rehearsal
  weighed (`TheBackTranslationResumed`).

## Consequences

- A part recorded again whose upload failed keeps the check closed until it lands. Hers waits
  only while a take is sending (`noRec`, `:2137`), so there her check opens over the older
  clip the server still holds; ours has replaced the part on the tablet with the new
  recording, and opening would tell the check over a recording the room does not hold.
