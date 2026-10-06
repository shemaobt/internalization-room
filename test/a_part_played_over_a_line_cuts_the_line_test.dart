import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

void main() {
  test(
    'a line and a part dispatched together never sound at once on the sound port',
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

      runner.run(const [
        PlayLine(Line(LineKind.guide, 1, url: 'line.mp3')),
        PlayPart(PartSound(0, 'part.m4a')),
      ]);
      await pumpEventQueue();

      final voice = harness.sounds.where((entry) => entry.startsWith('voice:'));
      expect(voice, ['voice:line', 'voice:stop'], reason: '${harness.sounds}');
      expect(
        harness.sounds.indexOf('voice:stop'),
        lessThan(harness.sounds.indexOf('playback:play')),
        reason: '${harness.sounds}',
      );
      expect(harness.playback.sounding, isTrue);
    },
  );
}
