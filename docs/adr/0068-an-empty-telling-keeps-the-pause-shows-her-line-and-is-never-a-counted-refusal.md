---
status: accepted
date: 2026-10-07
amends: 0053 (the policy gains a row and an event that never counts), 0046 (in part: a wordless stretch is answered by her line shown, not the inaudible line)
---

# An empty telling keeps the pause, shows her line, and is never a counted refusal

This amends ADRs 0053 and 0046 without editing their decisions; it adds "amended by 0068"
to their status lines. The Definer settled the rule on 7 October (ENG-1450), the app half of
the server's change (ENG-1226).

## Context

Since the server's ADR 0049, both telling doors refuse a telling with no words with a 422
and the code `WORDLESS_TELLING`, and send no line. The tablet had no such code, so the
failure policy counted the refusal like any other and the third one raised a blocking halt
that called for a person. The refused recording also stayed pending with the confirm lit,
so a confirm resent it under the same key and counted again. ADR 0046 said a wordless
stretch is answered with the inaudible line; the tablet never voiced it, and the server no
longer sends it. In Marcia's app the screen stays paused on the piece and shows «Não
entendi — traduzam de novo esse pedaço», and nothing is voiced.

## Decision

- **The policy has a row for it.** `WORDLESS_TELLING` becomes `TheTellingCameBackEmpty`,
  after the row for a passage that cannot open and before the generic refusal, so it never
  reaches the strike count. A rule that answers earlier (passes, keeps the resume, asks
  again) still does.
- **The machine answers in the Back-translation only.** It sets the fact that the telling
  came back empty and lets the pending translation go: no refusal counted, no line played,
  the part left where the confirm held it. Anywhere else the event changes nothing. The
  Station clears the pending translation and ends its wait, and keeps the recording's copy
  in the Outbox; only the circle is offered.
- **The fact clears three ways:** the capture microphone opening, a telling with words
  landing (a plain answering event, `TheTellingLanded`, not the room's answer, which every
  session read also brings), and the team leaving the Back-translation. A halt does not
  clear it, and it is not kept in the slice, so a reopened session shows nothing.
- **Shown, in a wordless room (ADR 0014),** means a mark beside the circle, on the side
  opposite the warning mark and drawn like it in the blue of the translation, whose
  VoiceOver label is her line; the circle's own label becomes her line too. A person and
  the offline face still win the circle's label, and a blocking halt hides the mark as it
  hides the warning.
- **A refused replacement leaves the earlier telling** as it was, and the part does not
  resume: the stretch stays named, and the tap reopens the microphone on its bounds.
- **`captured` is retired** from both telling answers, with the two branches that read it.
  The server answers every telling it takes with words, and refuses the rest.

## Considered Options

**A notifier arm on the code.** Rejected: ADR 0053 keeps every failure decision in the
policy, and the guard test enforces it.

**Clearing the fact on any room answer.** Rejected: a background session read would wipe
her line before the team acted.

**Withdrawing the refused recording from the Outbox.** Rejected: the copy is audio the team
made, and it goes up as any other.

## Consequences

- An empty telling never calls a person, however many times it comes back.
- ADR 0046's sentence that a wordless stretch is answered with the inaudible line is no
  longer true for the telling doors.
- A server before shema-api #637 answered a replacement 200 with `captured: false`; the
  tablet now reads that as a telling that landed.
