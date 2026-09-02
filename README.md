# Sala de Internalização

Voice-first Flutter app for the internalization room of the Shemá oral Bible translation flow. The visual language comes from the Claude Design prototype `Sala de Internalização.dc.html` (Shemá design system); the interaction model follows the client-validated *Tripod Internalization · Interaction Flows* document.

> **Neither reference artifact is in this workspace.** Until they are, the rules below cannot be checked against their source, and where the code diverges nobody can tell from here whether it was a deliberate cut. The rules were written as the target, not as a description of the code: the notes marking drift say which is which today.

The room walks a team through a passage in five stations, with **zero readable words on team screens** — one terracotta circle, a bead necklace (colar) as the only progress indicator, and everything else spoken:

1. **Convite** — the breathing circle welcomes the team and gives the book panorama; a wooden bead opens the passage.
2. **Conversa** — tap the circle to speak, tap again when finished. Each engaged meaning-map element warms a bead on the colar (oat → half → wood; one bead is a ring: the significant absence — the backend says how many beads there are and which one it is). Tapping the hand records a question that becomes a blue knot on the cord.
3. **Ensaio** — tap to record the whole passage; listen, re-record, or keep. Kept takes become ghost beads on the thread.
4. **Retrotradução** — the team's own recording plays; a tap pauses it and captures a piece told back in Portuguese, and a tap sets the clip running again from where it stopped. When the clip ends, *terminei* runs the check, which lands on findings or on *conferida*. A finding that names a stretch sends the team to the grid described below, where telling it again and re-recording are both always on offer. A finding that names none — the analyst could not attribute it, or there was too little telling-back to judge — offers telling the whole recording again, unless the kind is an addition, a meaning change or a preservation violation; that short list is the room's own rule and not a classification the server makes, since the analyst reads the telling-back against the meaning map and never hears the mother-tongue recording, so it does not say whether a difference came from the telling or from the recording under it. The other exit in that fallback is not a restart: it sends the team back to the rehearsal with every take, stretch and bead kept, to record what the passage still lacks (see *the end of the story*, below). A true restart — dropping the recorded clip, emptying the rehearsal, and waiting for the session's answer while the exits leave the screen and the circle shows the room is busy — still exists as `reRecordClip`, but nothing on this screen calls it anymore.
5. **Fecho** — the cord closes into a circle and the beads glow slowly.

### Interaction rules taken from the flows document

