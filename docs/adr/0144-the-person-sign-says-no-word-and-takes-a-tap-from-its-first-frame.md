---
status: accepted
date: 2026-10-28
amends: 0107
---

# The person sign says no word and takes a tap from its first frame

This amends ADR 0107 without editing its decision: it adds "amended by 0144" to its status
line. Marcia's handoff is a plain div with a click and no aria-label (`app/page.tsx:1063`, at
18fa7c4), whose clicks count the moment the phase turns (`app/globals.css:234`,
`pointer-events:auto` with no delay). ENG-1894 brings ours to hers. Her frozen app wins over
ADR 0107.

## Decision

1. **The sign carries no label and no role.** VoiceOver hears neither «Um momento para uma
   pessoa» nor «A moment for someone», and the wash is not a button. The wash keeps its tap,
   and with it the gesture's own action, as her div keeps its click. The label goes with the
   role: an unnamed button would have been the one node VoiceOver lands on while the circle is
   out of the tree under the halt.
2. **A tap on the rising sign clears it**, exactly as a tap on the fully shown one. The fade is
   unchanged: 1.6 s, ease, as hers.
3. **A tap on the sign as it fades out still does nothing**, and nothing beneath receives it.
   Hers lets that tap through to the circle; that difference is a follow-up, not this ADR.

## Considered Options

**Drop only the label.** Rejected: it leaves an unnamed button.

**Drop the guard entirely.** Rejected: a tap on the fading wash would then run half a gesture
(the armed tap handed over, the disk word cleared) with no halt to clear, a change nobody asked
for and that is not hers either.

## Amends

- 0107: «the wash alone carries «Um momento para uma pessoa» to VoiceOver» no longer holds; the
  wash carries nothing. «Only a tap on the fully shown wash clears the sign» now reads: a tap on
  the rising or fully shown wash clears it. The rejected option «Clear the sign on a tap at any
  time, the fade included» is taken for the rise, as hers; a second tap as it fades still never
  opens the microphone.
