import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'machine_generator.dart';

final _oneSeed = int.tryParse(Platform.environment['MACHINE_SEED'] ?? '');
final Iterable<int> _seeds = switch (_oneSeed) {
  final seed? => [seed],
  null => List.generate(500, (seed) => seed),
};

var _changes = 0;

final _machine = MachineUnderTest<Machine>(
  start: const Machine(),
  step: reduce,
  draw: (_, world, random) => drawAnEvent(world, random),
  show: describeMachine,
);

final _everyStationChangeMovesTheGenerationByOne = Invariant<Machine>(
  'every Station change moves the generation by one, but the ways off the scene '
  'screen that carry its turn or its reply (ADRs 0165, 0167)',
  (before, event, after, effects, world) {
    if (after.station == before.station) return null;
    if (event is TheSceneRehearsalLeft &&
        (before.holdsATurn || event.keepsTheReply)) {
      return null;
    }
    _changes++;
    if (after.generation == before.generation + 1) return null;
    return '${describeEvent(event)} moved the Station from '
        '${before.station.runtimeType} to ${after.station.runtimeType} and the '
        'generation from ${before.generation} to ${after.generation}';
  },
);

void main() {
  test('every Station change moves the generation by one, but the way back '
      'that carries the scene turn', () {
    expectEverySeedHolds(_machine, [
      _everyStationChangeMovesTheGenerationByOne,
    ], seeds: _seeds);
    expect(_changes, greaterThan(0), reason: 'no seed changed the Station');
  });
}
