import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

const _umaParte = Duration(seconds: 30);

/// The stretch at one place in the row, whatever the room has renamed it to.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

/// A rehearsal of two parts told back in three stretches — one out of the first part, two
/// out of the second — standing at the analyst's finding on the stretch at [lugar].
Future<Sala> _aSalaNaPergunta({int lugar = 1}) async {
  final harness = SalaHarness()
    ..playback.length = _umaParte
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = lugar;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);

  await it.sala.goConversa();
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  await gravarUmaParte(it);
  await gravarUmaParte(it);
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  await traduzirUmTrecho(it, const Duration(seconds: 10));
  harness.playback.finishPlayback();
  await waitFor('a primeira parte terminar', () => it.estado.btParteFronteira);
  it.sala.ouvirGravacao();
  await waitFor(
    'a segunda parte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
  await traduzirUmTrecho(it, const Duration(seconds: 5));
  await traduzirUmTrecho(it, const Duration(seconds: 12));
  harness.playback.finishPlayback();
  await waitFor('o ensaio inteiro terminar', () => it.estado.btClipEnded);

  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () =>
        it.estado.btPhase == BtPhase.findings &&
        it.estado.btFindingTrecho != null,
  );
  return it;
}

void main() {
  test(
    'os trechos vizinhos, sem conserto, continuam tocando a parte original',
    () async {
      for (final lugar in [0, 2]) {
        final it = await _aSalaNaPergunta(lugar: lugar);
        final trecho = it.estado.btFindingTrecho!;
        final caminhoDaParte = it.estado.partes[trecho.parte].path;

        it.sala.ouvirOTrechoEATraducao();
        await waitFor(
          'o trecho apontado estar tocando',
          () => it.estado.btTrechoTocando,
        );

        expect(
          it.harness.playback.played.last,
          caminhoDaParte,
          reason:
              'o trecho no lugar $lugar não foi consertado; o arquivo '
              'continua sendo o da parte que sempre foi',
        );
        expect(
          it.harness.playback.ranges.last,
          '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
        );
      }
    },
  );

  test(
    'o caminho curto não troca a materna nem os limites do trecho',
    () async {
      final it = await _aSalaNaPergunta();
      final antes = _no(it.container, 1);
      final parteAntes = it.estado.partes[antes.parte].path;

      it.sala.traduzirDeNovoEmPortugues();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir para traduzir de novo',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await entregarAPonte(it);

      final depois = _no(it.container, 1);
      expect(depois.from, antes.from);
      expect(depois.to, antes.to);

      it.harness.playback.played.clear();
      it.sala.ouvirOTrechoEATraducao();
      await waitFor(
        'o trecho apontado estar tocando',
        () => it.estado.btTrechoTocando,
      );

      expect(
        it.harness.playback.played.last,
        parteAntes,
        reason:
            'o caminho curto não regrava a materna; o áudio continua '
            'sendo o da parte, do jeito que sempre foi',
      );
    },
  );
}
