import 'channel.dart';
import 'failure_policy.dart';
import 'machine.dart';
import 'scene_rehearsal.dart';
import 'session_snapshot.dart';
import 'spoken_line.dart';
import 'turn_result.dart';

/// The room client's doors and the person-call inbox. Today it carries the one look, the
/// Session read and the call for a person, and grows when the effects empty into the
/// ports.
abstract interface class RoomPort {
  /// What the room holds of [turn]: the reply it stored, the turn it is still answering,
  /// nothing that landed, or the result of a look that failed itself.
  Future<LookAnswer> lookAt(Turn turn);

  Future<SessionReadAnswer> readTheSession(String session);

  /// The passage's scene rehearsals, as the room lists them for [session].
  Future<SceneRehearsalsAnswer> sceneRehearsalsOf(String session);

  /// Calls a person for [session]: the room needs someone, and the Desk lists it as halted.
  Future<RoomResult> askForAPerson(String session);
}

/// What the one look found of a turn.
sealed class LookAnswer {
  const LookAnswer();
}

final class TheReplyLanded extends LookAnswer {
  final TurnResult reply;

  const TheReplyLanded(this.reply);
}

final class StillAnswering extends LookAnswer {
  const StillAnswering();
}

final class NothingLanded extends LookAnswer {
  const NothingLanded();
}

final class TheLookFailed extends LookAnswer {
  final RoomResult result;

  const TheLookFailed(this.result);
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

/// What the room answered to a list of the scene rehearsals: the list, or the result the
/// failure policy reads.
sealed class SceneRehearsalsAnswer {
  const SceneRehearsalsAnswer();
}

final class SceneRehearsalsListed extends SceneRehearsalsAnswer {
  final List<SceneRehearsalRecord> listed;

  const SceneRehearsalsListed(this.listed);
}

final class SceneRehearsalsFailed extends SceneRehearsalsAnswer {
  final RoomResult result;

  const SceneRehearsalsFailed(this.result);
}

/// Voice lines and parts together: one sound at a time. A part cuts a line; a line holds
/// the part beneath it, so the part can come back once the line is said.
abstract interface class SoundPort {
  Future<bool> playLine(String url, {void Function()? onSoundStart});

  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart});

  Future<bool> playFixedLine(
    String line,
    String language, {
    void Function()? onSoundStart,
  });

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

  Future<void> delete(String path);

  Stream<bool> get taken;
}

/// The disk and the Outbox.
abstract interface class StorePort {
  void stopTheSend(String row);

  Future<CurrentSession?> currentSession();

  Future<void> holdTheSession(CurrentSession session);

  /// Lets go of the Current session, or only of the session [only] names.
  Future<void> letGoOfTheSession({String? only});

  /// The end of the conversation of [session] as the tablet saw it: the clip the Guide said
  /// last, or null for a turn of the team's; absent when the tablet never saw it end.
  Future<({SpokenLine? line})?> endOf(String session);

  Future<void> holdTheEnd(String session, SpokenLine? line);

  Future<void> letGoOfTheEnd(String session);
}

/// The session this tablet was in when it last stood in a passage.
class CurrentSession {
  final String sessionId;
  final String book;
  final String pericope;
  final String language;

  /// The last clip the Guide said, while the conversation still ends on it.
  final SpokenLine? lastLine;

  /// Whether the conversation ends on a turn of the team's, which hers offers no replay for.
  final bool teamSpokeLast;

  /// Whether the session is a Panorama's: a relaunch lands on that Panorama (ADR 0064).
  final bool panorama;

  const CurrentSession({
    required this.sessionId,
    required this.book,
    required this.pericope,
    required this.language,
    this.lastLine,
    this.teamSpokeLast = false,
    this.panorama = false,
  });

  /// The end of the conversation: on [line], or, with none, on a turn of the team's, unless
  /// the tablet never saw it end ([known] false).
  CurrentSession withLine(SpokenLine? line, {bool known = true}) =>
      CurrentSession(
        sessionId: sessionId,
        book: book,
        pericope: pericope,
        language: language,
        lastLine: line,
        teamSpokeLast: known && line == null,
        panorama: panorama,
      );
}
