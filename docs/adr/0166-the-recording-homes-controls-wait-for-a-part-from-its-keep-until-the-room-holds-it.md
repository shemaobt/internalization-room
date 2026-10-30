---
status: accepted
date: 2026-10-30
amends: 0154 (what counts as a part waiting), 0103 and 0131 (in part: the row of a send that ended on a wait, and an earlier visit's take sent by the tap)
---

# The recording home's controls wait for a part from its keep until the room holds it

This amends ADRs 0154 and 0103 without editing their decisions; it adds "amended by 0166" to
their status lines. It also touches ADR 0131's row states. The Definer settled it on the
ticket (ENG-1985) on 29 October. Her frozen app wins: «Ouvir tudo» shows only once the server
holds every part (`allRecorded`, `app/components/Drafting.tsx:795`, :2541, at 18fa7c4), and a
take is held until its upload answers (:563-596), so a fresh part is never counted as sent.

## Context

ADR 0154 let the check open only once no part waits in the Outbox. A part only counted as
waiting once the Outbox had been counted after the keep. From the keep tap until then the
advance disc lit and the check opened, and the same happened when a station change dropped
that count. «Ouvir tudo» and the wood play did not read the Outbox at all. On the rows, a send
that ended on a wait (the room turned the tablet away, or a join's take fell on the network)
read «enviando…» with no tap for good. An earlier visit's take sent by its tap never read
«✓ salvo».

## Decision

- **A part waits from its keep tap until the room holds it.** The keep in flight counts as
  waiting, and the keep lasts until a count of the Outbox taken after the take went in has been
  applied. A count dropped for a newer one or for a station change does not end it.
- **The advance disc, the check, «Ouvir tudo» and the wood play all wait.** «Ouvir tudo» shows
  only once every scene has its part and the room holds every part. The wood play is dimmed
  while a part waits, and the per-row «Ouvir» stays live.
- **A row whose send ended on a wait reads «falhou — toque para tentar de novo»**, with its
  tap, which sends it again. A take the room refused for good keeps its own words and no tap.
- **A take of an earlier visit sent by its tap belongs to this visit from the tap on.** It
  reads «✓ salvo» once the room's list holds it, and «falhou — toque para tentar de novo» if
  that send fails.
- **The home's busy mark stays a swap in flight.** A part going up does not make the home busy.

## Consequences

- The disc and «Ouvir tudo» stay dark for as long as the tablet takes to copy and count a
  take, which is longer on a slow tablet.
- A take of an earlier visit tapped and then failed leaves the notice and reads on its row as
  a take of this visit.
