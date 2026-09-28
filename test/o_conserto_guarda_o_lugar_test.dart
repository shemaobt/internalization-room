import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

const _umaParte = Duration(seconds: 30);

/// The stretch at one place in the row, whatever the room has renamed it to.
///
/// Mending mints a new name every time, so a stretch cannot be followed by its name
/// across a correction. Its place is what stays put, and it is what the team sees.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

/// A rehearsal of two parts told back in three stretches — one out of the first part, two
/// out of the second — standing at the analyst's finding on the second stretch.
///
/// The pointed stretch is deliberately out of the *second* part: its place on the cord is
/// part 1, so a mend that lands it on part 0 is as wrong as one that loses it altogether,
/// and only reading the real part number can tell those apart.
Future<Sala> _aSalaNaPergunta() async {
  final harness = SalaHarness()
    ..playback.length = _umaParte
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = 1;
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
  test('a ponte recém-gravada é a que se ouve, no caminho curto', () async {
    final it = await _aSalaNaPergunta();
    final aPonteAntiga = _no(it.container, 1).retroPath;
    expect(aPonteAntiga, isNotNull);

    await escolherTraduzirDeNovo(it);
    await entregarAPonte(it);
    final aPonteNova = it.harness.recorder.lastPath;

    expect(aPonteNova, isNot(aPonteAntiga));
    expect(
      _no(it.container, 1).retroPath,
      aPonteNova,
      reason:
          'o botão de ouvir a ponte toca o arquivo do trecho, então ele '
          'tem de ser o que a equipe acabou de dizer — tocar o anterior '
          'devolve a explicação que o analista já recusou',
    );
    expect(
      it.estado.btFindingTrecho?.retroPath,
      aPonteNova,
      reason:
          'e é por este ponteiro que a tela decide se o botão acende, '
          'enquanto o achado estiver aberto',
    );
  });

  test('a primeira contagem continua guardando o que foi gravado', () async {
    final it = await _aSalaNaPergunta();

    for (final lugar in [0, 1, 2]) {
      expect(
        _no(it.container, lugar).retroPath,
        isNotNull,
        reason:
            'todo trecho contado tem aqui a cópia do que a equipe disse '
            'na língua-ponte',
      );
    }
  });

  test(
    'os trechos vizinhos não se mexem, nem depois de dois consertos',
    () async {
      final it = await _aSalaNaPergunta();
      final vizinhos = [_no(it.container, 0), _no(it.container, 2)];

      await escolherTraduzirDeNovo(it);
      await entregarAPonte(it);
      await escolherTraduzirDeNovo(it);
      await entregarAPonte(it);

      for (final (onde, antes) in [(0, vizinhos[0]), (2, vizinhos[1])]) {
        final depois = _no(it.container, onde);
        expect(
          [depois.parte, depois.retroPath, depois.from, depois.to],
          [antes.parte, antes.retroPath, antes.from, antes.to],
          reason:
              'correção é localizada: consertar um trecho não pode mover nem '
              'emudecer os outros dois',
        );
      }
    },
  );
}
