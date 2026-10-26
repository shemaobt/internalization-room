# Setup

What a fresh checkout needs before the room will run.

## Environment

Copy `.env.example` to `.env` and fill it in. `BACKEND_URL` addresses the room's backend —
the simulator reaches it at `http://localhost:8000`, a physical iPhone needs the Mac's LAN
address. Nothing else in it reaches the room: the tablet is known by the device credential
it collects once a facilitator links it from the Desk. The file is gitignored and is
bundled as an asset, so a release build carries whatever sat in the tree of whoever
compiled it.

## Choosing a device

`flutter run` with no device flag offers a picker. `flutter run -d <iphone-id>` goes
straight to one; `flutter devices` lists the ids.

## The weakest device

The room runs on everything from an iPhone 16 Pro Max down to old Android tablets and old
iPhones (João, 23 September 2026), and no change may weigh on a weak device. Motion and
memory are judged against the weakest device, never against the newest.

No reference device is named yet. Naming one — model, RAM, Android version — takes the
devices the teams actually carry, and nobody has listed them, so `minSdk` stays Flutter's
default (`flutter.minSdkVersion`, `android/app/build.gradle.kts`) until they do. The iOS
floor is 15.0, as `AGENTS.md` says.

The repo states no frame-time budget for motion and no budget for the memory clips hold,
and none is invented here. The only figures it carries are redraw rates: the ambient clock
draws the circle at 30 Hz, or at 60 Hz while a ripple runs
(`lib/features/sala/presentation/widgets/motion.dart`). That is how often the room draws,
not what a weak device must sustain. A change that moves motion or holds clips in memory
states its own figure in its ticket and measures it on the weakest device available.

## The dev skip bar

Every build, a debug one included, stops at the claim code until a facilitator spends it
from the Desk: the room opens to nothing but a device credential, and a build that skipped
the link would have none. `DEV_PULAR_FASES=1` in `.env` opens the skip bar and its
shortcuts, and only in a debug build — a release would otherwise ship whatever `.env` was
compiled in. A release build on a developer's own device takes the latch on the command
line instead, where nothing but that one build can pick it up:

```sh
flutter run --release -d <iphone-id> --dart-define=DEV_ATALHOS=true
```

`DEV_ATALHOS` brings the skip bar to that release build when `DEV_PULAR_FASES=1` is also
set; on its own it does nothing.

## iOS signing

The Shemá team id is `55ZKR3YQMJ` and the bundle id is `com.shema.internalizationRoom`. A
first deploy to a personal device may need the developer profile trusted on the phone,
under Settings → General → VPN & Device Management.

## Android release signing

Release signing reads `android/key.properties`, which is gitignored and absent from a
fresh checkout: copy `android/key.properties.example` and fill in the four values. Without
it, `flutter build appbundle --release` stops with a message naming the file rather than
producing an unsigned artifact, and `flutter run --release` stops too; debug and profile
builds are unaffected. `storeFile` resolves against the Android app directory when
relative, so an absolute path is the one that behaves as it looks. The keystore and its
passwords belong in the team's secret store: an install can only ever be replaced by a
build carrying the same key.
