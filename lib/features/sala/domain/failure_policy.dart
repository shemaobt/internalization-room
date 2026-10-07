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

/// What a door does with a refusal.
enum RefusalRule {
  /// The openSession/sendTurn/loadWheel family: a person is called on the spot.
  haltsAtOnce,

  /// Three refusals call a person; [FailureContext.refusals] are the ones counted.
  counts,

  /// A code that stops the room calls a person; any other refusal changes nothing.
  passesUnlessItStops,

  /// Nothing the door is refused changes the room.
  passes,

  /// The call for a person is asked again on the ladder.
  asksAgain,

  /// The resume calls a person and keeps the resume, however it was turned down.
  keepsTheResume,
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
  final int refusals;
  final Kept sounding;

  const FailureContext({
    required this.station,
    this.step,
    required this.generation,
    this.turn,
    this.rule = RefusalRule.counts,
    this.door = Door.step,
    this.why = RoomReach.noNetwork,
    this.refusals = 0,
    this.sounding = const NothingKept(),
  });
}

/// The one place a room result becomes an event (ADR 0053).
abstract final class FailurePolicy {
  static const refusalsBeforeAPerson = 3;

  static MachineEvent decide(RoomResult result, FailureContext context) {
    final generation = context.generation;
    final sounding = context.sounding;
    final halt = RoomRaisedAHalt(sounding: sounding, generation: generation);
    final passed = TheRefusalPassed(generation: generation);
    final keptTheResume = RoomRaisedAHalt(
      sounding: const TheResume(),
      generation: generation,
    );
    final rule = context.rule;
    final turn = context.turn;
    return switch (result) {
      RoomAnswered() when turn != null => TurnAnswered(
        turn,
        generation: generation,
      ),
      RoomAnswered() => TheRoomAnswered(generation: generation),
      RoomSessionGone() when rule == RefusalRule.keepsTheResume =>
        keptTheResume,
      RoomSessionGone() => TheSessionIsGone(generation: generation),
      RoomNetworkFailed() || RoomTimedOut() when turn != null => TurnGivenUp(
        turn,
        sounding: sounding,
        generation: generation,
      ),
      RoomNetworkFailed() => NetworkFailedAt(
        context.door,
        why: context.why,
        generation: generation,
      ),
      RoomTimedOut() => halt,
      RoomRefused() when rule == RefusalRule.passes => passed,
      RoomRefused() when rule == RefusalRule.keepsTheResume => keptTheResume,
      RoomRefused(code: RefusalCode.nobodyToReach)
          when rule == RefusalRule.asksAgain =>
        passed,
      RoomRefused(code: RefusalCode.passageClosed)
          when rule == RefusalRule.asksAgain =>
        TheCallMetAClosedPassage(generation: generation),
      RoomRefused() when rule == RefusalRule.asksAgain => TheCallWasRefused(
        generation: generation,
      ),
      RoomRefused(:final code) when RefusalCode.stopsTheRoom.contains(code) =>
        halt,
      RoomRefused() when rule == RefusalRule.passesUnlessItStops => passed,
      RoomRefused(code: RefusalCode.passageCannotOpen) => ThePassageCannotOpen(
        generation: generation,
      ),
      RoomRefused(code: RefusalCode.wordlessTelling) => TheTellingCameBackEmpty(
        generation: generation,
      ),
      RoomRefused() when sounding is TheOpening => TheOpeningMissed(
        generation: generation,
      ),
      RoomRefused() when rule == RefusalRule.haltsAtOnce || turn != null =>
        halt,
      RoomRefused() => TheRoomRefused(
        third: context.refusals + 1 >= refusalsBeforeAPerson,
        sounding: sounding,
        generation: generation,
      ),
    };
  }
}
