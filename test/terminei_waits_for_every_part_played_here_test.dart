import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show intoTheRecordingHome, settle;
import 'um_ensaio_de_tres_partes.dart';

const _duasPartes = [Duration(seconds: 10), Duration(seconds: 8)];

Future<Sala> _ouvidaInteiraNumaVidaAnterior() async {
  final it = await umEnsaioGravado(_duasPartes);
  it.harness.room.listeningUnheardTakeIds = const [];
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  for (final quanto in _duasPartes) {
    await ouvirAteOFim(it, quanto);
  }
  await settle();

  it.container.invalidate(salaSessionProvider);
  it.container.read(salaSessionProvider);
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
  await waitFor(
    'a mesma sessão voltar à casa',
    () => it.estado.stage == SalaStage.ensaio && it.partes.length == 2,
  );
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        !it.estado.awaitingTheGuide,
  );
  await settle();
  return it;
}

void main() {
  test(
    'a passage the room counted heard in an earlier life keeps terminei '
    'dark after a frase told here, until every part has played here',
    () async {
      final it = await _ouvidaInteiraNumaVidaAnterior();

      await traduzirUmTrecho(it, const Duration(seconds: 4));
      await waitFor(
        'a equipe voltar ao círculo',
        () => it.estado.btPhase == BtPhase.playing,
      );
      await settle();

      expect(it.estado.btOuvidaInteira, isTrue);
      expect(
        it.estado.canAdvanceToTheVerdict,
        isFalse,
        reason:
            'a contagem da sala, feita numa visita anterior, acendia o terminei '
            'com uma frase contada e o resto da gravação nunca tocado aqui',
      );

      await ouvirAteOFim(it, _duasPartes[0]);
      await settle();
      expect(it.estado.canAdvanceToTheVerdict, isFalse);

      await ouvirAteOFim(it, _duasPartes[1]);
      await settle();
      expect(it.estado.canAdvanceToTheVerdict, isTrue);
    },
  );

  test('a part paused a second short of its end is still to hear here, and '
      'one paused within her 750 ms slack is not', () async {
    final it = await _ouvidaInteiraNumaVidaAnterior();
    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await ouvirAteOFim(it, _duasPartes[0]);
    await theClipOpens(it.harness);
    await waitFor('a segunda parte tocar', () => it.harness.playback.sounding);

    it.harness.playback.at = _duasPartes[1] - const Duration(seconds: 1);
    it.sala.ouvirGravacao();
    await waitFor('a parte pausar', () => !it.harness.playback.sounding);
    await settle();
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'um segundo da parte por ouvir acendia o terminei, fora da folga '
          'de 750 ms que a dela dá ao tocador',
    );

    it.sala.ouvirGravacao();
    await waitFor('a parte seguir', () => it.harness.playback.sounding);
    it.harness.playback.at = _duasPartes[1] - const Duration(milliseconds: 500);
    it.sala.ouvirGravacao();
    await waitFor(
      'a parte pausar de novo',
      () => !it.harness.playback.sounding,
    );
    await settle();
    expect(
      it.estado.canAdvanceToTheVerdict,
      isTrue,
      reason:
          'meio segundo da parte por ouvir deixava o terminei apagado, dentro '
          'da folga que a dela dá',
    );
  });
}
