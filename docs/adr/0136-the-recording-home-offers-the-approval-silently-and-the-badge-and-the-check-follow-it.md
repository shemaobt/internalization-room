---
status: accepted (amended by 0138, amended by 0150, amended by 0151, amended by ENG-1910 (2026-10-30: a refused approval on the home keeps its button), amended by ENG-1909 (2026-11-02: the approve button stays drawn and rests while a take records or waits; the badge stands whenever a release does))
date: 2026-10-26
amends: 0106 (in part: the approved badge also stands on the recording home), 0112 (in part: the approval is offered, refused and saved from the recording home too), 0116 (in part: the external check opened from the home leaves to the home)
---

# The recording home offers the approval silently, and the badge and the check follow it

This amends ADR 0106, ADR 0112 and ADR 0116 without editing their decisions: it adds "amended by 0136"
to their status lines. Her app is the bar (`Drafting.tsx` `approve`, `approveOffered`, `exitExt`): one
approve door on the recording home, whatever the mode, ending in the Saved screen with the mode unchanged.

## Decision

- **The home offers «Aprovar como rascunho final» exactly when the room calls the passage checked**
  (`btChecked`, the session read's `checked`), no release stands, nothing is being recorded or sent,
  and no act is in the air. A kept take drops `btChecked` until the room is read again once the take is up.
- **The approval from the home is silent**: no voiced line, no P3. It ends on «Ensaio salvo» drawn over the
  home, with no stage change, so the resume point stays the home. «Pronto» returns to the home, which then
  draws the approved badge and the «Checagem externa» button.
- **A refusal from the home shows one of her three texts on the home**, chosen by the same door order
  as ADR 0112 (the first hole its order names): a part nobody heard → «ainda falta ouvir um trecho da
  gravação»; an untold stretch or part, or a check not made → «para aprovar, a tradução precisa estar
  conferida» and the offer is withdrawn; anything else (an unknown code, an answer with neither a
  version nor blockers, a failed request) → «não deu para conferir agora — tentem de novo». The home
  runs none of the Back-translation's doors (no part plays, no stretch is opened). A request refused
  outright (a version race) still takes the Back-translation's failure path, whose changes are
  invisible on the home. The text clears when the station changes or a take is kept.
- **The record circle waits while the approval is in the air.**
- **The external check leaves to the door it was opened from.** Opened from the home, or reopened after a
  relaunch, it leaves to the recording home and the resume point is the home; opened from the
  Back-translation without a relaunch, it leaves there (ADR 0116).

## Amendment · 2026-10-30 (ENG-1910)

As hers (`Drafting.tsx:709-717`), which refreshes nothing after a refused approval:

- A refusal because the telling is not conferida writes «para aprovar, a tradução precisa estar conferida» and the offer stays: the button and «✓ traduzida e conferida» are no longer withdrawn by the refusal. Only a Session read that says the passage is not checked takes them away.
- An approval from the home lost on the network writes «não deu para conferir agora — tentem de novo» and the Failure policy decides it at the approval's own door: her line only, no person.
- A gone session and a refused request still take the Failure policy.

## Amendment · 2026-11-02 (ENG-1909)

As hers (`Drafting.tsx:2547-2548`), which draws the button on conferida and the release alone, disabled while busy, and the badge on the release alone:

- The button is offered when the room calls the passage checked, the approval is still open and nothing is saved. It acts only when the home is idle, nothing waits in the Outbox and no approval or open is in the air; otherwise it stays drawn and rests, and a press sends nothing.
- The approved badge, the listeners line and «Checagem externa» stand on the home whenever the passage has a release, while a take records or waits in the Outbox too. «Checagem externa» still rests while the microphone is open.
