---
status: accepted, amended by 0107, 0108, 0125, 0140
date: 2026-10-20
supersedes: 0050 (in part), 0073 (in part)
amends: 0053, 0074, 0097
---

# Only her six failures raise the person sign, and the Reach is left only on the way in

This supersedes in part ADR 0050 and ADR 0073 and amends ADR 0053, ADR 0074 and ADR 0097
(a refusal of «Ouvir de novo» is no longer counted; ADR 0097's look and its wait for the
reach stand, and its empty look decides by this policy). It adds "superseded in part by
0093" to the status lines of 0050 and 0073 and "amended by 0093" to those of 0053, 0074 and
0097, and edits none of their Decisions. Settled on the ticket (ENG-1355),
19 and 20 October.

## Context

Marcia's app shows the wordless person sign in six cases and halts the room for nothing
else; the team guide's procedure (tap, repeat the last line, twice → Daniel leads) is built
on that. Ours raised the sign from about twenty places: a third refusal of any request, a
code that stops the room at any door, a wait with no turn that timed out, a Session read
saying `needs_person`, a rehearsal part's sound failing twice, an empty take, a wheel with
nothing to offer, a resume that could not be had. And a network failure at any door took
the room out of reach: the offline face, the «sem conexão» line, the retry ladder, and the
Step's request sent again on the return or on any lift.

## Decision

- **The person sign is raised only by the failure policy, in her six cases:** a spoken turn
  the room refuses (any code) or answers with nothing to play; a spoken turn given up whose
  One look finds nothing; a scene rehearsal given up whose look finds nothing, shown once the
  team is back on the Conversation; the reply's sound failing twice; a tablet that cannot
  record; the microphone failing to start twice in a row. The policy reads the tablet's own
  failures beside the room's results. The build guard, a build that can reach no room, shows
  the sign too and calls nobody; it is not one of her cases.
- **Nothing else halts the room.** A refusal of any other request lets its Step go and is
  never counted. A Session read never raises the sign; a refused Watch read changes nothing.
  A resume whose read fails, refused or lost, or whose rehearsal cannot be had, goes back to
  the Choice and keeps its session and the warning the session holds. A resume whose
  rehearsal names a part the room answers is gone for good (its 404) opens the Ensaio with
  that part's scene row not recorded and every other row holding its own part; nothing is
  renumbered (ADR 0102). The stored row is written once as what the team now has, on the
  Ensaio, and from then on as on any other passage; a part the team records on a row with no
  part goes up above the room's own pass for that number, which the row keeps until that row
  is recorded, across a relaunch. A row on the Ensaio with no part opens the Ensaio, not
  the conversa. Any other refusal of a part goes back to the Choice like the network. A
  refused approval keeps the door its hole names, and otherwise returns the team to the Back-
  translation as it stood before «terminei». A scene-rehearsal refusal keeps the scene
  screen's own answer. Only the Guide's sound counts toward the sign; a rehearsal part or a
  stretch that will not play leaves silence. A call for a person needs a session: none of her
  six cases can happen before one exists, so the tablet never calls by its device.
- **What failed, and why, is kept for the operator.** Every decision of the policy is logged
  with its door and its reason, so the failures the team is no longer shown still reach the
  log.
- **Nothing is resent by itself.** A lift sends nothing; the Verdict is asked again only by
  the team's «terminei», with her «não deu para conferir agora» line on the screen.
- **The Reach is left only on the way in.** A network failure on a way in (a Station with no
  session yet: the Choice, a passage or a Panorama not opened) falls as before, with its
  ladder, its notice and its one resend on the return. Anywhere else it changes nothing and
  schedules nothing: a Step waiting on it is let go. ENG-1371 replaces the way in's fall with
  the quiet invite and removes the rest of the ladder; the Outbox keeps its own retry (ADR
  0050, invariant 12).

## Considered Options

**Remove the ladder and the resend from the way in too.** Rejected until ENG-1371: a passage
opened while the server is away would have no way back but a relaunch.

## Consequences

- A network blip during a turn is still decided by the One look: a reply that landed plays,
  nothing found shows the sign.
- A team relaunching into a session the Desk marks as needing a person sees no sign.
- A stretch whose key was still in flight is not sent again on a return; the team tells it
  again.
- The Desk's «precisa de uma pessoa» mark follows the same six cases, because the tablet's
  call goes out exactly when the sign shows.

## Amendment · 2026-10-23 (ENG-1424)

Her third case, as her app draws it. A scene rehearsal given up whose look finds nothing,
and a scene rehearsal the room answers with nothing to play, are one case: the scene screen
stays open, says «não deu para enviar agora — tentem de novo», the sign waits for the team's
return to the Conversation, and the list is read again. «terminei» sends the rehearsal again
under the same turn id; a re-tap that drops again keeps the sign waiting. When the list reads
it as sent, the screen says «a tradução deste ensaio da cena já foi para a voz» and nothing is
sent again. A reply the look finds plays as one that arrived on time, and the screen closes as
after any «terminei».

A «terminei» the room refuses, first tap or again, is not a call for a person, as in her app:
the screen says «não deu para enviar agora — tentem de novo», or «a tradução deste ensaio da
cena já foi para a voz» when the refusal says it was already sent, no sign is raised, and a
sign that was waiting is forgotten. A refusal because the passage closed closes the passage,
and a code that stops the room only reads the list again, leaving a waiting sign waiting. An
answer to «terminei» the tablet cannot read is a lost answer, not a refusal: the one look
runs, as after a drop. An answer belongs to the «terminei» that sent it, as every turn's answer belongs to
the call that sent it: one from an earlier tap, given up on, never acts on the tap that
followed. A «terminei» that lands, or whose
reply the look finds, forgets the waiting sign too. Nothing is resent by itself: a row read as
sent while a person is called is never sent again.
