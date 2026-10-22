---
status: accepted
date: 2026-10-22
---

# The stores are fed from main, and the upload key's master copy lives in Secret Manager

Henok settled it on 22 October (ENG-1750).

## Context

Every store release was built, signed and uploaded by hand from one laptop, which also held
the only copy of the Android upload keystore, its passwords, the Apple distribution
certificate and the store credentials. An install can only ever be replaced by a build
carrying the same key, so losing that laptop would end the room's updates for good. The
oral-collector already publishes from GitHub Actions.

## Decision

- **A push to `main` that raises the version in `pubspec.yaml` is a release.** Actions
  builds and signs both platforms and sends the Android bundle to Google Play production at
  100% and the iOS build to App Store Connect, submitted for review with the release note
  kept in the repository. The release after Apple's approval stays in Henok's hand. A push
  that does not raise the version builds nothing and ends green.
- **The version has one source**, `pubspec.yaml`, the same number on both platforms, raised
  by hand in the PR that carries the release note.
- **The master copy of every release secret lives in Secret Manager**, project
  `shemaobt-secrets`; the repository's GitHub secrets are copies the workflows read, named
  as the oral-collector's. No laptop is a store of secrets.
- **The room signs as the oral-collector does**: certificate from a base64 secret, an App
  Store profile of a fixed name fetched with the App Store Connect API key, manual signing
  set on the project at build time.

## Considered Options

**Build on every push and let the store refuse a repeated version**, as the oral-collector.
Rejected: the room merges several times a day; each would spend a full macOS build and end red.

**Internal tracks and TestFlight first, production by hand.** Rejected: the tablets are few
and ours, and the point is that a merge reaches them without a laptop.

**Phased release and staged rollout**, as the milestone first said. Rejected by Henok on
22 October for the same reason.

**fastlane match.** Rejected: one more store of secrets for one app.

## Consequences

A merge that raises the version goes to the field once the stores accept it; the freeze week
decides by not raising the version. The first automated release waits on a PR of its own.
`xcrun altool --upload-app` is deprecated, so the upload goes through fastlane deliver, which
also submits.
