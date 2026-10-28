import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/pausa.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_wav_take.dart';

const _tenSeconds = Duration(seconds: 10);

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

void main() {
  test(
    'the strip shows a long gap as a valley and a band per translated frase',
    () {
      final valley = sceneStripOf(
        width: 300,
        length: _tenSeconds,
        envelope: envelopeOf(
          aSpokenWav(
            gaps: [(const Duration(seconds: 3), const Duration(seconds: 5))],
          ),
        ),
      );
      final banded = sceneStripOf(
        width: 300,
        length: _tenSeconds,
        frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)],
      );

      final tallest = valley.columns.reduce(max);
      expect(tallest, greaterThan(0));
      for (var x = 92; x <= 148; x++) {
        expect(
          valley.columns[x],
          lessThan(tallest / 10),
          reason: 'a coluna $x cai no silêncio de 3 s a 5 s',
        );
      }
      expect(banded.bands.map((band) => (band.from, band.to)), [
        (0.0, 90.0),
        (90.0, 180.0),
      ]);
      expect(banded.ticks, [90.0, 180.0]);
    },
  );

  test('the strip draws the pending pausa and the player', () {
    final paused = sceneStripOf(
      width: 300,
      length: _tenSeconds,
      pausa: const Duration(milliseconds: 3100),
    );
    final playing = sceneStripOf(
      width: 300,
      length: _tenSeconds,
      playhead: const Duration(seconds: 5),
    );

    expect(paused.pausa, closeTo(93, 1e-9));
    expect(playing.playhead, closeTo(150, 1e-9));
  });

  test('a frase of a part recorded again is drawn faint along the strip, '
      'never as a translated band with its tick', () {
    final strip = sceneStripOf(
      width: 300,
      length: _tenSeconds,
      stale: [_frase('f1', 0, 4000)],
    );

    expect(strip.staleBands.map((band) => (band.from, band.to)), [
      (0.0, 120.0),
    ]);
    expect(strip.bands, isEmpty);
    expect(strip.ticks, isEmpty);
  });
}
