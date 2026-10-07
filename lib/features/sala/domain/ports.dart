import 'channel.dart';
import 'failure_policy.dart';
import 'machine.dart';
import 'room_reach.dart';
import 'session_snapshot.dart';
import 'turn_result.dart';

/// The room client's doors, network health and the person-call inbox. Today it carries
/// network health, the one look, the Session read, the reach, the call for a person and
/// the person-arrived mark, and grows when the effects empty into the ports.
abstract interface class RoomPort {
  Stream<void> get networkReturned;

  /// The reply the room stored for [turn], or null for anything else: not stored, still
  /// in flight, or a look that failed itself.
  Future<TurnResult?> lookAt(Turn turn);

  Future<SessionReadAnswer> readTheSession(String session);

  /// How far a request would get right now.
  Future<RoomReach> reach();

  /// Calls a person for [session]: the room needs someone, and the Desk lists it as halted.
  Future<RoomResult> askForAPerson(String session);

  /// The same call for a halt with no session to name, made by the tablet's own device.
  Future<TabletCallAnswer> askForAPersonWithoutASession();

  /// Tells the server the person arrived at the room for [session].
  Future<RoomResult> personArrived(String session);
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

/// What the room answered to a call made by the tablet, or why the call was never made.
sealed class TabletCallAnswer {
  const TabletCallAnswer();
}

final class TabletCallAnswered extends TabletCallAnswer {
  final RoomResult result;

  const TabletCallAnswered(this.result);
}

final class TheTabletIsUnknown extends TabletCallAnswer {
  const TheTabletIsUnknown();
}

final class TheDeviceLinkUnread extends TabletCallAnswer {
  const TheDeviceLinkUnread();
}

final class TheRoomIsGone extends TabletCallAnswer {
  const TheRoomIsGone();
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

  Duration get linePosition;

  Duration? get lineLength;

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

  /// Writes the passage down as finished; a failure to write is swallowed.
  Future<void> markThePassageClosed(String book, String passage);

  Future<CurrentSession?> currentSession();

  Future<void> holdTheSession(CurrentSession session);

  /// Lets go of the Current session, or only of the session [only] names.
  Future<void> letGoOfTheSession({String? only});
}

/// The session this tablet was in when it last stood in a passage.
class CurrentSession {
  final String sessionId;
  final String book;
  final String pericope;
  final String language;

  const CurrentSession({
    required this.sessionId,
    required this.book,
    required this.pericope,
    required this.language,
  });
}
