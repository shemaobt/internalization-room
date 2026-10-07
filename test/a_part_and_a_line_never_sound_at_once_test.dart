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
      case 'voice:line' || 'voice:asset' || 'voice:fixed':
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

bool _lineIsSounding(List<String> log) {
  var line = false;
  for (final entry in log) {
    if (entry == 'voice:line' ||
        entry == 'voice:asset' ||
        entry == 'voice:fixed') {
      line = true;
    }
    if (entry == 'voice:stop') line = false;
  }
  return line;
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

  test(
    'a line that ends after a newer line started leaves the newer one sounding',
    () async {
      final sound = container.read(soundPortProvider);
      harness.voice.holdNextLine();
      final first = sound.playLine('first.mp3');
      harness.voice.finishHeldLine();
      harness.voice.holdNextLine();
      sound.playLine('second.mp3');
      await first;

      sound.playPart(const PartSound(0, 'part.m4a'));

      expect(
        _neverBothSounding(harness.sounds),
        isTrue,
        reason: '${harness.sounds}',
      );
    },
  );

  test(
    'a line asked while the second part of a chain plays stops that part',
    () async {
      final sound = container.read(soundPortProvider);
      harness.playback.completions.listen(
        (_) => sound.playPart(const PartSound(1, 'second.m4a')),
      );
      sound.playPart(const PartSound(0, 'first.m4a'));
      await pumpEventQueue();
      harness.playback.finishPlayback();
      await pumpEventQueue();
      expect(harness.playback.sounding, isTrue);

      sound.playLine('line.mp3');
      await pumpEventQueue();

      expect(harness.playback.sounding, isFalse);
      expect(_lineIsSounding(harness.sounds), isTrue);
    },
  );

  test('a line after a part that ended on its own still sounds', () async {
    final sound = container.read(soundPortProvider);
    sound.playPart(const PartSound(0, 'part.m4a'));
    await pumpEventQueue();
    harness.playback.finishPlayback();
    await pumpEventQueue();

    sound.playLine('line.mp3');
    await pumpEventQueue();

    expect(harness.playback.sounding, isFalse);
    expect(_lineIsSounding(harness.sounds), isTrue);
  });
}
