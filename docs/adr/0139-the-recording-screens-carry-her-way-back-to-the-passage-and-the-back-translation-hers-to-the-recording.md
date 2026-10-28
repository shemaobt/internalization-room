---
status: accepted, amended by 0142
date: 2026-10-27
amends: 0062 (in part: the ≡ is no longer on the recording screens nor on the Back-translation)
---

# The recording screens carry her way back to the passage, and the Back-translation hers to the recording

This amends ADR 0062 without editing its decision: it adds "amended by 0139" to its status line.
Her app is the bar (João, 26 October: her frozen app wins over our ADRs), settled on the ticket
(ENG-1835).

## Context

ADR 0062 put the ≡ «Escolher outra passagem» on every Station but the Choice and the Closing. On the
grain choice, the Ensaio Final plan, the recording home and the Back-translation it led to the Choice,
and the plan's «pensando…» carried no corner at all. Her recording step never offers another passage:
its screens lead back to where the team came from.

- `Drafting.tsx:2139`: the `back` chevron, «Voltar para a passagem atual», calls `onExit`, which
  `page.tsx:413` (`exitDrafting`) answers by showing the session canvas again. It is drawn on the
  «pensando…» first paint (`:2189`), the plan (`:2268`, `EnsaioFinalPlan.tsx:72`), the grain choice
  (`:2286`) and the recording home (`:2500`).
- `Drafting.tsx:2387`: the Back-translation, the First listen included (`btStep` "listen", `:256`),
  carries «Voltar para a gravação», and `exitBt` (`:1118-1131`) returns to the recording home.
- `page.tsx:1008`: «Escolher outra passagem» is drawn on the session canvas alone.
- `strings.ts:264`, `:274`, `:129`, `:139`: the words, in pt and en.

## Decision

- **The grain choice, the Ensaio Final plan, its «pensando…» and the recording home carry her chevron,
  «Voltar para a passagem atual», where the ≡ stood.** A tap returns to the Conversation of the same
  passage, in the same session. The room falls silent, a take recorded and not kept is thrown away, and
  a plan read still in the air lands nowhere.
- **The Back-translation carries «Voltar para a gravação» at the same spot.** A tap returns to the
  recording home, and the telling-back's local state is reset as the finding's «gravar a parte de novo»
  already resets it.
- **The ≡ stays on the Conversation and the Panorama**, its only places in her app.
- **Both chevrons wear the corner buttons' one body** (ADR 0130), with the chevron glyph, as hers draws
  both with the same chevron.
- **The visibility rule of ADR 0062 is unchanged here:** the chevron hides wherever the ≡ hid. Her
  recording screens never hide it; that rule is ENG-1848's.

## Considered Options

**Keep the ≡ beside the chevron on the recording screens.** Rejected: her recording step has no way to
another passage; the canvas is one tap away.

**Write the Conversation as the resume point on the way back, as her reload lands on the session
(`page.tsx:210`).** Rejected for now: a relaunch on a Conversation point does not restore the takes the
tablet keeps, so a kept part still in the Outbox would be missing from the home until it lands.

## Consequences

- ADR 0062's held take (the pause that comes back on the Choice's way back) is reached by nothing any
  more. `leaveThePassage`, its only way in, is now tapped only on the Conversation and the Panorama,
  where no take is ever held, and her app holds nothing across a leave. It stays in the code until a
  follow-up removes it with 0062's held-take clause.
- A relaunch after the way back still lands where the last stored point says, the recording home.
- Opening the Back-translation again after leaving it plays from the untold ground, as any opening from
  the home does; hers restores the verdict.
