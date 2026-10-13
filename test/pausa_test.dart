import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/pausa.dart';

import 'a_wav_take.dart';

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

const umaLacuna = [
  (Duration(milliseconds: 3000), Duration(milliseconds: 3400)),
];

void main() {
  test('a part that is not a PCM16 WAV has no envelope', () {
    expect(envelopeOf(utf8.encode('a equipe falou')), isNull);
  });

  test('a stereo PCM16 part is read for its silences like a mono one', () {
    final envelope = envelopeOf(aSpokenWav(channels: 2, gaps: umaLacuna));

    expect(silencesIn(envelope!), [(from: s(3.0), to: s(3.4))]);
  });

  test('a WAV with another chunk before its data is read from its data', () {
    final envelope = envelopeOf(
      aSpokenWav(chunkBeforeData: true, gaps: umaLacuna),
    );

    expect(silencesIn(envelope!), [(from: s(3.0), to: s(3.4))]);
  });

  test('a part silent throughout has no silence to snap to', () {
    final envelope = envelopeOf(aSpokenWav(silentThroughout: true));

    expect(silencesIn(envelope!), isEmpty);
  });

  test('a quiet run shorter than 150 ms is not a silence', () {
    final envelope = envelopeOf(aSpokenWav(gaps: [(s(3.0), s(3.12))]));

    expect(silencesIn(envelope!), isEmpty);
  });

  test('on a near tie the silence before the tap wins, because one after it '
      'counts double', () {
    final envelope = envelopeOf(
      aSpokenWav(gaps: [(s(3.0), s(3.7)), (s(4.2), s(4.4))]),
    );

    expect(
      placeThePause(envelope!, s(4.0), lo: s(0.2), hi: s(9.9)),
      s(3.35),
      reason:
          'a de antes termina 0,3 s antes do toque; a de depois começa '
          '0,2 s depois, que conta 0,4 s',
    );
  });
}
