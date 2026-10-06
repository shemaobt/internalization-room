import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

const _beat = Duration(seconds: 30);

void main() {
  late ProviderContainer container;
  late ARoomHost host;
  late EffectRunner runner;
  int fired() => host.answers.whereType<WatchFired>().length;

  setUp(() {
    container = ProviderContainer(overrides: SalaHarness().overrides);
    addTearDown(container.dispose);
    host = ARoomHost();
    runner = runnerOver(portsOf(container), host, watchPeriod: _beat);
    host.onAnswer = (event) {
      if (event is WatchFired) runner.run(const [ArmTheWatch()]);
    };
  });

  test('the Watch fires once when the beat passes', () {
    fakeAsync((time) {
      runner.run(const [ArmTheWatch()]);

      time.elapse(_beat - const Duration(seconds: 1));
      expect(fired(), 0);
      time.elapse(const Duration(seconds: 1));
      expect(fired(), 1);
    });
  });

  test('the Watch fires once more on the next beat', () {
    fakeAsync((time) {
      runner.run(const [ArmTheWatch()]);

      time.elapse(_beat * 2);

      expect(fired(), 2);
    });
  });

  test('arming the Watch twice inside one beat still fires once', () {
    fakeAsync((time) {
      runner.run(const [ArmTheWatch(), ArmTheWatch()]);
      time.elapse(const Duration(seconds: 10));
      runner.run(const [ArmTheWatch()]);

      time.elapse(_beat - const Duration(seconds: 10));

      expect(fired(), 1);
    });
  });

  test('the Watch does not fire when the room does not want it', () {
    fakeAsync((time) {
      host.watchIsWanted = false;
      runner.run(const [ArmTheWatch()]);

      time.elapse(_beat * 3);

      expect(fired(), 0);
    });
  });
}
