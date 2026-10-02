import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

void main() {
  test(
    'a part played while a line is still sounding leaves the line sounding',
    () async {
      final harness = SalaHarness();
      final container = ProviderContainer(overrides: harness.overrides);
      addTearDown(container.dispose);
      final runner = runnerOver(
        container,
        ARoomHost(),
        watchPeriod: const Duration(seconds: 30),
      );
      harness.voice.holdNextLine();
      container.read(soundPortProvider).playLine('line.mp3');

      runner.run(const [PlayPart(PartSound(0, 'part.m4a'))]);
      await pumpEventQueue();

      final voice = harness.sounds.where((entry) => entry.startsWith('voice:'));
      expect(voice.last, 'voice:line', reason: '${harness.sounds}');
    },
  );
}
