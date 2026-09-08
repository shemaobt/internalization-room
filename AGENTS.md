# Internalization Room

Voice-first Flutter tablet app for the Internalization Room of the Shemá oral Bible
translation flow. Team screens carry no readable words; the necklace is the only progress indicator.

## Toolchain and commands

`pubspec.yaml` asks for `sdk: ^3.12.0`, so the toolchain must ship Dart 3.12. Flutter
3.41.x ships Dart 3.11.3 and cannot resolve the dependencies there. CI pins Flutter 3.44.9.

```sh
flutter pub get
flutter run                                                          # pick a device
flutter run -d <iphone-id>
flutter run --release -d <iphone-id> --dart-define=DEV_ATALHOS=true   # stands in for the device link
flutter analyze
flutter test
flutter build appbundle --release                # reads android/key.properties
```

## What CI enforces beyond the suite

- No test is skipped.
- The room stays wordless: no `Text(` widget in the room's presentation layer, the claim
  code screen being the one named exception.

## Secrets

Copy `.env.example` to `.env` and fill `BACKEND_URL` and `INTERNALIZATION_ROOM_KEY`. The
tablet's own device credential is never in that file: it lives in the iOS Keychain, and
`docs/adr/0017-the-credential-lives-in-the-keychain.md` says why.

## Where the rest is

State is Riverpod. The Shemá design system and the client-validated interaction flows are
vendored under `docs/spec/`.

- `CONTEXT.md` — the glossary. Use its terms in code, tests and commits.
- `docs/adr/` — one hard-to-reverse decision per file.
- `docs/setup.md`, `docs/backend-seams.md`, `docs/recordings-and-queue.md`.
