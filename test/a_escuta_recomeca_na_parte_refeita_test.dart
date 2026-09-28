import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test(
    'segurar a gravação no meio de uma parte não parte a escuta dela',
    () async {
      final harness = SalaHarness()
        ..playback.length = const Duration(seconds: 10);
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);

      await it.sala.goConversa(pericope: 'P01');
      await waitFor('a sala abrir', () => it.estado.sessionId != null);
      it.sala.goEnsaio();
      await gravarUmaParteDoEnsaio(it);
      it.sala.startRetro();
      await waitFor(
        'a tradução começar a tocar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing,
      );

      harness.playback.at = const Duration(seconds: 4);
      it.sala.ouvirGravacao();
      await waitFor('a gravação parar', () => !it.estado.btClipRodando);
      it.sala.ouvirGravacao();
      await waitFor('a gravação voltar', () => it.estado.btClipRodando);
      harness.playback.finishPlayback();
      await waitFor('a gravação acabar', () => it.estado.btClipEnded);
      await it.sala.finishBackTranslation();
      await waitFor(
        'a sala voltar do veredito',
        () => it.estado.btPhase != BtPhase.thinking,
      );

      expect(
        harness.room.playedByTakeSent.last,
        [
          {
            'take_id': harness.room.takeIds.single,
            'played_ranges': [
              [0, 10000],
            ],
            'clip_duration_ms': 10000,
          },
        ],
        reason:
            'a equipe segurou o ensaio uma vez e deixou correr até o fim: '
            'esquecer de reabrir a escuta ao soltar relata a parte até a pausa e o '
            'portão nunca mais deixa a passagem sair',
      );
    },
  );
}
