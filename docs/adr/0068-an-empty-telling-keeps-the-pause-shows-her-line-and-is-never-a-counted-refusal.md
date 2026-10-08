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

Since shema-api ADR 0049, both telling doors refuse a telling with no words with a 422
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
  Station clears the pending translation, deletes its recording file and ends its wait; the
  Outbox keeps its own copy. Only the circle is offered: the confirm, the scissors and the
  listen control stay dark while the fact stands.
- **A refusal is an answer.** Only a telling that got no answer (the network failed or timed
  out) waits as told-without-answer for a later landing; a refused one never does, so a
  refusal cannot hide the team's own landed telling behind a stranger's.
- **The fact clears three ways:** the capture microphone opening, the team asking for the
  verdict (`TheVerdictAsked`, which closes the stretch's open telling), and the team leaving
  the Back-translation. A telling with words needs no clearing of its own: once the pending
  translation is let go, nothing can land until the team records again, and the microphone
  that records has already cleared the fact. A halt does not clear it, and it is not kept in
  the slice, so a reopened session shows nothing.
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

**A clearing when a telling lands.** Dropped: measured, no landing can reach the room while
the fact stands, so the event would have had no witness.

**Withdrawing the refused recording from the Outbox.** Rejected: the copy is audio the team
made, and it goes up as any other.

## Consequences

- An empty telling never calls a person, however many times it comes back.
- ADR 0046's sentence that a wordless stretch is answered with the inaudible line is no
  longer true for the telling doors.
- A server before shema-api #637 answered a replacement 200 with `captured: false`; the
  tablet now reads that as a telling that landed.
