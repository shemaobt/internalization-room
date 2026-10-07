import 'channel.dart';
import 'failure_policy.dart';
import 'machine.dart';
import 'room_reach.dart';
import 'session_snapshot.dart';
import 'turn_result.dart';

/// The room client's doors, network health and the person-call inbox. Today it carries
/// network health, the one look, the Session read and the reach, and grows when the
/// effects empty into the ports.
abstract interface class RoomPort {
  Stream<void> get networkReturned;

  /// The reply the room stored for [turn], or null for anything else: not stored, still
  /// in flight, or a look that failed itself.
  Future<TurnResult?> lookAt(Turn turn);

  Future<SessionReadAnswer> readTheSession(String session);

  /// How far a request would get right now.
  Future<RoomReach> reach();
}

/// What the room answered to a Session read: the snapshot, or the result the failure
/// policy reads.
sealed class SessionReadAnswer {
  const SessionReadAnswer();
}

final class SessionReadAnswered extends SessionReadAnswer {
  final SessionSnapshot snapshot;

  const SessionReadAnswered(this.snapshot);
}

final class SessionReadFailed extends SessionReadAnswer {
  final RoomResult result;

  const SessionReadFailed(this.result);
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

/// The microphone: a take opened for its owner, closed into its file or discarded, and the
/// signal of a call taking the microphone and giving it back.
abstract interface class RecorderPort {
  /// Answers started, refused or failed.
  Future<MicAnswer> start(String take, MicOwner owner);

  Future<String?> stop();

  Future<void> discard();

  Stream<bool> get taken;
}

/// The disk and the Outbox.
abstract interface class StorePort {
  Future<int> flushTheOutbox();
}
