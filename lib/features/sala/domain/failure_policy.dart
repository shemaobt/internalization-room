import 'halt.dart';
import 'machine.dart';
import 'refusal_code.dart';
import 'room_reach.dart';
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

  const TheMicFailedToStart(this.inARow);
}

final class TheTabletCannotRecord extends TabletFailure {
  const TheTabletCannotRecord();
}

final class TheBuildCannotReachTheRoom extends TabletFailure {
  const TheBuildCannotReachTheRoom();
}

/// What a door does with a refusal.
enum RefusalRule {
  /// A turn the team spoke, on the Canvas or the Panorama: a person is called on the spot.
  aSpokenTurn,

  /// A refusal of any other request: its Step is let go.
  counts,

  /// Nothing the door is refused changes the room.
  passes,

  /// The call for a person is asked again on the ladder.
  asksAgain,

  /// The resume goes back to the Choice, however it was turned down.
  keepsTheResume,

  /// A scene refusal reads the scene rehearsals again.
  readsTheListAgain,
}

/// Where the room stood when the result came back. [turn] is set only for a call that
/// carries a `turn_id`, and [why] says how far a request gets when the network failed.
final class FailureContext {
  final Station station;
  final Enum? step;
  final int generation;
  final Turn? turn;
  final RefusalRule rule;
  final Door door;
  final RoomReach why;
  final Kept sounding;

  const FailureContext({
    required this.station,
    this.step,
    required this.generation,
    this.turn,
    this.rule = RefusalRule.counts,
    this.door = Door.step,
    this.why = RoomReach.noNetwork,
    this.sounding = const NothingKept(),
  });

  FailureContext copyWith({Turn? turn, Kept? sounding, int? generation}) =>
      FailureContext(
        station: station,
        step: step,
        generation: generation ?? this.generation,
        turn: turn ?? this.turn,
        rule: rule,
        door: door,
        why: why,
        sounding: sounding ?? this.sounding,
      );
}

/// The one place a room result or a failure of the tablet's own becomes an event (ADR
/// 0053); only Marcia's six cases and the build guard raise the person sign (ADR 0093).
abstract final class FailurePolicy {
  static const soundFailuresBeforeAPerson = 2;

  static const micFailuresBeforeAPerson = 2;

  static const _theHandsDoors = {Door.question, Door.inbox, Door.reply};

  static MachineEvent decide(RoomResult result, FailureContext context) {
    final generation = context.generation;
    final sounding = context.sounding;
    final halt = RoomRaisedAHalt(sounding: sounding, generation: generation);
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
      RoomRefused(
        code: RefusalCode.sceneRehearsalSent ||
            RefusalCode.restartOutOfOrder ||
            RefusalCode.notFound,
      )
          when context.door == Door.sceneRehearsal =>
        TheSceneDoorFailed(readAgain: true, generation: generation),
      RoomRefused() when context.door == Door.sceneRehearsal =>
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
      RoomNetworkFailed() || RoomTimedOut() when turn != null => TurnGivenUp(
        turn,
        sounding: sounding,
        generation: generation,
      ),
      RoomFoundNothing() ||
      RoomAnsweredWithoutAReply() when overAnOpening => missed,
      RoomFoundNothing() when context.station is SceneRehearsal =>
        TheSceneTurnFoundNothing(generation: generation),
      RoomFoundNothing() || RoomAnsweredWithoutAReply() => halt,
      RoomNetworkFailed() when context.door == Door.telling =>
        TheTellingCameBackEmpty(generation: generation),
      RoomNetworkFailed() when rule == RefusalRule.asksAgain =>
        TheCallWasRefused(generation: generation),
      RoomNetworkFailed() => NetworkFailedAt(
        context.door,
        why: context.why,
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

  static MachineEvent decideOnTheTablet(
    TabletFailure failure,
    FailureContext context,
  ) {
    final generation = context.generation;
    final halt = RoomRaisedAHalt(
      sounding: context.sounding,
      generation: generation,
    );
    final passed = TheRefusalPassed(generation: generation);
    return switch (failure) {
      TheSoundFailed(:final inARow) =>
        inARow >= soundFailuresBeforeAPerson ? halt : passed,
      TheMicFailedToStart(:final inARow) =>
        inARow >= micFailuresBeforeAPerson ? halt : passed,
      TheTabletCannotRecord() => halt,
      TheBuildCannotReachTheRoom() => RoomRaisedAHalt(
        sounding: context.sounding,
        callsForAPerson: false,
        generation: generation,
      ),
    };
  }
}
