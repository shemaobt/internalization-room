import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show ouvir, parte, pausar, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show entrarComAFala, ouvirAPausa, pausarAos, s, tocarOCirculo;

final _umaLacunaAos4e4 = aSpokenWav(gaps: [(s(4.4), s(4.8))]);

void main() {
  testWidgets('play over a pause standing mid-part drops it and the part goes '
      'on from the pause, not from the cursor', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, _umaLacunaAos4e4);
    await pausarAos(tester, harness, s(4.0));
    expect(container.read(salaSessionProvider).btCorte, s(4.0));

    await tocar(tester, ouvir);

    final state = container.read(salaSessionProvider);
    expect(
      state.btCortado,
      isFalse,
      reason:
          'a pausa ficava de pé depois do play, e o círculo abria o microfone '
          'nela',
    );
    expect(state.btCorte, state.btCursor);
    expect(
      harness.playback.playedFrom.last,
      s(4.0),
      reason:
          'o play tocava o trecho do cursor até a pausa em vez de seguir dela',
    );
    closeTheRoom(container);
  });

  testWidgets('after play dropped the pause, the circle marks a new pause at '
      'the head and never opens the microphone on the old one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, _umaLacunaAos4e4);
    await pausarAos(tester, harness, s(4.0));
    await tocar(tester, ouvir);

    await pausarAos(tester, harness, s(6.0));

    final state = container.read(salaSessionProvider);
    expect(
      state.btPhase,
      BtPhase.playing,
      reason:
          'o círculo abria o microfone na pausa que o play tinha descartado',
    );
    expect(
      state.btCorte,
      s(4.6),
      reason: 'a pausa nova não era marcada na cabeça, no silêncio mais perto',
    );
    closeTheRoom(container);
  });

  testWidgets('play after «ouvir a pausa» was paused drops the pause and the '
      'part goes on from it, not the rest of the moment before', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, _umaLacunaAos4e4);
    await pausarAos(tester, harness, s(4.0));
    await tocar(tester, ouvirAPausa);
    expect(harness.playback.ranges.last, '2500-4000');
    await tocar(tester, pausar);
    expect(container.read(salaSessionProvider).btTrechoPausada, isTrue);

    await tocar(tester, ouvir);

    expect(
      harness.playback.playedFrom.last,
      s(4.0),
      reason: 'o play retomava o momento antes da pausa em vez de seguir dela',
    );
    expect(container.read(salaSessionProvider).btCortado, isFalse);
    closeTheRoom(container);
  });

  testWidgets('play over a pause standing at the end of the part plays the '
      'moment before it, and the pause stays', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarComAFala(tester, harness, null);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocarOCirculo(tester);
    expect(container.read(salaSessionProvider).btCorte, parte);

    await tocar(tester, ouvir);

    expect(
      harness.playback.ranges.lastOrNull,
      '8500-10000',
      reason:
          'no fim da parte o play seguia da pausa, onde não há mais nada a '
          'ouvir',
    );
    expect(
      container.read(salaSessionProvider).btCortado,
      isTrue,
      reason: 'a pausa no fim da gravação caía com o play',
    );
    closeTheRoom(container);
  });
}
