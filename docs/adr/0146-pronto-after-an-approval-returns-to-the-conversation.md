---
status: accepted
date: 2026-10-28
amends: 0136 (in part: where «Pronto» returns to after an approval from the home)
---

# «Pronto» after an approval returns to the conversation

This amends ADR 0136 without editing its decision: it adds "amended by 0146" to its status line.
Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket (ENG-1836).

## Context

ADR 0136 ended the approval from the recording home on «Ensaio salvo» drawn over the home, and
«Pronto» returned to the home, which then drew the approved badge and «Checagem externa». The
approval from the Back-translation ended the same way over the Back-translation. Hers does
neither.

- `app/components/Drafting.tsx:1598-1612`: `approve` sets `saved` from either mode, the
  recording home and the Back-translation alike.
- `app/components/Drafting.tsx:2196`: the Saved screen's «Pronto» calls `onExit`, the same
  `onExit` as the way back at `:2139`.
- `app/page.tsx:944`, `:413`: `onExit` is `exitDrafting`, which ends on `setView("session")`, the
  conversation.
- `app/lib/strings.ts:276`, `:141`: «Pronto», «Done».

## Decision

- **«Pronto» after an approval lands on the passage's conversation at rest**, from the recording
  home and from the Back-translation alike: «Ouvir de novo» is armed, nothing is said or played,
  and the Opening is never asked. The line said last was the check's verdict, so it is dropped,
  and «Ouvir de novo» asks the room for the Guide's last line, as on every landing at rest.
- **The Back-translation answers the way out of the recording with the conversation**, as the
  recording home already did; the machine's `TheRecordingLeft` carries both.
- **The orange dot leads back to the recording home**, which draws the approved badge and
  «Checagem externa» from its own Session read (ADR 0138).
- **«Pronto» writes no Resume point.** A relaunch lands on the conversation whatever the row
  names (ADR 0141).

## Consequences

- The Back-translation over an approved draft is reached again from the home, through
  «Traduzir a gravação», never straight from the Saved screen.
- ADR 0136's «Pronto returns to the home» no longer holds; the rest of its decision stands.