- **Two taps, not a hold** — the first tap is the addressing gesture, the second says "I'm finished". Most speech in the room is deliberately not for the machine.
- **Latency is honesty** — a 0 ms acknowledgement ("Hmm — deixa eu pensar…", rotated) turns the wait into conversation; thinking is calm clay, never a spinner. The line is played from the bundle (`F0`–`F3`, rotated) the moment the recorder stops, before any request leaves the tablet.
- **Beads settle late** — coverage is classified off the voice path, so beads move ~30 s after the turn, during the team's reflection pause. `surfaced` (the Guide said it) is a half bead; only `engaged` (the team worked with it) fills.
- **Team-talk mode** — when a turn sends the team to rehearse among themselves, the circle becomes a dashed blue ring with the team glyph and the app simply waits. Nothing is recorded. *Drift: the code draws a **solid** blue disc; `dashed_ring.dart` exists but is never used.*
- **Failure never looks like failure** — repeated voice failures land on `needsPerson`, a calm still circle; the room says the line to the team at once and tells the server the session needs someone, asking again down `roomRetryBackoffProvider` for as long as it is stopped and the server has not confirmed it has the call; a long press (a person) resolves it, which is also what stops the asking, and in the conversa, when the halt took the session with it, the room opens another before inviting the team back — in the ensaio and the retro a fresh session would strand what the team has already recorded, so the halt resolves the way it always did and the way back to a live session is the wheel. A capture shorter than `shortestSpeechProvider` never leaves the tablet: the room answers "podem repetir?" from the bundle (`D0`–`D2`, rotated). The server keeps the same lines for a capture that reaches it and turns out to be silent.
- **The hand is a mailbox, not a doorbell** — a tap opens note mode (the circle sends, the hand cancels: a half question never sends). When a facilitator reply is waiting, a quiet sand/olive dot appears on the hand and a tap plays the oldest unheard reply. Never auto-played, never announced.
- **Kept rehearsals are the team's own audio** — nothing is generated. They come back as ghost play (listen → pause → record) before recording. The way back to another passage is the wheel, reached by the leave button.
- **The long way round is two stations, never one** — when the error was born in the recording, the mother tongue of that stretch is recorded again and that stretch is told again over it, in that order, with the second station following on its own. Correcting only the recording is not a state this product has: the room refuses a new recording that arrives carrying the old explanation, and a stretch left with a new voice and no telling is one the first round's gate holds the whole passage for. The new recording becomes a rehearsal take of its own, sliced from nought to its own length — which is why it waited on the room being able to measure an audio without playing it.
- **The team says where the error lives** — when the analyst points at a stretch, the room asks instead of guessing. A grid of two voices: column is the voice — wood is the team's own tongue, blue is the telling in Portuguese — and row is the verb, listen on top and speak below. Hearing either one is free and settles nothing. The wood microphone means the error was born in the recording, so the mother tongue is re-recorded and that stretch is told again over it, always in that order; the blue one means only the telling slipped. Correcting the recording alone does not exist, and the server refuses it. The kind of finding used to decide this alone, and three of the eight kinds hid the retell outright — it now governs only the fallback, for a finding that names no stretch at all.
- **A drained band means "waiting to be mended", not "wrong"** — during the telling-back the cord draws each stretch as a band, and the one the analyst pointed at is drained and wears a halo. It fills again the moment the team takes the correction on — choosing which voice speaks again, or opening the microphone — and not when the recording is delivered: choosing, recording and uploading is the whole span the team is working, and the colar was reporting it as nothing done. The cost was weighed and accepted: while the recording runs the band does not tell "mended" apart from "mending", and the circle is what says a capture is in the air. If the capture fails — no file back from the recorder, an upload the room refused, a room that made nothing of what arrived, or the room giving up on a wait that ran past its ceiling — the band drains again, because filling it is a promise and a promise nobody kept has to be taken back. A verdict pointing at the same stretch a second time drains it too: filling is never final.
- **A stretch is a slice of one recording** — a told-back stretch names the rehearsal recording it explains and the two times inside **that file**, never a position on the concatenated passage. Times relative to a file that never changes never shift, which is what lets one stretch be corrected without moving every stretch after it. The listening ruler stays whole: what the room reports as heard, and the length it measures the clip against, are still the rehearsal end to end.
- **Reopening lands where they stopped** — a passage left part-way comes back at the stage the tablet wrote down, not at its start. When that stage is the retro, the stretches already told come back from the room, which carries the whole telling-back on every session route; the next stretch begins where the last one ended, so no piece of the rehearsal is told back twice and the session never ends with two of everything. Landing in the ensaio carries those same stretches too, so the way back opened by *the end of the story* (below) does not forget them either. Any entry into the retro — out of the ensaio, that same way back, the fallback's "tell it again", or a reopening that lands on the retro itself — plays from the first ground nobody has told back yet: parts whose every stretch is explained are stepped over (a half born of a division that nobody has told yet holds its part), all but the last (kept so the clip still reaches its end and `terminei` is still offered), and reported to the room as heard, with the full clip length; while the parts are being measured the room shows itself busy, so no cut lands on a clip about to start. That is deliberate: the team did hear those parts, in the round that told them, and the room's own check that the rehearsal was heard end to end cannot tell one round from the next — reporting only this round's listening would fail a passage whose every stretch is already told, and the only way through would be hearing the whole story again, exactly the duplication this path exists to avoid. A retro the room holds no stretch for is not a retro to resume, and the rehearsal is where the team lands.
- **The end of the story** — a finding that names no stretch at all is not always a wrong telling; it can be an ending the team never rehearsed, so the analyst has nothing to point at. The fallback's other exit answers that directly: back to the rehearsal, takes and stretches and colar untouched, to record the missing ground — and only that new ground gets told back on the next pass into the retro.
- **The bead walks while it plays** — in the retro, the reading head above the cord follows the sound continuously while a part is in the air, asked of the player ten times a second by the cord layer alone so the rest of the room does not repaint at that rate. Outside a part playing the head holds the room's own record of where the team stopped hearing — a pause, a part's end, picking one back up — none of them a guess the player is asked for.

Design doctrine applied: progress lives only in the colar; no numbers, percentages, or lists are ever shown.

## Architecture

Thin-client Flutter app following [AGENTS.md](AGENTS.md): Riverpod state, feature-based clean architecture, self-documenting code.

- `lib/features/sala/domain` — coverage counters, the fixed-line asset names, kept takes, hand replies, back-translation findings, session state machine types. The meaning map and the facilitator's script live on the backend; the app only renders what it is told.
- `lib/features/sala/data` — `SalaSessionNotifier` (the session state machine), recording (mic capture via `record`), playback (`just_audio`, which also answers how long a file is without playing it — on a second player of its own, so measuring never disturbs the clip in the air), and `FacilitatorVoiceService`, which fetches the room's spoken lines from the backend, caches them under `voz/` (60 clips, oldest dropped) and plays the pre-approved fixed lines from `assets/audio/<lingua>/fixed/`.
- `lib/features/sala/presentation` — one screen, one view per station, the colar overlay, and the facilitator circle with its voice states (invite / listening / thinking / speaking / done / needsPerson, plus team-talk mode).

### The room's language

The tablet decides. `roomLanguageProvider` reads the device's locale, narrows it to one of
`languages` and falls back to English for anything else; the choice is read once per run and
never again, because a team hearing the language change under them mid-passage is worse than
either language. Nothing in the room is localized in the usual sense — there is no
`localizationsDelegates` and there are no words on a team screen to localize. What the
language decides is which bundle the fixed lines are played from, and which language the app
asks the server for on `POST /sessions` and on the wheel, since everything the room says is
made there.

