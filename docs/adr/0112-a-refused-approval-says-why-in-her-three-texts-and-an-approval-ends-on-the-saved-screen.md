---
status: accepted (amended by 0136, amended by ENG-1853, amended by ENG-2028, amended by ENG-2054)
date: 2026-10-22
amends: 0030 (in part: the approval's landing now shows a text), 0014 (her Saved screen is a named exception)
---

# A refused approval says why in her three texts, and an approval ends on the Saved screen

This amends ADR 0030 and ADR 0014 without editing their decisions: it adds "amended by 0112"
under 0030's title and an "Amended by ENG-1259" paragraph to 0014. Her app at Tripod-Internalization
18fa7c4 is the bar (`Drafting.tsx` `finalize` and `approve`, the `saved` screen; `strings.ts`).

Amended by ENG-2028 (2026-10-29): a refusal from the Back-translation only writes her text.
The check is not left before «terminei»: its phase, «terminei», the approve button, lit, and
the badge stay as they were (`Drafting.tsx` `approve` :1607), and the next press asks again.
The approve button stands on the tell view at every phase while the room calls the passage
checked, and it does not act while a guide line speaks, a check or a send runs, a microphone
is open or a sentence's re-record is open (`Drafting.tsx:2468`). Only a last listening the
press itself silenced at conferida counts as heard to its end; nothing else is given back.
Wherever this record or its amendments say a refusal is left before «terminei», read that the
check stays where it was.

Amended by ENG-2054 (2026-10-29): «terminei» reads the room's count of what was heard, not the
end of a listening on this tablet (ADR 0030, amended by ENG-2054). The sentence above on the
last listening the press silenced holds only for a room that names no list.

Amended by ENG-1853 (2026-10-29): a refusal from the Back-translation plays nothing.
«ainda falta ouvir um trecho da gravação» no longer comes with the part playing, and the
landings of ADR 0030 are not unchanged: every refusal was left before «terminei», as ADR 0030
then said — until ENG-2028, above, which leaves the check where it stood. The press's hold ends with the refusal's answer; there is no read of the stretch
it names and no move to it. The three texts and the order that chooses them stand.

## Context

A refused **Approval** showed nothing: the team pressed, the room went quiet, and either a part
played or nothing did. A minted approval said P3 and closed the passage to the Choice, forgetting
the **Resume point**. Her app shows one of three texts under the circle on a refusal, shows the
approved sentence with its **Version**, and ends on «Ensaio salvo» with one button, «Pronto».

## Decision

- **A refused approval always shows one of her three texts** on the **Back-translation**'s
  status line, chosen by the door the room's order picks, whatever that door then does:
  - `playback_did_not_cover_the_clip` → «ainda falta ouvir um trecho da gravação», and the part
    still plays;
  - `telling_back_not_checked`, `telling_back_never_analysed`, `untold_stretch` → «para aprovar,
    a tradução precisa estar conferida». `untold_part`, which this server never raises, is a
    telling-back hole and reads the same;
  - anything else → «não deu para conferir agora — tentem de novo»: a code no door names, an
    answer with neither version nor blockers, a refusal of the request itself (the version
    race's generic 409 included), a network failure. No sign and no spoken failure line; the
    failure still goes to the failure policy.
  The landings of ADR 0030 and 0093 are unchanged. Nothing is resent: the next ask is the
  team's tap. A session gone keeps its own road, with no text.
- **A minted approval shows her approved sentence**, «Aprovado como rascunho final da equipe
  (v{n}). Próximo passo: a checagem externa — o botão aqui embaixo.», says P3, and once the line
  is over the **Saved screen** stands over the Back-translation: a check mark, «Ensaio salvo»,
  the same sentence, «Pronto». It comes whatever happened to the line, whole, cut or never
  given, as her approve does (it awaits the line, then shows the screen); nothing asks the line
  again. Under the person sign «Pronto» fades and leaves the semantics tree, as the way out
  does (ADR 0107).
- **While an approval is in the air, no other Back-translation gesture acts**, from the press
  until the Saved screen comes or the refusal's handling ends (the read and the move to the
  stretch it names): a restart, a retelling, a frase, the recording, the circle, a sentence
  re-recorded or sent again, or a second approval asked in between does nothing, and none of them is drawn live, so nothing moves what was approved. The press also disarms any armed control (the Restart) and clears the
  Back-translation's notice with the refusal text, so a press reads only its own answer, and
  her approved sentence never outlives its approval. The hold belongs to the press and its
  Generation: once the team leaves the passage it holds nothing, and a late answer never
  touches a newer press. The approval itself does not act while a sentence's re-record is
  open.
- **«Pronto» drops the Saved screen and nothing else.** The Station, the Step (checked) and the
  Resume point stay; the passage is not closed. One Session read is asked after the mint, so the
  badge «✓ aprovado como rascunho final (v{n})» comes from a read (ADR 0106).
- The Saved screen is a state value, not a Station.

## Considered Options

**The Saved screen as a Station.** Rejected: «Pronto» returns to the same Station and Step, and
a Station change runs the leaving and arrival effects over a Back-translation that must stay as
it is.

**The badge from the approval's answer.** Rejected: ADR 0106, only a read sets it.

**Close the passage after «Pronto».** Rejected: the Definition of ENG-1259; the approved draft
is where the team goes on to the external check.

**A fourth text for the version race.** Rejected: her three only.

## Consequences

- The passage no longer closes on approval and the Resume point stays on the Back-translation.
- The `Fim` Station, `TheNecklaceClosed`, `beginAgain`, the linger before the Restart and the
  Fim view are no longer reached by any gesture. They are left in place.
- A read after the mint that fails leaves the approve button after «Pronto»; a press asks the
  room, which answers the release that exists, and the Saved screen comes again.
