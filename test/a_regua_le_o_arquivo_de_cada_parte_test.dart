import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// How long the recording that takes part two's place is: shorter than the one it
/// replaces, so a ruler drawn with the old length shows.
const _aParteNova = Duration(seconds: 5);

/// The rehearsal told back end to end, standing at a finding on the stretch of part two.
Future<Sala> _aSalaNoAchadoDaSegundaParte({Duration? tetoDaEspera}) async {
  final it = await umEnsaioDeTresPartesContadoInteiro(tetoDaEspera: tetoDaEspera);
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.addition
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
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.ensaioTap();
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

/// What the room answers *terminei* with once the part was recorded again: a refusal
/// naming [naoOuvida], and no finding.
void _aSalaVaiRecusar(Sala it, String naoOuvida) {
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = null
    ..verdictFindingPlace = null
    ..verdictUnheardTakeIds = [naoOuvida];
}

/// Carry the part in the air to its end, the way the tablet measures one.
Future<void> _ouvirAParteNoAr(Sala it, Duration quanto) async {
  it.harness.playback.length = quanto;
  it.harness.playback.at = quanto;
  it.harness.playback.finishPlayback();
  await waitFor(
    'a parte terminar',
    () => it.estado.btParteFronteira || it.estado.btClipEnded,
  );
}

/// Tell the part in the air back whole.
///
/// The microphone is waited for by the recorder having actually opened, not by the phase
/// alone: the phase is set before the capture is asked for, and a tap that lands in that
/// gap stops a recording that never started.
Future<void> _contarAParteNoAr(Sala it, Duration quanto) async {
  final antes = it.estado.btTrechos.length;
  final capturas = it.harness.recorder.captures;
  it.harness.playback
    ..length = quanto
    ..at = quanto;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () =>
        it.estado.btPhase == BtPhase.capturing &&
        it.harness.recorder.captures > capturas,
  );

  it.sala.retroTap();
  await waitFor(
    'o trecho traduzido entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
}

/// Back into the telling-back over the part that was recorded again, told whole, and on
/// to the end of the rehearsal — which is what lights *terminei* again.
Future<void> _contarDeNovoAParteRefeita(Sala it, Duration quanto) async {
  it.sala.startRetro();
  await waitFor(
    'a tradução recomeçar na parte refeita',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  await _contarAParteNoAr(it, quanto);
  await _ouvirAParteNoAr(it, quanto);
  it.sala.proximaParte();
  await waitFor(
    'a parte seguinte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
  await _ouvirAParteNoAr(it, partesDoEnsaio[2]);
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

    expect(it.estado.btFimDasPartesMs, [10000, 18000, 30000],
        reason: 'o colar desenha o ensaio inteiro desde o primeiro quadro: '
            'uma régua que só cresce à medida que as partes acabam esconde as '
            'faixas de tudo o que vem depois da parte no ar');
    expect(it.harness.playback.played.last, it.partes[0].path,
        reason: 'e a equipe continua a entrar pela primeira parte');
  });

  test('uma parte que o tablet não mede acaba a régua ali', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.harness.playback.semMedida.add(it.partes[2].path);

    await _entrarNaTraducao(it);

    expect(it.estado.btFimDasPartesMs, [10000, 18000],
        reason: 'uma parte que ninguém consegue medir acaba o cordão em vez de '
            'o alongar por um palpite');
    expect(it.estado.needsPerson, isFalse,
        reason: 'e não é motivo para parar a equipe: o desenho é que fica '
            'curto, o trabalho não');
    expect(it.harness.playback.played.last, it.partes[0].path);
  });

  test('cair numa parte além da régua mede as anteriores primeiro', () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    final terceira = it.partes[2].takeId!;
    // The part recorded again lands on a tablet that cannot measure it yet: the room has
    // a branch for a file the player answers nothing about, and the ruler is short by
    // that part until something measures it.
    late String aParteNova;
    await _regravarASegundaParte(it, antesDeGuardar: (arquivo) {
      aParteNova = arquivo;
      it.harness.playback.semMedida.add(arquivo);
    });
    it.harness.playback
      ..semMedida.remove(aParteNova)
      ..lengths[aParteNova] = _aParteNova;
    _aSalaVaiRecusar(it, terceira);

    await _contarDeNovoAParteRefeita(it, _aParteNova);
    await pedirOVeredito(it);

    expect(it.harness.playback.played.last, it.partes[2].path,
        reason: 'a recusa nomeia a terceira parte e a equipe cai nela');
    expect(it.estado.btOuvidoMs, 15000,
        reason: 'a cabeça de leitura senta onde a terceira parte começa, que é '
            'a soma das duas anteriores — e a segunda delas só tem tamanho '
            'porque o pouso a mediu no caminho; sem isso o colar põe a equipe '
            'cinco segundos atrás de onde o som está');
  });

  test('cair na última parte com um buraco atrás não oferece travessia nenhuma',
      () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    final terceira = it.partes[2].takeId!;
    // The part this tablet never manages to measure: the ruler stays short by it however
    // far the team listens, which is the hole the landing jumps over.
    await _regravarASegundaParte(it, antesDeGuardar: (arquivo) {
      it.harness.playback.semMedida.add(arquivo);
    });
    _aSalaVaiRecusar(it, terceira);

    await _contarDeNovoAParteRefeita(it, _aParteNova);
    await pedirOVeredito(it);
    await _ouvirAParteNoAr(it, partesDoEnsaio[2]);

    expect(it.estado.btParteFronteira, isFalse,
        reason: 'não há parte nenhuma depois da última: oferecer a travessia '
            'aqui manda a equipe para uma linha que não existe, e o toque que '
            'ela oferece rebenta');
    expect(it.estado.canFinishBackTranslation, isTrue,
        reason: 'a equipe ouviu a parte que o servidor pediu até o fim; que o '
            'colar não saiba desenhar uma parte de trás é assunto do desenho, '
            'e não do que a equipe pode apertar — e quem julga o relato é o '
            'servidor');
  });

  test('um id que nenhuma parte tem chama a pessoa antes de medir nada',
      () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    // The part recorded again goes in unmeasured, so there is a part left for a landing
    // to measure — and a name that leads nowhere must not make the team wait for it.
    await _regravarASegundaParte(it, antesDeGuardar: (arquivo) {
      it.harness.playback.semMedida.add(arquivo);
    });
    _aSalaVaiRecusar(it, 'ninguem');

    await _contarDeNovoAParteRefeita(it, _aParteNova);
    final medicoes = it.harness.playback.measurements.length;
    await pedirOVeredito(it);

    expect(it.estado.needsPerson, isTrue);
    expect(it.harness.playback.measurements.length, medicoes,
        reason: 'o nome não vira parte nenhuma, então não há para onde levar '
            'a equipe: medir o ensaio inteiro antes de descobrir isso só a faz '
            'esperar pela pessoa que já era para ter sido chamada');
  });
}
