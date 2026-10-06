import 'channel.dart';
import 'machine.dart';
import 'turn_result.dart';

/// The room client's doors, network health and the person-call inbox. Today it carries
/// network health and the one look, and grows when the effects empty into the ports.
abstract interface class RoomPort {
  Stream<void> get networkReturned;

  /// The reply the room stored for [turn], or null for anything else: not stored, still
  /// in flight, or a look that failed itself.
  Future<TurnResult?> lookAt(Turn turn);
}

/// Voice lines and parts together: one sound at a time. A part cuts a line; a line holds
/// the part beneath it, so the part can come back once the line is said.
abstract interface class SoundPort {
  Future<bool> playLine(String url, {void Function()? onSoundStart});

  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart});

  Future<void> playPart(Sound sound);

  Stream<void> get partEnded;

  Stream<void> get partFailed;

  Stream<void> get partOpened;

  Duration? get partLength;

  Duration get partPosition;

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
