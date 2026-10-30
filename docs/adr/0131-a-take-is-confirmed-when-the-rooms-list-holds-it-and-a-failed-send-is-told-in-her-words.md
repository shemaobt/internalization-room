---
status: accepted, amended by 0146, 0155, and by 0087's amendment of 28 October (ENG-1777: the ladder, the codeless drain and the relaunch send are gone; a join row left waiting at a drop waits for its scene row's tap), amended by 0166 (a row whose send ended on a wait reads failed with its tap)
date: 2026-10-22
amends: 0087, 0103, 0014, 0102
---

# A take is confirmed when the room's list holds it, and a failed send is told in her words

This amends ADRs 0087, 0103, 0014 and 0102 without editing their decisions; their status lines
say so. The Definer settled the rule with Jonatas on 22 October (ENG-1774), and the open
points were answered by the Orchestrator the same day.

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
  tablet spends none and stops the pass, as before. A row an older app left with three or
  more attempts reads as spent.
- **A take is spent only while a row can offer its tap.** Once the grain is known, a take
  of the open session that no row shows under it, such as a part after a switch to the
  whole passage, is never held for a tap, whatever spent it, except a refused one, which
  the room would refuse again: it goes up on a later pass, after every take a row can
  show, and the room sets it aside as ADR 0134 expects. The count that gates the
  approval leaves it out; it stays in the Outbox, untouched. While the grain is not known
  every spent take waits for its tap. The Orchestrator decided this on 27 October.
- **A join row keeps ADR 0120's window.** A network failure on a row of a join or a swap
  (one that names its rehearsal) is a wait, never an attempt, so it is never spent by the
  network: the join resends it quietly every 5 s for 90 s, and one still waiting at a drop
  goes up by itself after the relaunch. The Orchestrator decided this on 27 October.
- **Only a tap sends a spent take.** A take whose three attempts are gone does not go up
  by itself. One older exception stands: a part take refused with a bare `HTTP_*` code
  gets one more try on the Outbox's retry drain, which asks for the codeless; ENG-1777
  closes that gap. A spent take still holds the recordings made after it in its part (ADR
  0025); a take refused for good does not, nor one whose recording is gone. A take held
  behind a spent one is not due either: it arms no retry, reads «falhou — toque para
  tentar de novo» like the spent one, and waits for the tap that sends the spent one, then
  it. A tap on a part sends every unsent pass of it, older ones first, each with three
  attempts, whichever way its newest take took, even one that never reached the Outbox and
  fails to reach it again; an older pass refused for good is not sent again, while the
  pass the tap names is sent once more even if it was refused. A part reads as being kept
  from the moment its keep starts, and a tap on it is refused until the keep ends, so no
  tap reorders its takes. A keep on the red microphone does the same for the scene takes
  of its session before it: the room numbers a session's scene rehearsals by arrival (`n`
  is the session's highest plus one when it is stored; the recording time does not number
  it), so a newer take that arrived first would take an older one's number.
- **«parar» after 8 s** of sending, counted from when the first take of the tap or keep
  left in this pass: a part's older passes and a scene take sent ahead of the one the red
  microphone keeps count toward the same 8 s. A tap stops whichever take of that tap or
  keep is in the air, and only while it is this session's take in the air: the tap names the
  keep (its session, its part or scene, and when it began sending), not one row, so a tap
  that lands as one take of the keep hands over to the next stops the next. It never stops
  a take outside it. The request is let go, the take's attempts are spent, every take stays
  on the tablet and the pass ends. On the red microphone a keep stopped before its own take
  left reads «não deu para guardar o ensaio da cena — gravem de novo» with «falhou — toque
  para tentar de novo», and the tap sends the earlier take, then its own.
- **The take in the air, and the parts kept this visit, are the machine's.** The Outbox
  tells the machine when a take leaves (with the time its tap or keep began leaving, read
  through `package:clock`) and when it settles; the notifier tells it when a part's keep
  begins and which row it wrote. The machine holds which take is in the air, of which
  session, which parts are being kept, and which rows this visit kept. These are facts of
  the app run, so they are carried when the team leaves a passage and opens one again, as
  the held Panorama is; the rows are keyed by session, so nothing of one session reads on
  another's rows. «parar» is a gesture the machine turns into an effect the runner hands
  to the Outbox, naming the take. The screens read the take in the air, the parts being
  kept, and the parts saved, from the machine's Outbox facts. The newest take of a part,
  the highest pass and the last written on a tie, decides its row: while it is being kept
  the row reads «enviando…» and offers no tap, whatever it read before; it reads «✓ salvo»
  only when that take is one the room holds; and it reads «falhou — grave de novo», with
  no tap, when its recording is gone, whether it reached the Outbox or not, never an older
  pass's «✓ salvo».
