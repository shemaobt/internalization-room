---
status: accepted (amended by 0141)
date: 2026-10-27
amends: 0106 (in part: where an approved draft reopens), 0116 (in part: a relaunch whose row stood on the check), 0136 (in part: the check reopened after a relaunch, and the count of listeners on the home)
---

# An approved passage reopens on its conversation, and the dot leads to the home with its badge

This amends ADR 0106, ADR 0116 and ADR 0136 without editing their decisions: it adds "amended by
0138" to their status lines. Her app is the bar, and it wins over our ADRs (João, 26 October).

## Context

ADR 0106 landed a Session read that says `approved` on the Back-translation, checked, whichever
door brought it: the open from the Choice, a relaunch, or a resume from any row. Hers never does.
`choosePassage` (`app/page.tsx:774-798`) and the reload (`app/page.tsx:199-213`) both end on
`setView("session")`, with `setShowReplay(conversation.length > 0)` and the last Guide turn as
what «Ouvir de novo» replays; the opening is asked only of a session whose conversation is empty
(`app/lib/openOnce.ts:83`). Nothing in that path reads the approval. The orange dot opens Drafting
(`app/page.tsx:412`, `:1015`), which opens on the recording home of a passage that has its clips and
draws there «✓ aprovado como rascunho final (v{n})», «checagem externa: {n} ouvintes» and
«Checagem externa» (`app/components/Drafting.tsx:2548-2554`). A listener in progress comes back only
when the check is entered again (`app/components/ExternalCheck.tsx:388-395`).

## Decision

- **A Session read that says `approved`, with stretches told, lands on the passage's
  conversation at rest**, whichever door brought it: «Ouvir de novo» is armed, the Opening is never
  asked (even of a session the room never opened), nothing plays, and the Resume point is written
  on the conversation, keeping its parts and its listener. A resume that had already put the team on
  the Rehearsal is brought back to the conversation.
- **The landing fetches no parts.** The orange dot leads to the recording home, which lays the
  room's parts in behind its rows as it does for any passage, and draws the badge from the newest
  applied Session read (ADR 0136).
- **A relaunch whose row stood on the check lands on the conversation too.** The listener stays in
  the Resume point, and «Checagem externa» tapped on the home asks the room for them and lands where
  ADR 0116 says, silent. A read or an open that fails leaves the team on the home with her
  open-failed words, «não deu para abrir a checagem externa — tentem de novo»
  (`app/components/Drafting.tsx:1634`), and the next tap tries again.
- **The recording home draws the count of listeners** between the badge and «Checagem externa»,
  with the Back-translation's words, and the check that leaves to the home reads the session again
  so the count is the room's.
- A tablet whose Outbox still holds anything of the session that changes the packet lands where it
  stood, as ADR 0106 said.

## Consequences

- The Back-translation over an approved draft is reached from the home, through the parts again,
  never straight from a reopen; the badge and the count it draws are unchanged.
- The Station a relaunch without an approval lands on is still the row's (ADR 0064); that is ENG-1896.
