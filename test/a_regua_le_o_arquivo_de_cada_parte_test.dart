import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// Where the tablet writes the rebuilt passage when it fetches it. Named before the fetch
/// because how long that file is has to be arranged before the room measures it, and
/// through the recorder's own naming so a change to it cannot leave this arrangement
/// silently pointing at a file nobody ever writes.
String _arquivoDaComposta(Sala it) =>
    it.harness.recorder.aFile('composta-$composta').path;

/// The rehearsal told back end to end, standing at a finding on the stretch of part two.
Future<Sala> _aSalaNoAchadoDaSegundaParte({Duration? tetoDaEspera}) async {
  final it = await umEnsaioDeTresPartesContadoInteiro(
    compoeEm: composta,
    tetoDaEspera: tetoDaEspera,
  );
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.addition
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  return it;
}

/// The long way, both stations: the mother tongue recorded again, then the telling redone
/// over it. The room rebuilds the part around it and the part becomes that recording.
///
/// [antesDoVeredito] runs after the rebuilt passage has been swapped in and before the
/// room asks what the mend was worth, which is the one seam between the two.
Future<void> _consertarPeloCaminhoLongo(
  Sala it, {
  void Function()? antesDoVeredito,
}) async {
  final semArquivo = it.harness.room.replacesSemArquivo.length;
  it.sala.regravarAVozMaterna();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir na materna',
    () => it.estado.voice == VoiceState.listening,
  );
  it.sala.retroTap();
  await waitFor(
    'a voz materna nova substituir o trecho',
    () => it.harness.room.replacesSemArquivo.length == semArquivo + 1,
  );
  await waitFor(
    'a segunda estação abrir sozinha',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.harness.room
    ..verdictFinding = null
    ..verdictFindingPlace = null;
  antesDoVeredito?.call();
  final pontes = it.harness.room.replacesAsked.length;
  it.sala.retroTap();
  await waitFor(
    'a ponte nova substituir o trecho',
    () => it.harness.room.replacesAsked.length == pontes + 1,
  );
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// The tablet closed and opened again on the same passage.
Future<void> _reabrir(Sala it) async {
  it.container.dispose();
  it.harness.playback.played.clear();
  it.harness.playback.measurements.clear();
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.abrirEscolha();
  await waitFor(
    'a roda dizer que esta passagem tem trabalho parado',
    () => it.estado.comecadas.contains('P01'),
  );
  await it.sala.goConversa(pericope: 'P01');
  await waitFor(
    'a tradução ser retomada e voltar ao ar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.played.isNotEmpty,
  );
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

void main() {
  test('depois do conserto a régua lê o tamanho da composta', () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    it.harness.playback.lengths[_arquivoDaComposta(it)] = aComposta;

    await _consertarPeloCaminhoLongo(it);

    expect(parteDois(it).takeId, composta,
        reason: 'o caminho longo compõe uma gravação nova para a parte, e é '
            'ela que passa a ser a parte');
    expect(it.estado.btFimDasPartesMs, [10000, 15000, 27000],
        reason: 'a equipe que não lê vê no colar onde cada parte acaba. Com o '
            'tamanho do arquivo que a composta substituiu, as faixas depois '
            'dela ficam três segundos à frente do som, e a regra que atravessa '
            'para a parte seguinte lê o arquivo novo enquanto o colar lê o '
            'velho');
  });

  test('cair numa parte além da régua mede as anteriores primeiro', () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    final terceira = it.partes[2].takeId!;
    // The rebuilt passage lands on a tablet that cannot measure it yet: the room has a
    // branch for a file the player answers nothing about, and the ruler is short by that
    // part until something measures it.
    it.harness.playback.semMedida.add(_arquivoDaComposta(it));

    await _consertarPeloCaminhoLongo(it, antesDoVeredito: () {
      it.harness.playback
        ..semMedida.remove(_arquivoDaComposta(it))
        ..lengths[_arquivoDaComposta(it)] = aComposta;
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira];
    });

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
    // The rebuilt passage this tablet never manages to measure: the ruler stays short by
    // that part however far the team listens, which is the hole the landing jumps over.
    it.harness.playback.semMedida.add(_arquivoDaComposta(it));

    await _consertarPeloCaminhoLongo(it, antesDoVeredito: () {
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira];
    });
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
    // The rebuilt passage goes in unmeasured, so there is a part left for a landing to
    // measure — and a name that leads nowhere must not make the team wait for it.
    it.harness.playback.semMedida.add(_arquivoDaComposta(it));

    late int medicoes;
    await _consertarPeloCaminhoLongo(it, antesDoVeredito: () {
      medicoes = it.harness.playback.measurements.length;
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = ['ninguem'];
    });

    expect(it.estado.needsPerson, isTrue);
    expect(it.harness.playback.measurements.length, medicoes,
        reason: 'o nome não vira parte nenhuma, então não há para onde levar '
            'a equipe: medir o ensaio inteiro antes de descobrir isso só a faz '
            'esperar pela pessoa que já era para ter sido chamada');
  });

  test('uma medida que nunca responde no pouso chama uma pessoa', () async {
    final it = await _aSalaNoAchadoDaSegundaParte(
      tetoDaEspera: const Duration(seconds: 2),
    );
    final terceira = it.partes[2].takeId!;
    it.harness.playback.semMedida.add(_arquivoDaComposta(it));

    await _consertarPeloCaminhoLongo(it, antesDoVeredito: () {
      it.harness.playback
        ..semMedida.remove(_arquivoDaComposta(it))
        ..holdNextMeasurement();
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira];
    });

    expect(it.estado.needsPerson, isTrue,
        reason: 'medir espera o player, e a sala que espera sem dizer que está '
            'pensando não é vigiada por ninguém: uma medida que nunca volta '
            'deixava a equipe diante de um giro parado sem chamar ninguém');
    it.harness.playback.finishHeldMeasurement();
  });

  test('a composta que chega depois do chão não contado não deixa o tamanho '
      'velho', () async {
    final it = await _aSalaNoAchadoDaSegundaParte();
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');

    await _consertarPeloCaminhoLongo(it);

    expect(parteDois(it).takeId, isNot(composta),
        reason: 'esta sessão fechou sem nunca alcançar a passagem composta');
    it.harness.room.failClipWith = null;
    it.harness.playback.lengths[_arquivoDaComposta(it)] = aComposta;
    final oArquivoVelho = parteDois(it).path;

    await _reabrir(it);
    await waitFor(
      'a sala buscar a passagem composta que ela não tem',
      () => parteDois(it).takeId == composta,
    );
    await _ouvirAParteNoAr(it, partesDoEnsaio[2]);

    final medicoes = it.harness.playback.measurements;
    expect(medicoes, contains(oArquivoVelho),
        reason: 'sem a medida do arquivo velho não há ordem nenhuma para '
            'comparar, e a comparação abaixo passaria sozinha');
    expect(medicoes.indexOf(oArquivoVelho),
        lessThan(medicoes.indexOf(_arquivoDaComposta(it))),
        reason: 'esta é a ordem que a retomada toma sozinha, e é a que perde: '
            'o chão não contado mede o arquivo velho antes de a composta '
            'chegar, então quem mede primeiro não pode ser quem decide');
    expect(it.estado.btFimDasPartesMs, [10000, 15000, 27000],
        reason: 'na retomada as duas tarefas correm soltas: o chão não contado '
            'mede as partes que a equipe já contou e a composta chega depois. '
            'Quem mede primeiro não pode decidir o que o colar desenha, senão '
            'a parte refeita fica com o tamanho do arquivo que ela substituiu');
  });
}
