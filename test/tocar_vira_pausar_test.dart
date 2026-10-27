import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;
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
  notifier.retroTap();
  notifier.retroTap();
  await settle();
  await confirmarATraducao(container);
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
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
  );
  return container;
}

SalaHarness harnessApontando() =>
    SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 600)
      ..room.verdictChecked = false
      ..room.verdictFindingSegmentId = 'trecho-1';

void main() {
  test('um teto que vence antes do dublê nunca deixa o player real soando com '
      'o estado dizendo parado', () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 20))
      ..room.verdictChecked = false
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await pumpAoApontado(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.playback.length = const Duration(milliseconds: 50);

    notifier.traduzirAFraseDeNovo(0);
    await waitFor(
      'o trecho apontado estar tocando',
      () => container.read(salaSessionProvider).btTrechoTocando,
    );

    // O teto (comprimento 50ms + margem 20ms) vence bem antes desta espera, e o
    // dublê nunca é avisado de que o clipe terminou.
    await settle(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    final tocando = estado.btTrechoTocando || estado.btRetroTocando;
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
