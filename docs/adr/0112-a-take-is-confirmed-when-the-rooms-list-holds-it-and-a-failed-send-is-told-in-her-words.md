---
status: accepted
date: 2026-10-22
amends: 0087
---

# A take is confirmed when the room's list holds it, and a failed send is told in her words

This amends ADR 0087's confirmation line; 0087's status line says so. The Definer settled the
rule with Jonatas on 22 October (ENG-1774), and the open points were answered by the
Orchestrator the same day.

## Context

The **Outbox** confirmed a take on the upload's answer alone and deleted its copy at once.
Nothing read the room's list after an upload, so an answer the room did not bear out read
as saved. It gave a take five attempts on a ladder of 5 s to 10 min, and a network failure
never counted, so a send on a dead link waited minutes with no word. Nothing could stop a
send in flight. On the red microphone the failure words were VoiceOver labels only.
Marcia's app (`draftUpload.ts`, `Drafting.tsx` at 18fa7c4) proves a take by the server's own
record of it, tries three times 1 s then 3 s apart, and offers «parar» after 8 s of sending.

## Decision

- **Confirmed means listed.** After the upload answers, the Outbox reads the room's list
  (the session's takes for a part or a retro take, the passage's scene rehearsals for a
  scene take). Only a take the list holds is confirmed; its row and its copy leave then.
  An answer the list does not hold, or a list that cannot be read, is a failed attempt.
- **A re-send is safe.** The room answers the same bytes with the take it already holds
  (same id, no refusal), so an attempt after a lost answer or a failed list read sends the
  take again and reads the list again. Confirmation relies on that dedupe.
- **Three attempts per tap,** in one pass, one upload at a time and in order (ADR 0025),
  1 s then 3 s apart. A network failure, a timeout, an unlisted answer and a failed list
  read each spend one. A final refusal spends all three at once. A revoked or unauthorized
  tablet spends none and stops the pass, as before. A spent take is never sent again
  without the team's tap: nothing goes up by itself once its three attempts are gone. It
  still holds the recordings made after it in its part (ADR 0025), as a take refused for
  good does not. A tap on a part, or a keep on the red microphone, gives every unsent
  recording before it three attempts, so they still leave in the order recorded. A row an older app left with three or more attempts reads as
  spent; a tap gives it three again.
- **«parar» after 8 s** of one take's send, counted from its first attempt of the pass. A
  tap lets the request go (the upload is aborted), spends the take's attempts, keeps it on
  the tablet and ends the pass.
- **Every take over 25 MB is refused before sending,** of any kind: the room answers an
  oversize upload with a bare `BAD_REQUEST`, so only the tablet can tell it as too large.
- **The take's state is told on its screen in her words, never by the voice:** «gravando»,
  «enviando…» until confirmed, spent or refused, «✓ salvo» once listed (for a part of this
  visit), «falhou — toque para tentar de novo» when spent or stopped, «grande demais para o
  servidor — grave em partes menores» and «não foi aceita — grave de novo» for final
  refusals, which offer no tap on the ensaio row. On the red microphone a failed scene take
  reads «não deu para guardar o ensaio da cena — gravem de novo» (or the too-large or
  not-accepted line) with «falhou — toque para tentar de novo» as its tap. The red
  microphone's take state is a named exception to the wordless rule.

## Consequences

One more read per confirmed take. A take the room stored but never listed stays on the
tablet and reads as failed; its next tap re-sends bytes the room already holds and is
confirmed by the list. A take recorded while the server is away reads «falhou — toque para
tentar de novo» once its attempts are spent and goes up when the team taps it. The ladder
between passes now only paces a tablet the room turned away; ENG-1777 removes it. A spent
scene take still shows when the red microphone reopens, and a later keep makes it due, as
ADR 0087 says of a take still waiting. A retro take gets the same confirmation and no words:
nothing on the retro screen shows it. Kind `retro` is outside the per-tap rule until
ENG-1411 takes it out of the Outbox: with no tap to give it attempts, it keeps the five
attempts and the ladder it had, a network failure or an unlisted answer pacing it without
spending it.
