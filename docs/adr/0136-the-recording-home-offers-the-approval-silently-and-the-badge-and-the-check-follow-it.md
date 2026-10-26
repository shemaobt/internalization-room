---
status: accepted
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
- **A refusal from the home shows one of her three texts on the home** and runs no Back-translation
  routine: `playback_did_not_cover_the_clip` → «ainda falta ouvir um trecho da gravação»; any other
  blocker → «para aprovar, a tradução precisa estar conferida» and the offer is withdrawn; a failed request
  → «não deu para conferir agora — tentem de novo».
- **The record circle waits while the approval is in the air.**
- **The external check leaves to the door it was opened from.** Opened from the home, or reopened after a
  relaunch, it leaves to the recording home and the resume point is the home; opened from the
  Back-translation without a relaunch, it leaves there (ADR 0116).
