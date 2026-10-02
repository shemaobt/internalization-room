import 'channel.dart';

/// The room client's doors, network health and the person-call inbox. Today it carries
/// network health only, and grows when the effects empty into the ports.
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
