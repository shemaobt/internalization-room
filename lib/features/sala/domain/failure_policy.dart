import 'channel.dart';
import 'halt.dart';
import 'machine.dart';
import 'refusal_code.dart';
import 'station.dart';

/// What a room call came back with, as the failure policy reads it (ADR 0047). Timed out
/// is this tablet's own give-up, the busy-state watchdog's.
sealed class RoomResult {
  const RoomResult();
}

final class RoomAnswered extends RoomResult {
  const RoomAnswered();
}

final class RoomNetworkFailed extends RoomResult {
  const RoomNetworkFailed();
}

final class RoomRefused extends RoomResult {
  final String code;

  const RoomRefused(this.code);
}

final class RoomSessionGone extends RoomResult {
  const RoomSessionGone();
}

final class RoomTimedOut extends RoomResult {
  const RoomTimedOut();
}

final class RoomAnsweredWithoutAReply extends RoomResult {
  const RoomAnsweredWithoutAReply();
}

final class RoomFoundNothing extends RoomResult {
  const RoomFoundNothing();
}

sealed class TabletFailure {
  const TabletFailure();
}

final class TheSoundFailed extends TabletFailure {
  final int inARow;

  const TheSoundFailed(this.inARow);
}

final class TheMicFailedToStart extends TabletFailure {
  final int inARow;
  final MicOwner owner;

  const TheMicFailedToStart(this.inARow, {required this.owner});
}

final class TheTabletCannotRecord extends TabletFailure {
  final MicOwner owner;

  const TheTabletCannotRecord({required this.owner});
}

final class TheDiskFailed extends TabletFailure {
  const TheDiskFailed();
}

final class TheBuildCannotReachTheRoom extends TabletFailure {
  const TheBuildCannotReachTheRoom();
}

/// What a door does with a refusal.
enum RefusalRule {
  /// A turn the team spoke, on the Canvas or the Panorama: a person is called on the spot.
  aSpokenTurn,

  /// A refusal of any other request: its Step is let go.
  letsTheStepGo,

  /// Nothing the door is refused changes the room.
  passes,

  /// The call for a person is asked again on the ladder.
  asksAgain,

  /// The resume goes back to the Choice, however it was turned down.
  keepsTheResume,

  /// A scene refusal reads the scene rehearsals again.
  readsTheListAgain,

  /// «terminei» refused: the scene screen says whether it went already or can be sent
  /// again, forgets the waiting person sign and reads the scene rehearsals again; a closed
  /// passage closes, and a code that stops the room only reads them again.
  sendsTheScene,
}

/// Where the room stood when the result came back. [turn] is set only for a call that
/// carries a `turn_id`.
final class FailureContext {
  final Station station;
  final Enum? step;
  final int generation;
  final Turn? turn;
  final RefusalRule rule;
  final Door door;
  final Kept sounding;

  const FailureContext({
    required this.station,
    this.step,
    required this.generation,
    this.turn,
    this.rule = RefusalRule.letsTheStepGo,
    this.door = Door.step,
    this.sounding = const NothingKept(),
  });
}

/// The one place a room result or a failure of the tablet's own becomes an event (ADR
/// 0053); only Marcia's six cases and the build guard raise the person sign (ADR 0093).
abstract final class FailurePolicy {
  static const soundFailuresBeforeAPerson = 2;

  static const micFailuresBeforeAPerson = 2;

  static const _theHandsDoors = {Door.question, Door.inbox, Door.reply};

  static const _theSceneDoors = {Door.sceneRehearsal, Door.sceneFrase};

  /// The refusals at the frase door that say nothing of the frase itself.
  static const _theFraseIsNotRefused = {
    RefusalCode.sceneRehearsalSending,
    RefusalCode.fraseOutOfPlace,
  };

  /// A turn's answer that never reached the tablet whole: the room may have acted on it,
  /// so the one look decides. For «terminei», an answer it could not read is one too.
  static bool theAnswerWasLost(RoomResult result, RefusalRule rule) =>
      switch (result) {
        RoomNetworkFailed() => true,
        RoomRefused(code: RefusalCode.unreadable) =>
          rule == RefusalRule.sendsTheScene,
        _ => false,
      };

