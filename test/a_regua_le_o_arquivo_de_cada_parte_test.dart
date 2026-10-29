import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// The rehearsal told back end to end, standing at a finding on the stretch of part two.
Future<Sala> _aSalaNoAchadoDaSegundaParte({Duration? tetoDaEspera}) async {
  final it = await umEnsaioDeTresPartesContadoInteiro(
    tetoDaEspera: tetoDaEspera,
  );
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  return it;
}

/// The long way: back to the rehearsal and part two recorded again in its own place.
///
/// [antesDeGuardar] runs with the new recording already on the tablet and not yet kept,
/// which is the one moment a test can say what the player will answer about a file the
/// room has never seen. The room measures the new part the instant the team keeps it.
Future<void> _regravarASegundaParte(
  Sala it, {
  void Function(String arquivo)? antesDeGuardar,
}) async {
  it.sala.gravarAParteDeNovo();
  await waitFor(
    'a sala voltar ao ensaio',
    () => it.estado.stage == SalaStage.ensaio,
  );
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação da parte começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.gravarACena(2);
  await waitFor(
    'a gravação da parte terminar',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  antesDeGuardar?.call(it.harness.recorder.lastPath!);
  final antiga = it.partes[1].path;
  it.sala.takeKeep();
  await waitFor(
    'a sala nomear a gravação que tomou o lugar da parte 2',
    () => it.partes[1].path != antiga && it.partes[1].takeId != null,
  );
}

/// Into the back-translation from a rehearsal nobody has told back yet, standing with the
/// first part in the air.
Future<void> _entrarNaTraducao(Sala it) async {
  it.sala.startRetro();
  await waitFor(
    'a primeira parte entrar no ar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.estado.btClipRodando,
  );
}

void main() {
  test('a régua traz as três partes antes de a primeira tocar', () async {
    final it = await umEnsaioDeTresPartesGravado();

    await _entrarNaTraducao(it);

    expect(
      it.estado.btFimDasPartesMs,
      [10000, 18000, 30000],
      reason:
          'o colar desenha o ensaio inteiro desde o primeiro quadro: '
          'uma régua que só cresce à medida que as partes acabam esconde as '
          'faixas de tudo o que vem depois da parte no ar',
    );
    expect(
      it.harness.playback.played.last,
      it.partes[0].path,
      reason: 'e a equipe continua a entrar pela primeira parte',
    );
  });

  test('uma parte que o tablet não mede acaba a régua ali', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.harness.playback.semMedida.add(it.partes[2].path);

    await _entrarNaTraducao(it);

    expect(
      it.estado.btFimDasPartesMs,
      [10000, 18000],
      reason:
          'uma parte que ninguém consegue medir acaba o cordão em vez de '
          'o alongar por um palpite',
    );
    expect(
      it.estado.needsPerson,
      isFalse,
      reason:
          'e não é motivo para parar a equipe: o desenho é que fica '
          'curto, o trabalho não',
    );
    expect(it.harness.playback.played.last, it.partes[0].path);
  });

  test(
    'uma parte medida em zero acaba a régua como uma que não se mede',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.harness.playback.lengths[it.partes[2].path] = Duration.zero;

      await _entrarNaTraducao(it);

      expect(
        it.estado.btFimDasPartesMs,
        [10000, 18000],
        reason:
            'zero não é uma medida, é o player sem resposta sobre o '
            'arquivo: escrito na régua, ele espreme a parte a nada em vez de '
            'acabar o cordão ali',
      );
    },
  );

  test('um gesto enquanto a sala mede não abre o microfone', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.harness.playback.holdNextMeasurement();
    final capturas = it.harness.recorder.captures;

    it.sala.startRetro();
    await waitFor(
      'a sala entrar na espera da medição',
      () => it.estado.btPhase == BtPhase.thinking,
    );
    it.sala.retroTap();
    it.sala.retroTap();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      it.estado.btPhase,
      BtPhase.thinking,
      reason:
          'a espera é o estado honesto da sala enquanto o player mede, e '
          'agora ela acontece em toda entrada',
    );
    expect(
      it.harness.recorder.captures,
      capturas,
      reason:
          'um corte que caísse dentro da espera abria o microfone sobre '
          'um clipe a começar, com o cursor no zero',
    );
    expect(
      it.harness.playback.played,
      isEmpty,
      reason: 'e nada entra no ar antes de a régua estar medida',
    );

    it.harness.playback.finishHeldMeasurement();
    await waitFor(
      'a primeira parte entrar no ar',
      () => it.estado.btClipRodando,
    );
    expect(
      it.harness.playback.played.last,
      it.partes[0].path,
      reason: 'acabada a medição, a parte toca como sempre tocou',
    );
  });

  test('a parte regravada medida em zero acaba a régua ali', () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    await _regravarASegundaParte(
      it,
      antesDeGuardar: (arquivo) {
        it.harness.playback.lengths[arquivo] = Duration.zero;
      },
    );

    expect(
      it.estado.btFimDasPartesMs,
      [10000],
      reason:
          'a parte 2 é medida no instante em que a equipe a guarda, e um '
          'zero ali não é uma parte sem duração: é o player sem resposta '
          'sobre um arquivo acabado de escrever',
    );
  });
}