`codigo_view.dart` is the exception, and it is the same exception the CI gate already names:
a facilitator reads it once, at installation, so it reads in the language they set the device
to.

### Backend seams

The room is wired to `tripod-backend` at `/api/internalization-room`, addressed by `BACKEND_URL` and authenticated with `INTERNALIZATION_ROOM_KEY` (see `.env.example`). Every provider below is overridden in tests — see `test/fakes.dart`.

| Provider | What it owns |
| --- | --- |
| `roomRepositoryProvider` | sessions, turns, back-translation chunks and verdict, takes, voice clips |
| `handInboxRepositoryProvider` | the facilitator inbox: raise a question, fetch replies, mark heard |
| `takeUploadQueueProvider` | the durable outbox for kept takes and retro chunks, with retry and give-up |
| `connectivityServiceProvider` | whether the room is reachable, before the team ever taps |
| `workInProgressProvider` | the resume point per passage, in `guardadas/em_curso.json` |

Timing and escalation policy also live in providers so tests can shrink them: `beadSettleDelayProvider`, `beckonIntervalProvider`, `busyStateCeilingProvider`, `playbackCeilingProvider`, `clipGraceProvider`, `roomRetryBackoffProvider`, `fimLingerProvider`.

Recordings (conversa utterances, questions, ensaio takes, retro segments) are captured under the app documents directory in `recordings/`. Capture is opened in `pauseResume`: a call, an alarm or another app taking the microphone pauses the take and the recorder comes back on its own when the interruption ends, instead of staying paused for the rest of the rehearsal. The room reads the recorder's own state stream while it is doing that, so the eq bars and the record circle stop drawing a live capture for as long as the microphone is held elsewhere; the circle keeps saying the touch that ends the take, because the take is still open. Takes and chunks waiting to reach the room are copied to `guardadas/` with a `fila.json` manifest that survives the app closing; each row names the file, not its absolute path, so the queue still finds the audio after a restore or a reinstall changes the container prefix. That copy is deliberately kept after upload — the rehearsal and the back-translation are the team's product. The instant of a row's last try is written down as UTC rather than as a bare local time, and a stamp that sits ahead of the tablet's own clock is taken as already due: a time correction that moves the clock backwards, or a timezone change across a restart, would otherwise leave every queued recording paced against a wait that never comes due — silently, because a row that is merely never ready is neither exhausted, lost, nor stalled, and those are the only three the room says out loud. Writing a recording off is a guess about the disk and not a verdict: a row the queue could not find is looked at again on every flush, and the moment its audio is back at the path the queue reads, it is sent. That is what reaches the rows the old absolute-path resolution condemned while their files sat untouched beside them. Audio that is genuinely gone still falls out, so the queue still empties, and the team is still told about it. `guardadas/` also holds `em_curso.json`, the resume point: where each passage was left, so leaving one lands the team back there rather than at the start. It follows the queue's rule for the same reason — each take is stored by name and rejoined against the recordings folder at read time, so a restore, a reinstall or a new tablet does not leave the whole rehearsal pointing at a container prefix that is gone. Rows written by earlier builds carried the whole path and are still read. A resume point whose recordings are genuinely absent is cleared as it fails, because the wheel would otherwise go on offering a passage whose resume has already proved impossible and run the same failed resume on every opening. The session id lives nowhere else — `ir_sessions` carries no device, so nothing but this tablet can say which session belonged to which passage — which is why a resume point that cannot be written speaks. It is the same folder on the same disk as the queue, so it borrows the queue's stranded-recording line rather than adding a second one, and that line is guarded to play once per session so a failing disk does not become a chant. A `em_curso.json` that exists but cannot be parsed is never used as the base of a write: the rows of every other passage are in it. The write refuses and speaks instead of reporting a place it did not save.

### Known gaps

- The call for a person lives in memory: it is kept up by the running room, so a tablet that is closed and reopened while it is stopped forgets it was asking and only calls again the next time it halts.
- `dashed_ring.dart` is written but unused — it encodes a design rule the running code does not apply. `BtFindingKind.exitsByReRecording` now governs only the fallback for a finding that names no stretch; where a stretch is named, the team decides.

## Run

```sh
flutter pub get
flutter run                      # pick a device
flutter run -d <iphone-id>       # on an iPhone (signing team already configured)
```

An installation nobody has linked stops at the claim code and waits for a facilitator to
spend it from the Desk, and the dev skip bar is drawn only in a debug build. `.env`'s
`DEV_PULAR_FASES=1` opens both, and only in debug: a release carries whatever `.env` sat in
the tree of whoever compiled it, so the file alone would let an unclaimed tablet into a
team's room and put the phase buttons on a shipped screen. A release build on a developer's
own device takes the latch on the command line instead, where nothing but that one build
can pick it up:

```sh
flutter run --release -d <iphone-id> --dart-define=DEV_ATALHOS=true
```

`DEV_ATALHOS` stands in for the device link and, with `DEV_PULAR_FASES=1` in `.env`, brings
the skip bar with it.

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