  static MachineEvent decide(RoomResult result, FailureContext context) {
    final generation = context.generation;
    final sounding = context.sounding;
    final halt = RoomRaisedAHalt(generation: generation);
    final missed = TheOpeningMissed(generation: generation);
    final rule = context.rule;
    final turn = context.turn;
    final overAnOpening = sounding is TheOpening;
    return switch (result) {
      RoomAnswered() when turn != null => TurnAnswered(
        turn,
        generation: generation,
      ),
      RoomAnswered() => TheRoomAnswered(generation: generation),
      _ when _theHandsDoors.contains(context.door) => TheHandFailed(
        generation: generation,
      ),
      _ when context.door == Door.sceneList => TheScenesMissed(
        generation: generation,
      ),
      RoomNetworkFailed() || RoomRefused(code: RefusalCode.unreadable)
          when context.door == Door.sceneFrase &&
              rule == RefusalRule.readsTheListAgain =>
        TheTellingCameBackEmpty(readAgain: true, generation: generation),
      RoomNetworkFailed() when context.door == Door.sceneFrase =>
        TheTellingCameBackEmpty(generation: generation),
      RoomRefused() when turn != null && theAnswerWasLost(result, rule) =>
        TurnGivenUp(turn, sounding: sounding, generation: generation),
      RoomRefused(code: RefusalCode.sceneRehearsalSent)
          when rule == RefusalRule.sendsTheScene =>
        TheSceneWentAlready(generation: generation),
      RoomRefused(code: RefusalCode.passageClosed)
          when rule == RefusalRule.sendsTheScene =>
        TheCallMetAClosedPassage(generation: generation),
      RoomRefused(:final code)
          when rule == RefusalRule.sendsTheScene &&
              !RefusalCode.stopsTheRoom.contains(code) =>
        TheSceneSendRefused(generation: generation),
      RoomRefused() when rule == RefusalRule.sendsTheScene =>
        TheSceneDoorFailed(readAgain: true, generation: generation),
      RoomRefused(
        code: RefusalCode.sceneRehearsalSent ||
            RefusalCode.restartOutOfOrder ||
            RefusalCode.notFound,
      )
          when _theSceneDoors.contains(context.door) =>
        TheSceneDoorFailed(readAgain: true, generation: generation),
      RoomRefused(:final code)
          when context.door == Door.sceneFrase &&
              !_theFraseIsNotRefused.contains(code) =>
        TheTellingCameBackEmpty(generation: generation),
      RoomRefused() when _theSceneDoors.contains(context.door) =>
        TheSceneDoorFailed(
          readAgain: rule == RefusalRule.readsTheListAgain,
          generation: generation,
        ),
      RoomSessionGone() ||
      RoomRefused() ||
      RoomNetworkFailed() ||
      RoomFoundNothing() when rule == RefusalRule.keepsTheResume =>
        TheResumeFailed(generation: generation),
      RoomSessionGone() => TheSessionIsGone(generation: generation),
      _ when context.door == Door.look && context.station is SceneRehearsal =>
        TheSceneTurnFoundNothing(generation: generation),
      _ when context.door == Door.look => halt,
      RoomNetworkFailed() || RoomTimedOut() when turn != null => TurnGivenUp(
        turn,
        sounding: sounding,
        generation: generation,
      ),
      RoomFoundNothing() ||
      RoomAnsweredWithoutAReply() ||
      RoomTimedOut() when overAnOpening => missed,
      RoomFoundNothing() || RoomAnsweredWithoutAReply()
          when context.station is SceneRehearsal =>
        TheSceneTurnFoundNothing(generation: generation),
      RoomFoundNothing() || RoomAnsweredWithoutAReply() => halt,
      RoomNetworkFailed() when context.door == Door.telling =>
        TheTellingCameBackEmpty(generation: generation),
      RoomNetworkFailed() when rule == RefusalRule.asksAgain =>
        TheCallWasRefused(generation: generation),
      RoomNetworkFailed() => NetworkFailedAt(
        context.door,
        generation: generation,
      ),
      RoomTimedOut() => TheStepFailed(generation: generation),
      RoomRefused() when rule == RefusalRule.passes => TheRefusalPassed(
        generation: generation,
      ),
      RoomRefused(code: RefusalCode.nobodyToReach)
          when rule == RefusalRule.asksAgain =>
        TheRefusalPassed(generation: generation),
      RoomRefused(code: RefusalCode.passageClosed)
          when rule == RefusalRule.asksAgain =>
        TheCallMetAClosedPassage(generation: generation),
      RoomRefused() when rule == RefusalRule.asksAgain => TheCallWasRefused(
        generation: generation,
      ),
      RoomRefused(code: RefusalCode.passageCannotOpen) => ThePassageCannotOpen(
        generation: generation,
      ),
      RoomRefused(code: RefusalCode.wordlessTelling) => TheTellingCameBackEmpty(
        generation: generation,
      ),
      RoomRefused() when overAnOpening => missed,
      RoomRefused() when rule == RefusalRule.aSpokenTurn || turn != null =>
        halt,
      RoomRefused() => TheStepFailed(generation: generation),
    };
  }

  static bool _onTheSessionScreen(MicOwner owner, Station station) =>
      owner == MicOwner.conversation &&
      (station is Canvas || station is Panorama);

  static MachineEvent decideOnTheTablet(
    TabletFailure failure,
    FailureContext context,
  ) {
    final generation = context.generation;
    final halt = RoomRaisedAHalt(generation: generation);
    final passed = TheRefusalPassed(generation: generation);
    return switch (failure) {
      TheSoundFailed(:final inARow) =>
        inARow >= soundFailuresBeforeAPerson ? halt : passed,
      TheMicFailedToStart(:final owner) || TheTabletCannotRecord(:final owner)
          when !_onTheSessionScreen(owner, context.station) =>
        passed,
      TheMicFailedToStart(:final inARow) =>
        inARow >= micFailuresBeforeAPerson ? halt : passed,
      TheTabletCannotRecord() => halt,
      TheDiskFailed() => TheSceneDiskFailed(generation: generation),
      TheBuildCannotReachTheRoom() => RoomRaisedAHalt(
        callsForAPerson: false,
        generation: generation,
      ),
    };
  }
}
