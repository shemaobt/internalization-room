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
  final AnsweringEvent answer => _stampedAnswer(answer, generation),
  _ => null,
};

AnsweringEvent _stampedAnswer(
  AnsweringEvent event,
  int generation,
) => switch (event) {
  SessionRead(
    :final snapshot,
    :final sounding,
    :final sentBeforeTheCallLanded,
  ) =>
    SessionRead(
      snapshot,
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
  MicAnswered(:final answer, :final take) => MicAnswered(
    answer,
    take: take,
    generation: generation,
  ),
  NothingReplayed() => NothingReplayed(generation: generation),
  TheSessionIsGone() => TheSessionIsGone(generation: generation),
  ThePassageClosed() => ThePassageClosed(generation: generation),
  WatchFired() => WatchFired(generation: generation),
  RetryFired() => RetryFired(generation: generation),
  NetworkFailedAt(:final door, :final why) => NetworkFailedAt(
    door,
    why: why,
    generation: generation,
  ),
  TurnGivenUp(:final turn, :final sounding) => TurnGivenUp(
    turn,
    sounding: sounding,
    generation: generation,
  ),
  LookFound(:final turn, :final reply) => LookFound(
    turn,
    reply,
    generation: generation,
  ),
  TurnAnswered(:final turn) => TurnAnswered(turn, generation: generation),
  TurnFailed(:final turn) => TurnFailed(turn, generation: generation),
  TheRefusalPassed() => TheRefusalPassed(generation: generation),
  TheCallWasRefused() => TheCallWasRefused(generation: generation),
  TheCallMetAClosedPassage() => TheCallMetAClosedPassage(
    generation: generation,
  ),
  LookEmpty(:final sounding) => LookEmpty(
    sounding: sounding,
    generation: generation,
  ),
  TheRoomRefused(:final third, :final sounding) => TheRoomRefused(
    third: third,
    sounding: sounding,
    generation: generation,
  ),
  ThePassageCannotOpen() => ThePassageCannotOpen(generation: generation),
  TheTellingCameBackEmpty() => TheTellingCameBackEmpty(generation: generation),
  TheTellingLanded() => TheTellingLanded(generation: generation),
  TheOpeningMissed() => TheOpeningMissed(generation: generation),
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

String? _anAnswerFromBeforeTheStationChangedChangedTheRoom(
  int seed,
  void Function() tried,
) {
  final random = Random(seed);
  var machine = const Machine();
  var world = const World();
  for (var step = 0; step < 60; step++) {
    final drawn = drawAnEvent(world, random);
    final event = _stamped(drawn, machine.generation) ?? drawn;
    final (next, effects) = reduce(machine, event);
    world = world.after(event, effects);
    final older = machine.generation;
    final moved = next.station != machine.station;
    machine = next;
    if (!moved) continue;
    for (var stale = 0; stale < 4; stale++) {
      final answer = _stamped(drawAnEvent(world, random), older);
      if (answer == null) continue;
      tried();
      final (after, effects) = reduce(machine, answer);
      if (!identical(after, machine) || effects.isNotEmpty) {
        return 'seed $seed, step $step: ${describeEvent(answer)} from '
            'generation $older, before ${describeEvent(event)}, changed '
            '${describeMachine(machine)} into ${describeMachine(after)} | '
            '${effects.map(describeEffect).join(', ')}';
      }
    }
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

  test('an answer stamped with the generation from before a Station change '
      'never changes the room', () {
    var tried = 0;
    for (final seed in _seeds) {
      final problem = _anAnswerFromBeforeTheStationChangedChangedTheRoom(
        seed,
        () => tried++,
      );
      if (problem != null) {
        throw TestFailure('$problem\nRe-run it alone with MACHINE_SEED=$seed');
      }
    }
    expect(
      tried,
      greaterThan(0),
      reason: 'no answer from before a Station change was tried',
    );
  });
}
