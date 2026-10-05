import 'halt.dart';
import 'machine.dart';
import 'refusal_code.dart';
import 'session_state.dart';

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

/// Where the room stood when the result came back. [turn] is set only for a call that
/// carries a `turn_id`. [refusalHalts] marks the calls whose refusal calls a person on the
/// spot; every other refusal counts toward [refusals], the ones already counted.
final class FailureContext {
  final SalaStage stage;
  final Enum? step;
  final int generation;
  final Turn? turn;
  final bool refusalHalts;
  final Door door;
  final int refusals;
  final Kept sounding;

  const FailureContext({
    required this.stage,
    this.step,
    required this.generation,
    this.turn,
    this.refusalHalts = false,
    this.door = Door.step,
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
    return switch (result) {
      RoomAnswered() => TheRoomAnswered(generation: generation),
      RoomSessionGone() => TheSessionIsGone(generation: generation),
      RoomNetworkFailed() || RoomTimedOut() when context.turn != null =>
        TurnGivenUp(context.turn!, sounding: sounding, generation: generation),
      RoomNetworkFailed() => NetworkFailedAt(
        context.door,
        generation: generation,
      ),
      RoomTimedOut() => halt,
      RoomRefused(:final code) when RefusalCode.stopsTheRoom.contains(code) =>
        halt,
      RoomRefused(code: RefusalCode.passageCannotOpen) => ThePassageCannotOpen(
        generation: generation,
      ),
      RoomRefused() when context.refusalHalts || context.turn != null => halt,
      RoomRefused() => TheRoomRefused(
        third: context.refusals + 1 >= refusalsBeforeAPerson,
        sounding: sounding,
        generation: generation,
      ),
    };
  }
}
