# Sala de Internalização

Voice-first Flutter app for the internalization room of the Shemá oral Bible translation flow. Implemented from the Claude Design prototype `Sala de Internalização.dc.html` (Shemá design system).

The room walks a team through Ruth 1 in six stations, with **zero readable words on team screens** — one terracotta circle, a bead necklace (colar) as the only progress indicator, and everything else spoken:

1. **Convite** — the breathing circle welcomes the team and gives the book panorama; a wooden bead opens the passage.
2. **Conversa** — hold the circle to speak; the facilitator voice answers. Each engaged meaning-map element warms a bead on the colar (oat → half → wood; the 12th bead is a ring: the significant absence). Holding the hand button records a question that becomes a blue knot on the cord.
3. **Ensaio** — hold to record the whole passage; listen, re-record, or keep. Kept takes become ghost beads on the thread.
4. **Autocheque** — segment by segment, confirm or listen again. No pass/fail — it is conversation.
5. **Retrotradução** — two passes over five segments, telling each one in Portuguese for the consultant; the first pass half-fills each bead, the second completes it.
6. **Fecho** — the cord closes into a circle and the beads glow slowly.

Design doctrine applied: thinking is clay that glows, never a spinner; the raised hand becomes a blue knot on the cord; progress lives only in the colar; no numbers or percentages.

## Architecture

Thin-client Flutter app following [AGENTS.md](AGENTS.md): Riverpod state, feature-based clean architecture, self-documenting code.

- `lib/features/sala/domain` — meaning map (Ruth 1), facilitator script, session state machine types.
- `lib/features/sala/data` — `SalaSessionNotifier` (the session state machine), recording (mic capture via `record`), playback (`just_audio`), and `FacilitatorVoiceService` (currently on-device TTS in pt-BR; designed to be replaced by the backend STT → LLM → TTS pipeline).
- `lib/features/sala/presentation` — one screen, one view per station, the colar overlay, and the facilitator circle with its four voice states (invite / listening / thinking / speaking).

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
