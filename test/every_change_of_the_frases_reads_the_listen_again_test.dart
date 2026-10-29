import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _umTrechoApontado() async {
  final it = await umEnsaioContadoInteiro(
    partesDoEnsaio,
    numaSala: SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictHasFinding = true
      ..room.verdictFindingPlace = 0,
  );
  await waitFor('o ensaio inteiro terminar', () => it.estado.btClipEnded);
  await pedirOVeredito(it);
  await waitFor(
    'o analista apontar um trecho',
    () => it.estado.btFindingTrecho != null,
  );
  return it;
}

void _aSalaContaOTrechoDaSegunda(Sala it) => it.harness.room
  ..listeningUnheardTakeIds = const []
  ..listeningFixedLine = 'N2'
  ..listeningUntranslated = [
    UntranslatedPart(
      takeId: it.partes[1].takeId!,
      scene: 2,
      from: const Duration(milliseconds: 3000),
    ),
  ];

Future<({int linhas, int tocadas})> _voltarAConferirSemASala(Sala it) async {
  it.harness.room.reachable = false;
  it.sala.goEnsaio();
  await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
  final linhas = it.harness.voice.fixedLines.length;
  final tocadas = it.harness.playback.played.length;
  it.sala.startRetro();
  await waitFor(
    'a volta tocar alguma coisa',
    () => it.harness.playback.played.length > tocadas,
  );
  return (linhas: linhas, tocadas: tocadas);
}

void main() {
  test('a stretch told again leaves the room asked what is left, so a return '
      'out of its reach says the stretch it names now, not nothing', () async {
    final it = await _umTrechoApontado();
    await escolherTraduzirDeNovo(it);
    _aSalaContaOTrechoDaSegunda(it);
    await entregarAPonte(it);

    final antes = await _voltarAConferirSemASala(it);

    expect(
      it.harness.voice.fixedLines.skip(antes.linhas),
      [('N2', testLanguage)],
      reason:
          'o trecho contado de novo não perguntava nada à sala, e a volta sem '
          'rede seguia a última resposta, de antes dele',
    );
    expect(it.harness.playback.played.last, it.partes[1].path);
    expect(
      it.harness.playback.playedFrom.last,
      const Duration(milliseconds: 3000),
    );
  });

  test(
    'a translation started over asks the room again, and makes good the ask '
    'a told stretch lost, so a return out of reach follows the room now',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a tradução começar a tocar a primeira parte',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing,
      );
      it.harness.room.listeningUnheardTakeIds = const [];
      await traduzirUmTrecho(it, const Duration(seconds: 3));
      it.harness.room.failListeningWith = const NetworkFailed('sem rede');
      await traduzirUmTrecho(it, const Duration(seconds: 6));
      it.harness.room.failListeningWith = null;
      _aSalaContaOTrechoDaSegunda(it);

      it.sala.recomecarATraducao();
      await settle(const Duration(milliseconds: 700));
      it.sala.recomecarATraducao();
      await waitFor('a tradução recomeçar', () => it.estado.btRecomecada);
      it.harness.room.reachable = false;
      await waitFor(
        'a voz pedir que contem de novo',
        () =>
            it.harness.voice.fixedLines.contains(('P1', testLanguage)) &&
            it.estado.btPhase == BtPhase.playing,
      );

      final antes = await _voltarAConferirSemASala(it);

      expect(
        it.harness.voice.fixedLines.skip(antes.linhas),
        [('N2', testLanguage)],
        reason:
            'o recomeço não perguntava nada à sala, e a volta sem rede seguia a '
            'resposta de antes do trecho cuja pergunta caiu',
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(milliseconds: 3000),
      );
    },
  );
}
