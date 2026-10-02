import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'machine_generator.dart';

final _oneSeed = int.tryParse(Platform.environment['MACHINE_SEED'] ?? '');
final Iterable<int> _seeds = switch (_oneSeed) {
  final seed? => [seed],
  null => List.generate(500, (seed) => seed),
};

MachineEvent? _stamped(MachineEvent event, int generation) => switch (event) {
  SessionRead(
    :final snapshot,
    :final at,
    :final sounding,
    :final sentBeforeTheCallLanded,
  ) =>
    SessionRead(
      snapshot,
      at: at,
      sounding: sounding,
      sentBeforeTheCallLanded: sentBeforeTheCallLanded,
      generation: generation,
    ),
  TheCallLanded() => TheCallLanded(generation: generation),
  TheRoomAnswered() => TheRoomAnswered(generation: generation),
  TheAnswerWarned() => TheAnswerWarned(generation: generation),
  RoomRaisedAHalt(:final sounding, :final callsForAPerson) => RoomRaisedAHalt(
    sounding: sounding,
    callsForAPerson: callsForAPerson,
    generation: generation,
  ),
  LineArrived(:final line, :final by) => LineArrived(
    line,
    by: by,
    generation: generation,
  ),
  LineNotSaid(:final line) => LineNotSaid(line, generation: generation),
  PlayerOpened() => PlayerOpened(generation: generation),
  PlayerEnded() => PlayerEnded(generation: generation),
  PlayerFailed(:final source, :final sounding) => PlayerFailed(
    source,
    sounding: sounding,
    generation: generation,
  ),
  MicOpened(:final owner, :final take) => MicOpened(
    owner,
    take: take,
    generation: generation,
  ),
  MicClosed() => MicClosed(generation: generation),
  NothingReplayed() => NothingReplayed(generation: generation),
  TheSessionIsGone() => TheSessionIsGone(generation: generation),
  ThePassageClosed() => ThePassageClosed(generation: generation),
  WatchFired() => WatchFired(generation: generation),
  RetryFired() => RetryFired(generation: generation),
  NetworkFailedAt(:final door) => NetworkFailedAt(door, generation: generation),
  _ => null,
};

String? _aStaleAnswerChangedTheRoom(int seed) {
  final random = Random(seed);
  var machine = const Machine();
  var world = const World();
  for (var step = 0; step < 60; step++) {
    if (random.nextInt(6) == 0) {
      final older = machine.generation;
      machine = moveTheGeneration(machine);
      for (var stale = 0; stale < 4; stale++) {
        final event = _stamped(drawAnEvent(world, random), older);
        if (event == null) continue;
        final (after, effects) = reduce(machine, event);
        if (!identical(after, machine) || effects.isNotEmpty) {
          return 'seed $seed, step $step: ${describeEvent(event)} from '
              'generation $older changed ${describeMachine(machine)} into '
              '${describeMachine(after)} | '
              '${effects.map(describeEffect).join(', ')}';
        }
      }
      continue;
    }
    final drawn = drawAnEvent(world, random);
    final event = _stamped(drawn, machine.generation) ?? drawn;
    final (next, effects) = reduce(machine, event);
    world = world.after(event, effects);
    machine = next;
  }
  return null;
}

void main() {
  test('an answer from an older generation never changes the room', () {
    for (final seed in _seeds) {
      final problem = _aStaleAnswerChangedTheRoom(seed);
      if (problem != null) {
        throw TestFailure('$problem\nRe-run it alone with MACHINE_SEED=$seed');
      }
    }
  });
}
