import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

const _beat = Duration(seconds: 30);
const _retry = Duration(seconds: 5);

void main() {
  test('a generation that moves bumps the count by one each time', () {
    final once = moveTheGeneration(const Machine());
    final twice = moveTheGeneration(once);

    expect(const Machine().generation, 0);
    expect(once.generation, 1);
    expect(twice.generation, 2);
  });

  test('the Watch and the retry armed before a generation moves still fire '
      'and the machine takes their answers', () {
    final container = ProviderContainer(overrides: SalaHarness().overrides);
    addTearDown(container.dispose);
    final host = ARoomHost()..roomIsReachable = false;
    var machine = reduce(const Machine(), const NetworkFailedAt(Door.step)).$1;
    final runner = EffectRunner(
      room: container.read(roomPortProvider),
      sound: container.read(soundPortProvider),
      recorder: container.read(recorderPortProvider),
      store: container.read(storePortProvider),
      host: host,
      watchPeriod: () => _beat,
      retryDelay: (_) => _retry,
      generation: () => machine.generation,
    );

    fakeAsync((time) {
      runner.run(const [ArmTheWatch(), ArmTheRetry()]);
      machine = moveTheGeneration(machine);

      time.elapse(_beat);

      final watch = host.answers.whereType<WatchFired>().single;
      final retry = host.answers.whereType<RetryFired>().single;
      expect(reduce(machine, watch).$2, const [ReadTheState(), ArmTheWatch()]);
      expect(reduce(machine, retry).$2, const [ProbeTheRoom()]);
    });
  });
}
