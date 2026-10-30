---
status: accepted, amended by 0167
date: 2026-10-29
amends: 0153
---

# The check's strips keep the player on a paused take, and the retold band follows its pause

This amends ADR 0153 without editing its decision: it adds "amended by 0162" to its status line.
Her app is the bar, and it wins over our ADRs (João, 26 October). Settled on the ticket
(ENG-2042).

## Context

ADR 0153 put her strip on the check: the told stretches as bands, the pending pausa in telha
on the part in the air, and the player's line on the part that sounds. Two things on her strip
were left out. Her player keeps the last place it reported on a take through a pause, so the
line stays where the team stopped (`Drafting.tsx:2381`, `chainPlayer.ts:113-116`); ours drew
the line only while the part was in the player. And while a frase is told again with its pause
on the move, her band of that frase ends at the pending cut (`Drafting.tsx:2380`); ours kept
the frase's old end while «um pouco antes / depois» moved the pause away from it.

## Decision

**A paused take keeps the player's line on its strip where it stopped, and the band of the
frase told again ends at its pending pause.** The line stays while something plays over the
paused part or the microphone takes the team's translation, and while the team's own
translation plays; it leaves when a stretch of another part sounds, when another part plays,
and when the last part ends. The moving end is drawn on the ruler of the frase's place in its
part, as the replay already carries it.

## Consequences

The strip says where the team is in the take after a pause as well as during play, and the
frase they are telling again shows how far it now runs. The line does not ride a frase replay
or «ouvir a pausa» as hers does, it does not follow the pause after a nudge, and it does not
stay at the take's end after the last part: those differences are recorded as findings for
follow-up tickets.
