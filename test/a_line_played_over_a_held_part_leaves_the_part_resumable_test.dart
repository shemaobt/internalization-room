import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fakes.dart';

void main() {
  test('a line played over a held part leaves the part resumable', () async {
    final harness = SalaHarness();
    final container = ProviderContainer(overrides: harness.overrides);
    addTearDown(container.dispose);
    final runner = runnerOver(portsOf(container), ARoomHost());

    runner.run(const [PlayPart(PartSound(0, 'part.m4a'))]);
    await pumpEventQueue();
    runner.run(const [HoldTheSound()]);
    runner.run(const [PlayLine(Line(LineKind.guide, 1, url: 'line.mp3'))]);
    await pumpEventQueue();
    runner.run(const [LetTheSoundRun()]);
    await pumpEventQueue();

    expect(harness.playback.sounding, isTrue, reason: '${harness.sounds}');
  });
}
