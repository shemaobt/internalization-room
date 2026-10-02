import 'channel.dart';

/// The room's reach to the server: network health.
abstract interface class RoomPort {
  Stream<void> get networkReturned;
}

/// Voice lines and parts together: one sound at a time.
abstract interface class SoundPort {
  Future<bool> playLine(String url, {void Function()? onSoundStart});

  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart});

  Future<void> playPart(Sound sound);

  Future<void> pause();

  Future<void> resume();

  Future<void> stopTheLine();

  Future<void> stop();
}

abstract interface class RecorderPort {
  Future<void> discard();
}

/// The disk and the Outbox.
abstract interface class StorePort {
  Future<int> flushTheOutbox();
}
