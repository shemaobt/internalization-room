---
status: accepted
date: 2026-10-29
amends: 0100 (play over an earlier frase's retell), 0157 (the take's end)
---

# Play over an earlier retell toggles the take, and a take at its end plays from the start

On the scene rehearsal, three cases of play still followed ours and not Marcia's app at
Tripod-Internalization 18fa7c4 (`app/components/Rehearsal.tsx:648-666`, `togglePlay`;
ENG-2085).

- With an earlier frase translated again (no pause on the move), ADR 0100 had play let the
  retell go and play the take on from where the translation stopped. Hers lets the retell and
  its line go and toggles the take (`:657`): play now plays the take on from where the frase's
  replay paused, and while that replay still sounds, play only pauses it and marks no pausa.
- With the last frase's pause on the move, ADR 0157 had play hear «ouvir a pausa» only with the
  pause at the take's own end. Hers does it when the pause stands within 0.05 s of the end
  (`:654`): a pause a few milliseconds short of the end no longer plays those milliseconds and
  goes quiet.
- On the sent step, a frase bar played to the take's end left the take there, so the next play
  ended at once and only the one after started from the beginning. Hers starts an ended take
  over from 0 (`:665`): play now starts from the beginning when the take stopped at or past
  its end, as it already did after the whole take was heard.

## Consequences

- After play paused an earlier frase's replay, the next play goes on from where the
  translation stopped, as play does on any take paused with no pausa; hers resumes where it
  paused. That difference is older than this record and is left for its own ticket.
- A frase replayed to the take's end on the sent step still leaves what was heard as partly,
  with the paused clock at the end, as hers leaves the take paused there, not ended.
