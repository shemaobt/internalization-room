---
status: accepted, amended by 0055, 0057, 0058, 0059
date: 2026-10-02
supersedes: 0046 (in part: the Station region, the Halt lifted by the Desk, the Reach and the automatic resend)
amends: 0048, 0050
---

# Each Station is a state of its own, and effects and failures leave the notifier

## Context

ADR 0046 modelled the room's lifecycle as one machine of four regions. Halt, Channel and
Reach moved into `reduce` (ENG-1161 to ENG-1175), but the Station and its Step never did. On
main at 64de13a the notifier is 5,885 lines (5,197 when 0046 was written). It writes the state
directly 128 times and checks `_epoch` 109 times. Room failures bypass the machine through
`_handleRoomFailure`. The three places that break most, finishing the back-translation,
opening the Conversation and replaying after a halt, branch on Station × Step × what is
sounding.

On 2026-10-01 the team adopted the 6 November plan. The room follows Marcia's frozen app
(18fa7c4), which adds Stations (the passage Menu, the session Canvas, the Panorama, the
Ensaio Final, the Checagem externa) and changes how the room fails. On 2026-10-02 Henok
settled three production questions for that plan:

- **ENG-1354:** when the room needs a person, the team clears the sign with a tap. The Desk
  is told only as information.
- **ENG-1369:** a turn that fails is checked by one look at the session. Nothing is resent in
  the background.
- **ENG-1263:** a session never ends on its own. The Desk alone may label it "concluída" or
  "parada há X h".

## Decision

The room's core is rebuilt on three patterns, so that each feature of the plan lands in one
place.

1. **State, one per Station.** The Station is a sealed type, and each Station lives in its
   own file: Menu, Canvas, Panorama, Ensaio Final, Checagem externa. Each Station answers the
   events it understands with a transition: the next Station or Step, plus the effects to
   run. A Station ignores what it does not understand. A Step is substate of its Station and
   ends when the Station is left. The cross-cutting regions (the person sign, the Channel,
   the Outbox's facts) stay in the machine and run before the Station. For example, a person
   sign silences the Channel whatever the Station.
2. **Command, one effect runner.** The machine returns effects as data. A single runner
   outside the notifier executes them through ports: Room, Player, Recorder, Store, Clock. An
   effect that answers carries the **token** of the turn or Station that asked for it. The
   machine drops an event whose token is not the current one. This replaces every `_epoch`
   check.
3. **Strategy, one failure policy.** Every room result (answered, network failed, refused
   with a code, session gone, timed out) goes through one policy that turns it into an event:
   the one look, the person sign, session gone, or the Station's own answer. Nothing decides a
   failure inside a Station or the notifier.

The notifier becomes an adapter. It turns gestures into events, keeps the state for the UI
and hands effects to the runner. It holds no lifecycle field of its own.

## What changes from 0046

- **Halt** becomes the **person sign**: none, or shown. Only the team's tap clears it
  (ENG-1354). The blocking halt that only the Desk lifts, the warning that stops nothing, and
  the long press are gone from the tablet. The Desk's needs-person queue remains, as
  information.
- **Reach** and the **Pending request** are gone. A failed turn gets one look (ENG-1369), and
  the Outbox's automatic drain gives way to sending at the moments the plan names (ENG-1410).
  ADR 0050 is superseded for the tablet.
- **The Watch** (ADR 0048) beats only where a Station needs the server's reading. No halt
  depends on it.
- **The Stations** are the plan's. The Invitation, the Wheel's offering and the Closing do
  not return (ENG-1282, ENG-1263).

The terms Halt, Warning, Warning mark, Call for a person, Reach, Pending request and Watch in
CONTEXT.md change when the slice that removes them lands, not before.

## Considered options

- **Finish 0046 as written: one reducer with the Station as a fifth region.** Rejected:
  every Station would share one switch, and each plan feature would touch the same file of
  thousands of lines.
- **One controller per feature, with a mediator.** Rejected: what crosses features (a person
  sign during the back-translation, resuming) would move into the mediator, which would
  become the next notifier.

## Consequences

- The migration runs in slices, each at most 5 points:
  1. ports, the effect runner and tokens;
  2. the failure policy (it is ENG-1369 and ENG-1354);
  3. the Menu and the Canvas (they are ENG-1282 and ENG-1281);
  4. the turn's Steps;
  5. the Ensaio Final;
  6. the back-translation and the check.
- A plan ticket that touches the lifecycle lands as a Station transition. A test that drives
  the notifier for a rule that now lives in a Station moves to the machine and the
  generator.
- ENG-1176 and ENG-1177 are replaced by these slices.

## Amendment · 2026-10-02

Henok settled the interface of slice 1 the same day. There are **four ports: Room, Sound,
Recorder, Store**. Sound carries voice lines and parts together, so one sound plays at a time.
Network health and the person-call inbox belong to Room. The clock stays a seam, not a port.
The token is the machine's **`generation`**. Slice 1 moves it exactly where `_epoch` moves
today, so that no behaviour changes, and it moves "on every Station change" only once the
Station is in the machine. Slice 1 is split in two: the runner and ports (ENG-1442), then the
generation (ENG-1443). The ports are named `RoomPort`, `SoundPort`, `RecorderPort`
and `StorePort` in code, because `Sound` is already a Channel state. Until the Station
moves into the machine, an effect that still needs notifier state runs through one temporary
`EffectHost` the notifier implements. ENG-1444 empties it into the ports once the generation
has replaced `_epoch`.

## Amendment · 2026-10-06

Slice 3 is split. The Station does not exist in the machine yet: the notifier writes `SalaStage`
in about fourteen places, and the failure policy reads it from its context. Slice 3a
(ENG-1446) puts the `Station` sealed type in the machine, with the Menu and the Canvas as states
of their own and today's other stages wrapped unchanged, turns every `stage:` write of the
notifier into an event, moves `generation` on every Station change, and changes no behaviour.
Slice 3b (ENG-1282, ENG-1281) then lands the plan's Menu and Canvas as transitions. The tablet
halves of the server tickets that touch the Canvas (the interruption gesture, ENG-1447; the
empty telling, ENG-1450) follow 3b on the same rail.
