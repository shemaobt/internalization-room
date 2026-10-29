import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'a_station_host_double.dart';
import 'fakes.dart';

const _beat = Duration(seconds: 30);

void main() {
  test('a generation that moves bumps the count by one each time', () {
    final once = moveTheGeneration(const Machine());
    final twice = moveTheGeneration(once);

    expect(const Machine().generation, 0);
    expect(once.generation, 1);
    expect(twice.generation, 2);
  });

  test('the Watch armed before a generation moves still fires and the '
      'machine takes its answer', () {
    final container = ProviderContainer(overrides: SalaHarness().overrides);
    addTearDown(container.dispose);
    final host = AStationHost();
    var machine = const Machine(station: Canvas());
    final runner = runnerOver(
      portsOf(container),
      host,
      watchPeriod: _beat,
      generation: () => machine.generation,
    );

    fakeAsync((time) {
      runner.run(const [ArmTheWatch()]);
      machine = moveTheGeneration(machine);

      time.elapse(_beat);

      final watch = host.answers.whereType<WatchFired>().single;
      expect(reduce(machine, watch).$2, const [ReadTheState(), ArmTheWatch()]);
    });
  });
}
