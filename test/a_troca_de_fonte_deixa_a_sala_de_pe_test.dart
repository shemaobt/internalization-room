import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'tocar_vira_pausar_test.dart' show harnessApontando, pumpAoApontado;
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test(
    'o achado diz a língua materna, depois a tradução, e a sala fica quieta',
    () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState estado() => container.read(salaSessionProvider);
      final trecho = estado().btFindingTrecho!;

      sala.ouvirOTrechoEATraducao();
      await waitFor('a língua materna soar', () => harness.playback.sounding);
      expect(
        harness.playback.ranges.last,
        '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
      );

      harness.playback.finishPlayback();
      await waitFor(
        'a tradução soar',
        () =>
            harness.playback.sounding &&
            harness.playback.played.last == trecho.retroPath,
      );

      harness.playback.finishPlayback();
      await settle();

      expect(harness.playback.sounding, isFalse);
      expect(estado().btTrechoTocando, isFalse);
      expect(estado().btRetroTocando, isFalse);
      expect(estado().needsPerson, isFalse);

      final faladas = harness.voice.played.length;
      sala.retroTap();
      await settle();
      expect(
        harness.voice.played.length,
        faladas + 1,
        reason: 'o círculo responde ao toque: a sala diz o achado de novo',
      );
    },
  );

  test(
    'a parte gravada de novo toca do seu arquivo, acaba, e o círculo grava',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true
        ..verdictFindingPlace = 1;
      await pedirOVeredito(it);
      expect(it.estado.btPhase, BtPhase.findings);

      it.sala.gravarAParteDeNovo();
      await regravarAParte(it, 1);
      final nova = it.partes[1].path;

      it.sala.startRetro();
      await waitFor(
        'a parte nova soar',
        () =>
            it.harness.playback.sounding &&
            it.harness.playback.played.last == nova,
      );
      expect(it.estado.btParte, 1);

      it.harness.playback.finishPlayback();
      await waitFor(
        'a parte acabar de tocar',
        () => !it.estado.btClipRodando && !it.harness.playback.sounding,
      );

      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      expect(it.estado.needsPerson, isFalse);
    },
  );
}
