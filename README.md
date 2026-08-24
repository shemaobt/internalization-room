# Sala de Internalização

Voice-first Flutter app for the internalization room of the Shemá oral Bible translation flow. The visual language comes from the Claude Design prototype `Sala de Internalização.dc.html` (Shemá design system); the interaction model follows the client-validated *Tripod Internalization · Interaction Flows* document.

> **Neither reference artifact is in this workspace.** Until they are, the rules below cannot be checked against their source, and where the code diverges nobody can tell from here whether it was a deliberate cut. The rules were written as the target, not as a description of the code: the notes marking drift say which is which today.

The room walks a team through a passage in five stations, with **zero readable words on team screens** — one terracotta circle, a bead necklace (colar) as the only progress indicator, and everything else spoken:

1. **Convite** — the breathing circle welcomes the team and gives the book panorama; a wooden bead opens the passage.
2. **Conversa** — tap the circle to speak, tap again when finished. Each engaged meaning-map element warms a bead on the colar (oat → half → wood; one bead is a ring: the significant absence — the backend says how many beads there are and which one it is). Tapping the hand records a question that becomes a blue knot on the cord.
3. **Ensaio** — tap to record the whole passage; listen, re-record, or keep. Kept takes become ghost beads on the thread.
4. **Retrotradução** — the team's own recording plays; a tap pauses it and captures a piece told back in Portuguese, and a tap sets the clip running again from where it stopped. When the clip ends, *terminei* runs the check, which lands on findings or on *conferida*. A finding offers telling that part again and re-recording it — except for the kinds that are a property of the mother-tongue recording (an addition, a meaning change, a preservation violation), where telling it again cannot remove anything from the recording and only re-recording is offered.
5. **Fecho** — the cord closes into a circle and the beads glow slowly.

### Interaction rules taken from the flows document

- **Two taps, not a hold** — the first tap is the addressing gesture, the second says "I'm finished". Most speech in the room is deliberately not for the machine.
- **Latency is honesty** — a 0 ms acknowledgement ("Hmm — deixa eu pensar…", rotated) turns the wait into conversation; thinking is calm clay, never a spinner. The line is played from the bundle (`F0`–`F3`, rotated) the moment the recorder stops, before any request leaves the tablet.
- **Beads settle late** — coverage is classified off the voice path, so beads move ~30 s after the turn, during the team's reflection pause. `surfaced` (the Guide said it) is a half bead; only `engaged` (the team worked with it) fills.
- **Team-talk mode** — when a turn sends the team to rehearse among themselves, the circle becomes a dashed blue ring with the team glyph and the app simply waits. Nothing is recorded. *Drift: the code draws a **solid** blue disc; `dashed_ring.dart` exists but is never used.*
- **Failure never looks like failure** — repeated voice failures land on `needsPerson`, a calm still circle; a long press (a person) resolves it, and in the conversa, when the halt took the session with it, the room opens another before inviting the team back — in the ensaio and the retro a fresh session would strand what the team has already recorded, so the halt resolves the way it always did and the way back to a live session is the wheel. A capture shorter than `shortestSpeechProvider` never leaves the tablet: the room answers "podem repetir?" from the bundle (`D0`–`D2`, rotated). The server keeps the same lines for a capture that reaches it and turns out to be silent.
- **The hand is a mailbox, not a doorbell** — a tap opens note mode (the circle sends, the hand cancels: a half question never sends). When a facilitator reply is waiting, a quiet sand/olive dot appears on the hand and a tap plays the oldest unheard reply. Never auto-played, never announced.
- **Kept rehearsals are the team's own audio** — nothing is generated. They come back as ghost play (listen → pause → record) before recording. The way back to another passage is the wheel, reached by the leave button.

Design doctrine applied: progress lives only in the colar; no numbers, percentages, or lists are ever shown.

## Architecture

Thin-client Flutter app following [AGENTS.md](AGENTS.md): Riverpod state, feature-based clean architecture, self-documenting code.

- `lib/features/sala/domain` — coverage counters, the fixed-line asset names, kept takes, hand replies, back-translation findings, session state machine types. The meaning map and the facilitator's script live on the backend; the app only renders what it is told.
- `lib/features/sala/data` — `SalaSessionNotifier` (the session state machine), recording (mic capture via `record`), playback (`just_audio`), and `FacilitatorVoiceService`, which fetches the room's spoken lines from the backend, caches them under `voz/` (60 clips, oldest dropped) and plays the pre-approved fixed lines from `assets/audio/fixed/`.
- `lib/features/sala/presentation` — one screen, one view per station, the colar overlay, and the facilitator circle with its voice states (invite / listening / thinking / speaking / done / needsPerson, plus team-talk mode).

### Backend seams

The room is wired to `tripod-backend` at `/api/internalization-room`, addressed by `BACKEND_URL` and authenticated with `INTERNALIZATION_ROOM_KEY` (see `.env.example`). Every provider below is overridden in tests — see `test/fakes.dart`.

| Provider | What it owns |
| --- | --- |
| `roomRepositoryProvider` | sessions, turns, back-translation chunks and verdict, takes, voice clips |
| `handInboxRepositoryProvider` | the facilitator inbox: raise a question, fetch replies, mark heard |
| `takeUploadQueueProvider` | the durable outbox for kept takes and retro chunks, with retry and give-up |
| `connectivityServiceProvider` | whether the room is reachable, before the team ever taps |

Timing and escalation policy also live in providers so tests can shrink them: `beadSettleDelayProvider`, `beckonIntervalProvider`, `busyStateCeilingProvider`, `playbackCeilingProvider`, `clipGraceProvider`, `roomRetryBackoffProvider`, `fimLingerProvider`.

Recordings (conversa utterances, questions, ensaio takes, retro segments) are captured under the app documents directory in `recordings/`. Takes and chunks waiting to reach the room are copied to `guardadas/` with a `fila.json` manifest that survives the app closing; each row names the file, not its absolute path, so the queue still finds the audio after a restore or a reinstall changes the container prefix. That copy is deliberately kept after upload — the rehearsal and the back-translation are the team's product.

### Known gaps

- The room decides locally that it `needsPerson` (unplayable lines, repeated room failures, a busy state that overran) but has no way to tell the backend — `needs_person` has no producer server-side either.
- The back-translation retell loop has no cap, and `pass_number` is client-invented: `POST .../back-translation/chunks` carries no pass or chunk index, so the server cannot tell one pass from another.
- `dashed_ring.dart` and `BtFindingKind.exitsByReRecording` are written but unused — they encode design and domain rules the running code does not apply.

## Run

```sh
flutter pub get
flutter run                      # pick a device
flutter run -d <iphone-id>       # on an iPhone (signing team already configured)
```

iOS signing uses the Shemá team (`55ZKR3YQMJ`, bundle id `com.shema.internalizationRoom`). First deploy to a personal device may require trusting the developer profile on the phone (Settings → General → VPN & Device Management).

Android release signing reads `android/key.properties`, which is gitignored and absent from a
fresh checkout: copy `android/key.properties.example` and fill in the four values. Without it
`flutter build appbundle --release` stops with a message naming the file rather than producing
an unsigned artifact, and `flutter run --release` stops with it too — debug and profile builds
are unaffected. `storeFile` resolves against `android/app/` when relative, so an absolute path
is the one that does what it looks like. The keystore and its passwords belong in the team's
secret store: an install can only ever be replaced by a build carrying the same key.

## Test and lint

```sh
flutter analyze
flutter test
```
