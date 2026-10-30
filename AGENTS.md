# Internalization Room

Voice-first Flutter tablet app for the Internalization Room of the Shemá oral Bible
translation flow. Team screens carry no readable words; the necklace is the conversation's progress indicator.

Documentation is written in English.

## Toolchain and commands

Use Flutter 3.44.9: it is what CI pins, and the only version verified here. `pubspec.yaml`
asks for `sdk: ^3.12.0`, so a toolchain shipping Dart 3.11.3 — Flutter 3.41.x — cannot
resolve the dependencies at all. The iOS deployment target is 15.0: Xcode 27 refuses the
13.0 the Flutter template ships, and the `Podfile` forces 15.0 on the `Flutter` pod, whose
podspec still says 13.0.

```sh
flutter pub get
flutter run                                                          # pick a device
flutter run -d <iphone-id>
flutter run --release -d <iphone-id> --dart-define=DEV_ATALHOS=true   # the skip bar in a release build
flutter analyze
flutter test                                     # 3 workers by default (dart_test.yaml); --concurrency overrides, CI uses 2
flutter build appbundle --release                # reads android/key.properties
flutter build … --dart-define=BUILD_NUMBER=<the +N of pubspec.yaml>   # how a store build learns its own number; without it a build is a laptop build and never shows the update screen
dart run tool/check_doctrine.dart                # the doctrine guard, on demand
```

Run `git config core.hooksPath tool/git-hooks` once to get the doctrine guard on every commit.

## What CI enforces beyond the suite

- No test is skipped.
- The room stays wordless: no `Text(` widget in the room's presentation layer, enforced by
  `test/the_room_stays_wordless_test.dart` against a named exception list — the claim code
  screen, read by the facilitator and not the team, her moment label, the claquete,
  the «PT»/«EN» codes on the Choice, the scene question, her passage menu on the
  Choice, her check screen with its numbered frase list, the scene rehearsal's translate step,
  the numerals of her kept-retelling buttons, her recording home, the Ensaio Final plan,
  her Rehearsal sheet, her Saved screen, her Checagem externa screen, her grain choice, and the update screen (ADR 0014),
  and her «Ouvir tudo» screen with its title and «fim da gravação» (ADR 0014), and the red microphone's take state with her «parar» (ADR 0131), and the «pensando…» under a thinking circle (ENG-1925).
- Nothing forbidden returns to `lib/`: `tool/check_doctrine.dart` mirrors the backend's
  doctrine guard (`tripod-backend`, `scripts/check_doctrine.py`) against Marcia's six rules,
  spelled in Dart, against a typed allowlist in `tool/doctrine_allowlist.dart`.
- Time comes from `package:clock`: no `DateTime.now` and no bare `Stopwatch()` under `lib/`,
  enforced by `test/the_room_reads_the_clock_through_one_seam_test.dart`.
- No shared key returns: nothing under `lib/`, `test/`, `tool/` or in `.env.example` names
  it, enforced by `test/no_source_names_the_room_key_test.dart`. The device credential is
  the only thing a tablet sends.
- The source is what the pinned formatter produces: `dart format --output=none
  --set-exit-if-changed lib test tool` must exit 0; a branch that is not formatted fails
  the check.

## The room's core

The session lifecycle is one pure machine: `reduce(Machine, MachineEvent)` returns the next
`Machine` and the effects to run (ADR 0046). Under ADR 0053 its shape is three patterns:

- **State.** Each Station (Menu, Canvas, Panorama, Ensaio Final, Checagem externa) is its own
  type in its own file and answers the events it understands with a transition. Its Steps are
  substate. The cross-cutting regions (the person sign, the Channel, the Outbox's facts) run
  before it.
- **Command.** Effects are data. One `EffectRunner` executes them through four ports: `RoomPort`,
  `SoundPort` (voice and parts, one at a time), `RecorderPort` and `StorePort`. Every answer returns as an
  event stamped with the machine's `generation`, and `reduce` drops a stale one.
- **Strategy.** Every room result goes through one `FailurePolicy` that turns it into an event,
  and so does every failure of the tablet's own that may call a person: the reply's sound
  failing, the microphone failing to start, the tablet that cannot record.
  The room client gives each door one of four results: answered, network failed,
  refused(code), session gone (ADR 0047).

`SalaSessionNotifier` is an adapter. It turns gestures into events, keeps the state for the
UI and hands effects to the runner. A change to the lifecycle (opening a passage, a turn, the
person sign, resuming, an upload, a Station) lands as an event and a transition, with its test
at the machine level and in the generator (`test/machine_generator.dart`). It never lands as a
new field or branch in the notifier.
One exception, by the ticket (ENG-1898): the entry tapped on the Choice is a state field, kept
until its session lands or the open ends, and `stage` reads it so the Choice stays on screen
while the session is asked, as her picker does.

Every field of `SalaSessionNotifier` is declared `late`, never `late final`, with no
initializer, and is assigned in `_aNewLife()` or `build()`, so a relink begins a whole new
Life; only `_highestGeneration`, `_firstGeneration`, `_gestures`, `_lines` and `_random`
cross lives (enforced by `test/every_field_of_the_room_is_born_with_its_life_test.dart`).
A continuation captures `_thisLife` before its await and checks `_endedSince(life)` after it;
`_gone` alone guards only synchronous code, because a new Life sets it back to false.

Lifecycle code still in the notifier moves out to the machine through slices, and new lifecycle
work is built on the machine. The one written exception: the Retro screen keeps its notifier fields,
`btFindings`, `btConferindo`, `btRecusa`, `btVeredito`, `armedTap`, `btAviso`, `btRecomecada`,
`btPausaSoNaUltima`, `btRegravacao`, `btFraseQueAguarda`, `btFraseGuardada`, `btFraseDevida`, `btRascunhoAprovado`, `btChecked`, `btSoOuvir`, `btOuvidaInteira`, `btRestoPorOuvir`, `btPartesOuvidasAqui`, `btAprovando`, `btAprovadoAgora`, `btNaoOuvidas`, `btParteQueTocou` and `ensaioSalvo` included, its report
that the verdict was heard, and the Listening ledger's reports with `_oQueFaltaOuvir`,
`_aEscutaRecomecaEm`, `_umaParteFoiRegravada`, `_aTraducaoJaFoiDeixada` and the armed tap's `_armHandedOver`, until after the 2 November tablet freeze
(ADR 0046).

## The weakest device

The room runs on everything from an iPhone 16 Pro Max down to old Android tablets and old
iPhones, and no change may weigh on a weak device. Judge motion and memory against the
weakest device, never against the newest: what is smooth on a new phone has not shown it is
light enough. `docs/setup.md` says what the repo does and does not yet pin down about it.

## Secrets

Copy `.env.example` to `.env` and fill `BACKEND_URL`. The app ships no shared key: the
device credential is the only thing a tablet sends, and it is never in that file. It lives
in the iOS Keychain, and ADR 0017 says why.

## Where the rest is

State is Riverpod. The Shemá design system and the client-validated interaction flows are
vendored under `docs/spec/`. `docs/spec/prototype/` is historical: its motion timings
predate the live tempos, which come from Marcia's canvas (`Tripod-Internalization`,
`app/globals.css`).

- `docs/doctrine/` — Marcia's `DOCTRINE.md`, vendored at the pin in `DOCTRINE_PIN` and binding
  on every change here: read it before touching the canvas or the turn loop. `ACCEPTANCE_BAR`
  says which line of §4 is held by which test, and a change to the pin needs a ruling in
  `docs/doctrine/rulings/`.
- `CONTEXT.md` — the glossary. Use its terms in code, tests and commits.
- `docs/adr/` — one hard-to-reverse decision per file.
- `docs/setup.md`, `docs/backend-seams.md`, `docs/recordings-and-queue.md`.
