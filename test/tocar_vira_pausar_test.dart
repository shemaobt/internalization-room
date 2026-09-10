import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;
import 'playback_ceiling_test.dart' show gravaParte;

/// A team standing at the findings screen, with one stretch told and the analyst's
/// pointer already on it — the ground every case here plays out on.
Future<ProviderContainer> pumpAoApontado(SalaHarness harness) async {
  final container = await inConversa(harness);
  final notifier = container.read(salaSessionProvider.notifier);

  notifier.goEnsaio();
  await gravaParte(container, notifier);
  notifier.startRetro();
  await settle();

  harness.playback.at = const Duration(milliseconds: 40);
  notifier.cortarTrecho();
  await settle();
  notifier.retroTap();
  await waitFor(
    'o primeiro trecho chegar à sala',
    () => harness.room.chunksSent == 1,
  );
  await settle();

  harness.playback.at = const Duration(milliseconds: 600);
  harness.playback.finishPlayback();
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
  );
  return container;
}

SalaHarness harnessApontando() =>
    SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 600)
      ..room.verdictChecked = false
      ..room.verdictFindingSegmentId = 'trecho-1';

void main() {
  group('a voz materna', () {
    test('tocar de novo pausa em vez de recomeçar', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirVozMaterna();
      await waitFor(
        'o trecho apontado estar tocando',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );

      notifier.ouvirVozMaterna();
      await settle();

      expect(
        harness.playback.paused,
        isTrue,
        reason: 'o dublê recebeu pause, não um segundo play/playRange',
      );
      expect(
        harness.playback.ranges.length,
        1,
        reason: 'nenhum playRange novo — o clipe não recomeçou',
      );

      final state = container.read(salaSessionProvider);
      expect(state.btTrechoTocando, isFalse);
      expect(state.btTrechoPausada, isTrue);
    });

    test('tocar uma terceira vez retoma de onde parou', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirVozMaterna();
      await waitFor(
        'o trecho apontado estar tocando',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );
      notifier.ouvirVozMaterna();
      await settle();
      notifier.ouvirVozMaterna();
      await settle();

      expect(
        harness.playback.paused,
        isFalse,
        reason: 'o dublê recebeu resume',
      );
      expect(
        harness.playback.ranges.length,
        1,
        reason: 'sem um novo playRange — não recomeçou do zero',
      );

      final state = container.read(salaSessionProvider);
      expect(state.btTrechoTocando, isTrue);
      expect(state.btTrechoPausada, isFalse);
    });

    test('terminar sozinho volta ao começo na próxima vez', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirVozMaterna();
      await waitFor(
        'o trecho apontado estar tocando',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );
      harness.playback.finishPlayback();
      await waitFor(
        'o trecho parar de tocar sozinho',
        () => !container.read(salaSessionProvider).btTrechoTocando,
      );

      notifier.ouvirVozMaterna();
      await settle();

      expect(
        harness.playback.ranges.length,
        2,
        reason: 'um clipe que terminou sozinho recomeça do zero na próxima vez',
      );
      expect(container.read(salaSessionProvider).btTrechoTocando, isTrue);
    });
  });

  group('a voz da ponte', () {
    test('tocar de novo pausa em vez de recomeçar', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirTraducaoEmPortugues();
      await waitFor(
        'a ponte estar tocando',
        () => container.read(salaSessionProvider).btRetroTocando,
      );
      final tocadosAntes = harness.playback.played.length;

      notifier.ouvirTraducaoEmPortugues();
      await settle();

      expect(harness.playback.paused, isTrue);
      expect(
        harness.playback.played.length,
        tocadosAntes,
        reason: 'nenhuma nova chamada a play — o dublê só recebeu pause',
      );

      final state = container.read(salaSessionProvider);
      expect(state.btRetroTocando, isFalse);
      expect(state.btRetroPausada, isTrue);
    });

    test('tocar uma terceira vez retoma de onde parou', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirTraducaoEmPortugues();
      await waitFor(
        'a ponte estar tocando',
        () => container.read(salaSessionProvider).btRetroTocando,
      );
      final tocadosAntes = harness.playback.played.length;

      notifier.ouvirTraducaoEmPortugues();
      await settle();
      notifier.ouvirTraducaoEmPortugues();
      await settle();

      expect(harness.playback.paused, isFalse);
      expect(
        harness.playback.played.length,
        tocadosAntes,
        reason: 'sem um novo play — retomou, não recomeçou',
      );
      expect(container.read(salaSessionProvider).btRetroTocando, isTrue);
    });
  });

  // The two cases that lived here for the circle "Ouvir de novo a parte apontada" —
  // pause-instead-of-restart and resume-from-where-it-stopped — asserted that a tap on it
  // played the trecho. That decision changed: the circle now repeats the verdict's own
  // line instead, and `a_esfera_repete_a_pergunta_test.dart` covers it (cases 6 and 8 of
  // the R16 testing plan).

  test(
    'os players não se atropelam: tocando a materna, a ponte não entra',
    () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.ouvirVozMaterna();
      await waitFor(
        'o trecho apontado estar tocando',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );

      notifier.ouvirTraducaoEmPortugues();
      await settle();

      expect(
        container.read(salaSessionProvider).btRetroTocando,
        isFalse,
        reason: 'a ponte continua fora enquanto a materna toca — como hoje',
      );
      expect(container.read(salaSessionProvider).btTrechoTocando, isTrue);
    },
  );

  test('um teto que vence antes do dublê nunca deixa o player real soando com '
      'o estado dizendo parado', () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 20))
      ..playback.length = const Duration(milliseconds: 50)
      ..room.verdictChecked = false
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await pumpAoApontado(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => container.read(salaSessionProvider).btTrechoTocando,
    );

    // O teto (comprimento 50ms + margem 20ms) vence bem antes desta espera, e o
    // dublê nunca é avisado de que o clipe terminou.
    await settle(const Duration(milliseconds: 300));

    final tocando = container.read(salaSessionProvider).btTrechoTocando;
    final soando = harness.playback.sounding;
    expect(
      tocando || !soando,
      isTrue,
      reason:
          'se o teto desligou o estado, tem que ter parado o player de '
          'verdade — nunca um player tocando sob um estado que diz parado',
    );
  });
}
