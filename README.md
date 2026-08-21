# Sala de Internalização

Voice-first Flutter app for the internalization room of the Shemá oral Bible translation flow. The visual language comes from the Claude Design prototype `Sala de Internalização.dc.html` (Shemá design system); the interaction model follows the client-validated *Tripod Internalization · Interaction Flows* document.

The room walks a team through Ruth 1 in five stations, with **zero readable words on team screens** — one terracotta circle, a bead necklace (colar) as the only progress indicator, and everything else spoken:

1. **Convite** — the breathing circle welcomes the team and gives the book panorama; a wooden bead opens the passage.
2. **Conversa** — tap the circle to speak, tap again when finished; an instant acknowledgement plays while the turn is drafted. Each engaged meaning-map element warms a bead on the colar (oat → half → wood; the 12th bead is a ring: the significant absence). Tapping the hand records a question that becomes a blue knot on the cord.
3. **Ensaio** — tap to record the whole passage; listen, re-record, or keep. Kept takes become ghost beads on the thread.
4. **Retrotradução** — the team's own recording plays; a tap pauses it and captures a piece told back in Portuguese, after which the clip resumes on its own. When the clip ends, *terminei* runs the check, which lands on findings or on *conferida*.
5. **Fecho** — the cord closes into a circle and the beads glow slowly.

### Interaction rules taken from the flows document

- **Two taps, not a hold** — the first tap is the addressing gesture, the second says "I'm finished". Most speech in the room is deliberately not for the machine.
- **Latency is honesty** — a 0 ms acknowledgement ("Hmm — deixa eu pensar…", rotated) turns the wait into conversation; thinking is calm clay, never a spinner.
- **Beads settle late** — coverage is classified off the voice path, so beads move ~30 s after the turn, during the team's reflection pause. `surfaced` (the Guide said it) is a half bead; only `engaged` (the team worked with it) fills.
- **Team-talk mode** — when a turn sends the team to rehearse among themselves, the circle becomes a dashed blue ring with the team glyph and the app simply waits. Nothing is recorded.
- **Failure never looks like failure** — repeated voice failures land on `needsPerson`, a calm still circle; a long press (a person) resolves it. Inaudible audio becomes "podem repetir?" with no model round-trip.
- **The hand is a mailbox, not a doorbell** — a tap opens note mode (the circle sends, the hand cancels: a half question never sends). When a facilitator reply is waiting, a quiet sand/olive dot appears on the hand and a tap plays the oldest unheard reply. Never auto-played, never announced.
- **Kept rehearsals are the team's own audio** — nothing is generated. They come back as replay chips during Conversa, and as ghost play (listen → pause → record) before recording.

Design doctrine applied: progress lives only in the colar; no numbers, percentages, or lists are ever shown.

## Architecture

Thin-client Flutter app following [AGENTS.md](AGENTS.md): Riverpod state, feature-based clean architecture, self-documenting code.

- `lib/features/sala/domain` — meaning map (Ruth 1), facilitator script, kept takes, hand replies, back-translation findings, session state machine types.
- `lib/features/sala/data` — `SalaSessionNotifier` (the session state machine), recording (mic capture via `record`), playback (`just_audio`), and `FacilitatorVoiceService` (currently on-device TTS in pt-BR).
- `lib/features/sala/presentation` — one screen, one view per station, the colar overlay, and the facilitator circle with its voice states (invite / listening / thinking / speaking / done / needsPerson, plus team-talk mode).

### Backend seams

These providers hold the app's side of contracts the backend does not expose yet. Each has a deliberately conservative default and is overridden in tests; wiring the backend means replacing only these.

| Provider | Belongs to the backend | Default today |
| --- | --- | --- |
| `handInboxRepositoryProvider` | facilitator inbox: replies + mark-heard | no replies |
| `speechCaptureGateProvider` | STT: did this capture contain speech | capture-duration heuristic |
| `keptRehearsalServiceProvider` | §5 classifier: retelling + Guide approval | never keeps — "under-save, never over-save" |
| `backTranslationServiceProvider` | BT Analyst + Speaker findings | no findings → *conferida* |

With the defaults in place the app reaches *conferida* directly; the findings screen and the replay chips are reachable by overriding the corresponding provider (see `test/fakes.dart`).

Recordings (conversa utterances, questions, ensaio takes, retro segments) are saved under the app documents directory in `recordings/`.

## Run

```sh
flutter pub get
flutter run                      # pick a device
flutter run -d <iphone-id>       # on an iPhone (signing team already configured)
```

iOS signing uses the Shemá team (`55ZKR3YQMJ`, bundle id `com.shema.internalizationRoom`). First deploy to a personal device may require trusting the developer profile on the phone (Settings → General → VPN & Device Management).

## Test and lint

```sh
flutter analyze
flutter test
```
