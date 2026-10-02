import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';

import 'fakes.dart';

bool _neverBothSounding(List<String> log) {
  var line = false;
  var part = false;
  for (final entry in log) {
    switch (entry) {
      case 'voice:line' || 'voice:asset':
        line = true;
      case 'voice:stop':
        line = false;
      case 'playback:play':
        part = true;
      case 'playback:pause' || 'playback:stop':
        part = false;
    }
    if (line && part) return false;
  }
  return true;
}

void main() {
  late SalaHarness harness;
  late ProviderContainer container;

  setUp(() {
    harness = SalaHarness();
    container = ProviderContainer(overrides: harness.overrides);
    addTearDown(container.dispose);
  });

  test('a part asked for while a line is sounding silences the line first', () {
    final sound = container.read(soundPortProvider);
    harness.voice.holdNextLine();

    sound.playLine('line.mp3');
    sound.playPart(const PartSound(0, 'part.m4a'));

    expect(
      _neverBothSounding(harness.sounds),
      isTrue,
      reason: '${harness.sounds}',
    );
    expect(harness.sounds, contains('playback:play'));
  });

  test('a line asked for while a part is sounding silences the part first', () {
    final sound = container.read(soundPortProvider);

    sound.playPart(const PartSound(0, 'part.m4a'));
    sound.playLine('line.mp3');

    expect(
      _neverBothSounding(harness.sounds),
      isTrue,
      reason: '${harness.sounds}',
    );
    expect(harness.sounds, contains('voice:line'));
  });
}
