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
flutter run --release -d <iphone-id> --dart-define=DEV_ATALHOS=true   # stands in for the device link
flutter analyze
flutter test
flutter build appbundle --release                # reads android/key.properties
dart run tool/check_doctrine.dart                # the doctrine guard, on demand
```

Run `git config core.hooksPath tool/git-hooks` once to get the doctrine guard on every commit.

## What CI enforces beyond the suite

- No test is skipped.
- The room stays wordless: no `Text(` widget in the room's presentation layer, the claim
  code screen being the one named exception.
- Nothing forbidden returns to `lib/`: `tool/check_doctrine.dart` mirrors the backend's
  doctrine guard (`tripod-backend`, `scripts/check_doctrine.py`) against Marcia's six rules,
  spelled in Dart, against a typed allowlist in `tool/doctrine_allowlist.dart`.
- The source is what the pinned formatter produces: `dart format --output=none
  --set-exit-if-changed lib test tool` must exit 0; a branch that is not formatted fails
  the check.

## Secrets

Copy `.env.example` to `.env` and fill `BACKEND_URL` and `INTERNALIZATION_ROOM_KEY`. The
device credential is never in that file: it lives in the iOS Keychain, and ADR 0017 says why.

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