- **A gone recording is final.** A take whose recording is gone can never go up, so it
  offers no tap and the room refuses a re-send of it, as for a final refusal; this holds
  for a part on its row and for a scene take on the red microphone. It also holds after a
  relaunch, and the row offers no «Ouvir» that would play the gone take; the room's own
  part still plays. Recording again recovers it: a new part take takes its part's gone
  takes off the Outbox, and a part take the room holds takes those at or below its own
  pass, so a newer gone take is still told; a new one waits behind any spent older pass
  whose recording is still on the tablet, and its tap sends both, older first.
  The Orchestrator decided this on 23 October; Jonatas may overrule it.
- **A part beyond the last scene has its own row.** Each part beyond the passage's last
  scene that has a take still to send, in the air, being kept or kept this visit shows a
  numbered row after the scenes, with the same words, the same tap and the same rules as
  any part's row. Jonatas decided this on 23 October. The row tells the send and nothing
  else: no «Gravar», «Ouvir» or «Gravar de novo», and recording on it records nothing, so
  a part past the scenes is recorded again only by the circle, after a finding sent the
  team back to it. Once an earlier visit's take of it is sent the row leaves; a take kept
  this visit keeps it with «✓ salvo». The Orchestrator decided this on 23 October.
- **A tap acts on the session and app run it was made in.** It names its session and part
  when it lands, and nothing it does after waiting on the Outbox touches another session's
  takes. Once its run has ended it makes no spent take due again; a take it had already
  handed to the Outbox goes as any kept take does.
- **Every take over 25 MB is refused before sending,** of any kind: the room answers an
  oversize upload with a bare `BAD_REQUEST`, so only the tablet can tell it as too large.
- **The take's state is told on its screen in her words, never by the voice:** «gravando»;
  «enviando…» while it is being kept or sent, until confirmed, spent or refused; «✓ salvo»
  once listed, for a part of this session's visit; «falhou — toque para tentar de novo»
  when spent or stopped, on a take held behind a spent one, and on a newest take that
  never reached the Outbox; «falhou — grave de novo», with no tap, on a part's newest take
  whose recording is gone; «grande demais para o servidor — grave em partes menores» and
  «não foi aceita — grave de novo» for final refusals, which offer no tap on the ensaio row.
  On the red microphone a failed scene take reads «não deu para guardar o ensaio da cena —
  gravem de novo» (or the too-large or not-accepted line) with «falhou — toque para tentar
  de novo» as its tap, or with «falhou» and no tap once its recording is gone. The red
  microphone's take state is a named exception to the wordless rule (ADR 0014).

## What this replaces in ADR 0103

- "A take of this visit still on its first try shows nothing new": it reads «enviando…».
- "A take refused for good is sent once more": only by the tap on its own row, which
  reads «enviar agora» for a take of an earlier visit; this visit's refused take reads her
  refusal words with no tap.
- "The automatic retry stays, untouched": only a tap sends a spent take; the ladder now
  only paces a tablet the room turned away and the retro copy (until ENG-1411), and
  ENG-1777 removes it.
- "A part beyond the last scene … the Outbox still retries it": it is no longer retried by
  itself. Each unsent part beyond the last scene shows its own numbered row on the Ensaio
  screen, with the same words and the same tap as any part's row (Jonatas, 23 October).

## What this replaces in ADR 0102

- "Parts beyond the last scene … get no row": a part beyond the last scene with a take to
  tell has a row after the scenes that tells the send and records nothing.

## Consequences

One more read per confirmed take. A take the room stored but never listed stays on the
tablet and reads as failed; its next tap re-sends bytes the room already holds and is
confirmed by the list. A take recorded while the server is away reads «falhou — toque para
tentar de novo» once its attempts are spent and goes up when the team taps it. A spent
scene take still shows when the red microphone reopens, and a later keep makes it due, as
ADR 0087 says of a take still waiting. A retro take gets the same confirmation and no words:
nothing on the retro screen shows it. Kind `retro` is outside the per-tap rule until
ENG-1411 takes it out of the Outbox: with no tap to give it attempts, it keeps the five
attempts and the ladder it had, a network failure or an unlisted answer pacing it without
spending it.
