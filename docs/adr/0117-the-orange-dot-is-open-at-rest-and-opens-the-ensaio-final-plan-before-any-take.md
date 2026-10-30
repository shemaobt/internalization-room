---
status: accepted, amended by 0134 (the 6 s cut and a passage with no scenes open the grain choice while no grain is in force); amended by ENG-1828 (2026-10-29: an empty whole-passage recording with no scene rehearsal of the session opens the whole-passage home); amended by ENG-1861 (2026-10-29: a take the room has not received never decides where the dot goes); amended by ENG-2104 (2026-10-30: the notice's «enviar agora» rests while a take of the session goes up or a join, a swap or a bring-back runs)
date: 2026-10-22
amends: 0014
---

# The orange dot is open at rest and opens the Ensaio Final plan before any take, and a whole set aside is held by its file or the room's id

This supersedes the rule ENG-1441 left in ADR 0037's status note, "before the dot lights
there is no way to the whole-passage recording", and amends ADR 0014 without editing its
decision. The Definer settled the rules on ENG-1382 (Definition and Split of 22 October).

## Context

Ours drew the orange dot only once the voice had said its send-off, and its tap always opened
the recording home. Marcia's dot is faint and tappable whenever the canvas rests, bright from
the send-off, gone while the voice is busy, a microphone is open or a person is called, and
never on a Panorama. Its tap opens her Ensaio Final plan over a passage with no take, and the
recording home once one exists. A tap that reaches the room while the voice speaks or a
microphone records would cut the team off, so the dot's own hiding rule is also the rule its
tap obeys.

Separately, a resume over a whole rehearsal set aside behind scene parts kept the whole under
a file name nobody wrote. Every relaunch found it missing, read the room again and rebuilt the
parts from its listing, so a part still waiting in the Outbox read as the room's older take
and a new recording of it went up at a pass already used.

## Decision

- **The dot has three looks, decided in one place:** gone (unseen, deaf, out of a screen
  reader's reach) while the way out is hidden and while any voice sounds; bright from the
  send-off, the completion floor or the Ensaio Final moment; faint otherwise. It is never drawn on a Panorama. Its name is
  «Gravar o ensaio de vocês», and «Abrir o Ensaio Final» once a current part came from a
  join, part by part: the tablet's take where it holds one, the room's listing otherwise.
- **The tap refuses whenever the dot is gone**, and with a turn in flight, as the red
  microphone does, and while a sent note's microphone is still closing, so the note is never
  lost on its way out. A tap on the dot still discards a raised-hand note, as hers does.
- **Where the tap goes:** a passage with a take the tablet holds opens the recording home at
  once. Otherwise the **Ensaio Final plan** opens, a Step of the Rehearsal showing «pensando…»
  while the Outbox is read and the room is asked for the passage's takes, scene rehearsals
  and scenes. A take waiting in the Outbox or in the room's listing opens the recording home;
  no take and known scenes keep the plan; anything else (a failed read, no scenes, six
  seconds without an answer) opens the recording home, never the person sign. «pensando…»
  never stands past six seconds. Only a session the room has forgotten goes through the
  Failure policy.
- **The recording home the dot opens lays in the room's listing behind its rows**, whichever
  way it was reached: the room's parts for scenes the tablet holds none of come in under their
  rows as they arrive, and a part recorded again goes up above every pass the room holds for
  it, whether or not its audio could be fetched.
- **The plan is never a resume point.** A relaunch on the plan lands on the Conversation.
- **A whole set aside is held by its file when the tablet has one, otherwise by the room's
  take id** in the Resume point, never under a made-up name. A whole beside parts is never
  counted missing on a resume, so a relaunch reads the room only for a part it lacks; a
  point an earlier app wrote under the made-up name reads the same way.

## Consequences

- The grain choice, the whole-passage recording over scene parts and their switch are not
  here: ENG-1765 and ENG-1766 carry them, and until then every case where her app shows the
  grain choice opens today's recording home.
- The plan shows only its heading, her line and «Gravar cena por cena» until ENG-1383 adds
  its rows. The plan over joined parts with a scene still left to join, as the Ensaio Final
  plan entry reads, arrives with ENG-1385; until then any take opens the recording home.
- Golden images of the Conversation now show the faint dot at rest.

## Amendment · 2026-10-29 (ENG-1828)

Her frozen app is the rule (João, 2026-10-26). With no take hers opens the plan only when the
session holds a scene rehearsal, sent or not, or when the draft's grain is not `whole`, the
passage has scenes and no rehearsal sits elsewhere (`efScreen`, ensaioFinal.ts:79-80 at
18fa7c4); an empty whole draft with no rehearsal of the session falls to the whole-passage
record screen. «No take and known scenes keep the plan» changes: **with the whole passage in
force, no take and no scene rehearsal of the session open the whole-passage home.** A scene
rehearsal of the session, or no grain in force, still keeps the plan.

## Amendment · 2026-10-29 (ENG-1861)

Her frozen app is the rule (João, 2026-10-26). Hers chooses the dot's screen from the server's
draft alone (`efScreen` and `draftDecidesScreen`, ensaioFinal.ts:74-86,114-117 at 18fa7c4);
what the tablet still holds is drawn over whichever screen that is, as her pending notice
(Drafting.tsx:2200-2214). **Where the tap goes** changes in two places:

- A passage opens the recording home at once only over a take **the room has received** that
  came from no join. A take the tablet holds that never reached the room goes through the plan
  read like any passage with no take.
- **A hand take waiting in the Outbox no longer opens the recording home**; only the room's
  listing does. A join still on its way in the Outbox is still a waiting part of the plan.

A take the room has not received is offered on top of the screen the room's listing chose: the
plan and the grain choice draw her line «Uma gravação ainda está neste computador e não foi
enviada.» with one «Cena N · m:ss — enviar agora» per take, as the recording home already did,
and «A passagem inteira · m:ss — enviar agora» for a whole-passage take, as hers names it
whatever the grain: under the whole grain, and first while the room names no grain
(ENG-2078).
A take sent from there that reaches the room opens the recording home of the grain the room now
lists it under, from the grain choice too, as her screen turns to the draft's once the draft
holds it. A part the home words as gone or refused is not offered there, by the same rule as
the home's rows. A take of the other grain stays on the tablet, unoffered.

## Amendment · 2026-10-30 (ENG-2104)

Her frozen app is the rule (João, 2026-10-26). Her pending notice's send is
`disabled={sending || phaseBusy}` (Drafting.tsx:2209 at 18fa7c4): a take sending, a join, a
swap, a bring-back, the arrival's import or a splice resume rests it; a grain switch does not
(`grainBusy` is not in `phaseBusy`, :2132; on her grain pick :2289-2293 only the two grain
buttons rest). **Every «… — enviar agora» the notice draws, on the plan and on the grain
choice, rests while a part take of the session is in the air or being kept, or a join, the
home's swap or a bring-back runs**: it is dimmed, reads as disabled to VoiceOver and takes no
tap. The notifier's own `enviarACena` refuses the phase — a join, the home's swap, a
bring-back (`phaseBusy`) — as the plan's gestures do under `planBusy`; a take going up is
drawn only, because the home's Scene row keeps its «falhou — toque para tentar de novo» tap
under another send and reads «enviando…» at once (0131), and that row shares the gesture.
A grain switch leaves it as it is. The arrival's import and the splice
have no counterpart here (0121). The refusal while a take records (ENG-2058's `ensaio ==
recording` guard in the notifier) is not this amendment's: hers keeps the send enabled then.
