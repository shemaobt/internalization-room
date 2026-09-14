import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';

import 'fakes.dart';

/// The rehearsal: a first part of twenty seconds told back in two stretches, a second of
/// fifteen told back whole.
const _primeiraParte = Duration(seconds: 20);
const _segundaParte = Duration(seconds: 15);

/// The mother tongue of the first stretch, recorded again. Three seconds longer than the
/// six it replaces, so the arithmetic the room does on every stretch after it has a
/// difference to show.
const _aMaterna = Duration(seconds: 9);

/// The name the room gives the recording it rebuilds out of the two, and how long that
/// recording is: the first part with six of its seconds replaced by nine.
const _composta = 'C';
const _aComposta = Duration(seconds: 23);

class _Sala {
  final SalaHarness harness;
  ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  KeptTake get parteUm => estado.keptTakes.firstWhere(
        (take) => take.scopeId == KeptScope.parte(1),
      );
}

Trecho _no(_Sala it, int lugar) => it.estado.btTrechos[lugar];

/// The band the cord draws for one stretch, on the whole rehearsal. Asked of the cord's
/// own rule rather than copied, which is the question the team asks of the necklace.
(int, int)? _naFaixa(SalaSessionState state, int lugar) => cordSpanMs(
      trecho: state.btTrechos[lugar],
      fimDasPartes: state.btFimDasPartesMs,
    );

Future<void> _gravarUmaParte(_Sala it) async {
  final antes = it.estado.keptTakes.length;
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
  it.sala.takeKeep();
  await waitFor('a sala nomear a parte nova', () {
    final takes = it.estado.keptTakes;
    return takes.length == antes + 1 && takes.last.takeId != null;
  });
}

Future<void> _traduzirUmTrecho(_Sala it, Duration em) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.at = em;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'o trecho contado entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
}

Future<void> _atravessarAFronteira(_Sala it) async {
  it.harness.playback.finishPlayback();
  await waitFor('a parte terminar', () => it.estado.btParteFronteira);
  it.sala.proximaParte();
  await waitFor(
    'a parte seguinte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
}

/// Play the rehearsal out to its end, crossing whatever part boundaries are left, and ask
/// the room what the telling-back was worth.
Future<void> _pedirOVeredito(_Sala it) async {
  while (!it.estado.btClipEnded) {
    it.harness.playback.finishPlayback();
    await waitFor(
      'a parte terminar',
      () => it.estado.btParteFronteira || it.estado.btClipEnded,
    );
    if (it.estado.btClipEnded) break;
    it.sala.proximaParte();
    await waitFor(
      'a parte seguinte entrar no ar',
      () => !it.estado.btParteFronteira,
    );
  }
  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () =>
        it.estado.btPhase == BtPhase.findings &&
        it.estado.btFindingTrecho != null,
  );
}

/// A rehearsal of two parts told back in three stretches, standing at a finding on the
/// stretch at [apontado].
///
/// [ateOnde] is how far into the first part the second stretch reaches. It stops short of
/// the part's end only where the test needs ground nobody has told back yet — the room
/// steps over a part told to its end, and there is no next cut to make in one.
Future<_Sala> _aSalaNaPergunta({
  required int apontado,
  Duration ateOnde = _primeiraParte,
}) async {
  final harness = SalaHarness()
    ..playback.length = _primeiraParte
    ..playback.measured = _aMaterna
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = apontado
    ..room.composesInto = _composta;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  await _gravarUmaParte(it);
  await _gravarUmaParte(it);
  final partes = it.estado.keptTakes;
  harness.playback.lengths[partes[0].path] = _primeiraParte;
  harness.playback.lengths[partes[1].path] = _segundaParte;

  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  await _traduzirUmTrecho(it, const Duration(seconds: 6));
  await _traduzirUmTrecho(it, ateOnde);
  await _atravessarAFronteira(it);
  await _traduzirUmTrecho(it, _segundaParte);
  await _pedirOVeredito(it);
  return it;
}

/// The long way, both stations: the mother tongue recorded again, then the telling redone
/// over it.
///
/// Answers with the path of the mother tongue's own recording — the one audio a stretch
/// this mend touches can always fall back to, whether or not the composed passage it asks
/// for ever reaches this tablet.
Future<String> _consertarPeloCaminhoLongo(_Sala it, {int apontaDepois = 0}) async {
  final semArquivo = it.harness.room.replacesSemArquivo.length;
  it.sala.regravarAVozMaterna();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir na materna',
    () => it.estado.voice == VoiceState.listening,
  );
  it.harness.room.verdictFindingPlace = apontaDepois;
  it.sala.retroTap();
  await waitFor(
    'a voz materna nova substituir o trecho',
    () => it.harness.room.replacesSemArquivo.length == semArquivo + 1,
  );
  final materna = it.harness.recorder.lastPath!;
  await waitFor(
    'a segunda estação abrir sozinha',
    () => it.estado.btPhase == BtPhase.capturing,
  );
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
  // The rebuilt passage is a file of its own length, and the room measures it the way it
  // measures every part: this is the double saying how long the file it just handed over
  // is, not the test arranging an outcome.
  if (it.parteUm.takeId == _composta) {
    it.harness.playback.lengths[it.parteUm.path] = _aComposta;
  }
  return materna;
}

/// The tablet closed and opened again on the same passage.
Future<void> _retomar(_Sala it) async {
  it.container.dispose();
  it.harness.playback.played.clear();
  it.harness.playback.ranges.clear();
  it.harness.room.clipsFetched.clear();
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

/// The URL the room was asked for the audio of one take, if it was asked at all.
bool _baixou(_Sala it, String takeId) => it.harness.room.clipsFetched.any(
      (url) => url.endsWith('/takes/$takeId/audio'),
    );

/// What the tablet is holding for the first part of the rehearsal.
List<int> _bytesDaParteUm(_Sala it) => File(it.parteUm.path).readAsBytesSync();

void main() {
  test('a parte é trocada no lugar pela passagem composta', () async {
    final it = await _aSalaNaPergunta(apontado: 0);

    await _consertarPeloCaminhoLongo(it);

    expect(it.parteUm.takeId, _composta,
        reason: 'a primeira parte do ensaio passa a ser a passagem que a sala '
            'compôs, no mesmo escopo: trocar de escopo mudaria o índice da '
            'parte, e todo trecho endereça a parte pelo índice');
    expect(
      _bytesDaParteUm(it),
      it.harness.room.takeAudio[_composta],
      reason: 'trocar o nome sem trazer o áudio deixa a parte apontando para '
          'um arquivo que é a gravação velha',
    );
    expect(_baixou(it, _composta), isTrue,
        reason: 'a passagem composta só existe no servidor até a sala pedi-la');
    expect(
      [
        it.estado.partes.length,
        it.estado.partes[0].takeId,
        it.estado.partes[1].takeId,
      ],
      [2, _composta, it.harness.room.takeIds[1]],
      reason: 'a composta ocupa o lugar da parte que ela refez; a segunda parte '
          'não foi tocada, e o ensaio continua tendo duas',
    );
  });

  test('todo trecho da parte mora na composta, e o lugar é o que toca', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    final terceiro = _no(it, 2);

    await _consertarPeloCaminhoLongo(it);

    expect(
      [
        for (final lugar in [0, 1])
          [
            _no(it, lugar).takeId,
            _no(it, lugar).parte,
            _no(it, lugar).from.inMilliseconds,
            _no(it, lugar).to.inMilliseconds,
          ],
      ],
      [
        [_composta, 0, 0, 9000],
        [_composta, 0, 9000, 23000],
      ],
      reason: 'a sala refez a gravação inteira em volta do conserto: o trecho '
          'corrigido dura os nove segundos da materna nova e o vizinho, que '
          'ninguém tocou, desliza os três segundos que a passagem cresceu',
    );
    for (final lugar in [0, 1]) {
      expect(
        [_no(it, lugar).lugarFrom, _no(it, lugar).lugarTo],
        [_no(it, lugar).from, _no(it, lugar).to],
        reason: 'um trecho que é fatia de uma parte do ensaio mora onde toca. '
            'O lugar existe para o conserto que vive num arquivo à parte, e a '
            'composta acaba com esse caso: mantê-lo faria o colar desenhar os '
            'seis segundos velhos sobre um trecho que agora tem nove',
      );
    }
    expect(
      [
        _no(it, 2).takeId,
        _no(it, 2).parte,
        _no(it, 2).from,
        _no(it, 2).to,
      ],
      [terceiro.takeId, terceiro.parte, terceiro.from, terceiro.to],
      reason: 'o trecho da outra parte é fatia de outra gravação, e refazer '
          'esta não mexe nele',
    );
  });

  test('as pontes dos vizinhos sobrevivem à composição', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    final ponte = _no(it, 1).retroPath;
    expect(ponte, isNotNull,
        reason: 'a equipe contou este trecho neste tablet, e a explicação dela '
            'está aqui');

    await _consertarPeloCaminhoLongo(it);

    expect(_no(it, 1).retroPath, ponte,
        reason: 'a composição muda o arquivo e o horário de todo trecho da '
            'parte, e o vizinho era achado por essas duas coisas. Perdê-lo '
            'deixa a voz azul muda num trecho que ninguém corrigiu');
  });

  test('todo play usa a passagem composta', () async {
    final it = await _aSalaNaPergunta(apontado: 0);

    await _consertarPeloCaminhoLongo(it, apontaDepois: 1);
    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();

    it.sala.ouvirVozMaterna();
    await waitFor(
      'a materna do trecho vizinho tocar',
      () => it.estado.btTrechoTocando,
    );
    expect(
      [
        File(it.harness.playback.played.last).readAsBytesSync(),
        it.harness.playback.ranges.last,
      ],
      [it.harness.room.takeAudio[_composta], '9000-23000'],
      reason: 'o vizinho é uma fatia da passagem composta agora, no horário '
          'novo. Tocado do arquivo velho, a equipe ouve outro pedaço da '
          'história e julga o trecho errado. Medido pelo áudio: a parte trocada '
          'no lugar guarda o mesmo escopo, e o caminho por si não diz qual dos '
          'dois arquivos está lá',
    );
  });

  test('ouvir a passagem toca a composta', () async {
    final it = await _aSalaNaPergunta(apontado: 0);

    await _consertarPeloCaminhoLongo(it);
    it.sala.continuarOEnsaio();
    await waitFor(
      'a sala voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    it.harness.playback.played.clear();

    it.sala.ghostPlay();
    await waitFor(
      'a passagem começar a tocar',
      () => it.harness.playback.played.isNotEmpty,
    );

    expect(
      File(it.harness.playback.played.first).readAsBytesSync(),
      it.harness.room.takeAudio[_composta],
      reason: 'ouvir a passagem é ouvir o ensaio como ele está agora, e a '
          'primeira parte é a composta. Medido pelo áudio e não pelo caminho: '
          'a parte trocada no lugar guarda o mesmo escopo, e um caminho que '
          'não mudou passaria igual sobre a gravação velha',
    );
  });

  test('o próximo corte vem da composta', () async {
    final it = await _aSalaNaPergunta(
      apontado: 0,
      ateOnde: const Duration(seconds: 14),
    );
    await _consertarPeloCaminhoLongo(it);
    final contadaAte = _no(it, 1).to;

    it.sala.continuarOEnsaio();
    await waitFor(
      'a sala voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    it.sala.startRetro();
    await waitFor(
      'a tradução voltar ao chão que ninguém contou',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    final antes = it.harness.room.chunksSent;
    await _traduzirUmTrecho(it, _aComposta);

    expect(it.harness.room.chunksSent, antes + 1);
    expect(it.harness.room.chunkTakes.last, _composta,
        reason: 'um corte novo é uma fatia da gravação que está tocando, e a '
            'primeira parte é a composta. Enviado sobre a gravação velha, o '
            'trecho novo endereça um áudio que já não é a passagem');
    expect(
      it.harness.room.chunkSpans.last,
      '${contadaAte.inMilliseconds}-${_aComposta.inMilliseconds}',
      reason: 'a contagem desta parte parou onde o trecho vizinho termina '
          'agora, e o corte seguinte começa lá. Começado onde ele terminava '
          'antes da composição, o trecho novo repete três segundos do vizinho',
    );
  });

  test('o colar segue os tempos novos', () async {
    final it = await _aSalaNaPergunta(apontado: 0);

    await _consertarPeloCaminhoLongo(it);

    expect([_naFaixa(it.estado, 0), _naFaixa(it.estado, 1)],
        [(0, 9000), (9000, 23000)],
        reason: 'a equipe que não lê vê no colar onde o conserto dela ficou. '
            'Desenhados pelos horários velhos, os dois trechos se sobrepõem e '
            'a passagem parece mais curta do que é');
  });

  test('sem passagem composta, tudo como antes', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.composesInto = null;
    final parte = it.parteUm;

    await _consertarPeloCaminhoLongo(it);

    expect([it.parteUm.scopeId, it.parteUm.takeId, it.parteUm.path],
        [parte.scopeId, parte.takeId, parte.path],
        reason: 'uma sala que não compôs nada não tem parte nova para dar: a '
            'do ensaio continua sendo a gravação da equipe');
    expect(
      [
        _no(it, 0).takeId,
        _no(it, 0).from,
        _no(it, 0).to,
        _no(it, 0).parte,
        _no(it, 0).lugarFrom,
        _no(it, 0).lugarTo,
      ],
      [
        it.harness.room.takeIds.last,
        Duration.zero,
        _aMaterna,
        0,
        Duration.zero,
        const Duration(seconds: 6),
      ],
      reason: 'o conserto toca o take próprio dele, inteiro, e continua morando '
          'nos seis primeiros segundos da primeira parte',
    );
  });

  test('quando o download falha, nada se perde e a sala avisa', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');
    final parte = it.parteUm;
    final ponte = _no(it, 1).retroPath;
    final avisos = <String>[];
    final antes = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) avisos.add(message);
    };
    addTearDown(() => debugPrint = antes);

    await _consertarPeloCaminhoLongo(it);

    expect([it.parteUm.scopeId, it.parteUm.takeId, it.parteUm.path],
        [parte.scopeId, parte.takeId, parte.path],
        reason: 'a parte só troca quando o áquivo novo está no tablet. Trocada '
            'sobre um download que falhou, ela aponta para um arquivo que não '
            'existe e a retomada seguinte joga o ensaio inteiro fora');
    expect(
      [
        _no(it, 0).parte,
        _no(it, 0).lugarFrom,
        _no(it, 0).lugarTo,
        _no(it, 1).parte,
        _no(it, 1).retroPath,
      ],
      [0, Duration.zero, const Duration(seconds: 6), 0, ponte],
      reason: 'o conserto está feito no servidor e é da equipe: o que se '
          'perdeu foi o arquivo. Os dois trechos continuam na primeira parte, '
          'no lugar que tinham, e a ponte do vizinho continua onde estava',
    );
    expect(avisos.any((linha) => linha.contains(_composta)), isTrue,
        reason: 'uma passagem composta que o tablet nunca alcança não tem outro '
            'sinal: ninguém na sala sabe ler, e a única pessoa que pode '
            'descobrir isso é quem lê o log');
  });

  test('sem a lista das gravações, a sala não troca parte nenhuma', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');
    await _consertarPeloCaminhoLongo(it);
    final parte = it.parteUm;
    it.harness.room
      ..failClipWith = null
      ..failTakesWith = const RoomUnavailable('sem rede');

    await _retomar(it);

    expect([it.parteUm.takeId, it.parteUm.path], [parte.takeId, parte.path],
        reason: 'qual parte uma passagem composta responde é o que a lista das '
            'gravações diz, e só ela: sem a lista a sala não tem como escolher '
            'e não escolhe. Adivinhar poria o áudio de uma parte no lugar de '
            'outra, que é pior do que a retomada de antes');
    expect(it.harness.room.clipsFetched, isEmpty,
        reason: 'nada a baixar enquanto não se sabe o que a gravação responde');
  });

  test('a retomada fria baixa a composta que não tem', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');
    await _consertarPeloCaminhoLongo(it);
    expect(it.parteUm.takeId, isNot(_composta),
        reason: 'esta sessão fechou sem nunca alcançar a passagem composta');
    it.harness.room.failClipWith = null;

    await _retomar(it);
    await waitFor(
      'a sala buscar a passagem composta que ela não tem',
      () => it.parteUm.takeId == _composta,
    );

    expect(_baixou(it, _composta), isTrue,
        reason: 'os trechos apontam para uma gravação que este tablet não tem: '
            'sem buscá-la não há arquivo nenhum para tocá-los');
    it.harness.room.verdictFindingPlace = 1;
    await _pedirOVeredito(it);
    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();

    it.sala.ouvirVozMaterna();
    await waitFor(
      'a materna do trecho vizinho tocar',
      () => it.estado.btTrechoTocando,
    );

    expect(
      [it.harness.playback.played.last, it.harness.playback.ranges.last],
      [it.parteUm.path, '9000-23000'],
      reason: 'uma sala aberta de novo sobre uma passagem composta numa sessão '
          'anterior calava: o trecho não era fatia de parte nenhuma que ela '
          'tivesse, e tocar não fazia nada',
    );
  });

  test('depois de reabrir, a parte trocada continua', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    await _consertarPeloCaminhoLongo(it);
    final arquivo = it.parteUm.path;

    await _retomar(it);

    expect([it.parteUm.takeId, it.parteUm.path], [_composta, arquivo],
        reason: 'a troca da parte foi guardada no ponto de retomada com o '
            'resto do ensaio');
    expect(it.harness.room.clipsFetched, isEmpty,
        reason: 'o arquivo já está no tablet, e baixá-lo de novo a cada '
            'abertura gasta a rede de uma equipe que costuma não ter nenhuma');
  });

  test('8b: um 500 no download não para a sala', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('HTTP 500');
    final avisos = <String>[];
    final antes = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) avisos.add(message);
    };
    addTearDown(() => debugPrint = antes);

    await _consertarPeloCaminhoLongo(it);

    expect(it.estado.needsPerson, isFalse,
        reason: 'um download que falha é melhor-esforço; a sala nunca para '
            'por uma pessoa por causa dele');
    expect(it.estado.offline, isFalse,
        reason: 'a rede que baixou a materna e a ponte está boa; só a busca '
            'da composta falhou');
    expect(it.estado.canResolveWithPerson, isFalse,
        reason: 'sem needsPerson nem offline, não há nada para uma pessoa '
            'resolver');
    expect(avisos, isNotEmpty,
        reason: 'ninguém na sala lê; o log é o único lugar onde isso se sabe');
  });

  test('8c: idem para RoomUnavailable e timeout', () async {
    for (final erro in <Exception>[
      const RoomUnavailable('sem rede'),
      TimeoutException('demorou demais'),
    ]) {
      final it = await _aSalaNaPergunta(apontado: 0);
      it.harness.room.failClipWith = erro;

      await _consertarPeloCaminhoLongo(it);

      expect(it.estado.needsPerson, isFalse,
          reason: '$erro no download da composta também é melhor-esforço');
      expect(it.estado.offline, isFalse,
          reason: '$erro no download da composta não tira a sala do ar');
    }
  });

  test('9b: no resume frio, download que falha não para a sala', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');

    await _consertarPeloCaminhoLongo(it);
    expect(it.parteUm.takeId, isNot(_composta),
        reason: 'este ensaio nunca alcançou a passagem composta: o download '
            'já falhou na estação que a compôs');

    await _retomar(it);

    expect(it.estado.needsPerson, isFalse,
        reason: 'a retomada fria não para a sala só porque a composta não '
            'baixou de novo');
    expect(
      [
        _no(it, 0).parte,
        _no(it, 0).contado,
        _no(it, 1).parte,
        _no(it, 1).contado,
      ],
      [0, true, 0, true],
      reason: 'os dois trechos continuam no lugar e contados: o trecho '
          'corrigido não é fatia de parte nenhuma que este tablet tenha, mas '
          'o lugar onde ele mora no ensaio não depende do arquivo existir',
    );
    expect(_naFaixa(it.estado, 0), isNotNull,
        reason: 'o colar precisa de uma faixa para desenhar o trecho '
            'corrigido, mesmo sem o arquivo local');
    expect(_naFaixa(it.estado, 1), isNotNull, reason: 'idem para o vizinho');
  });

  test(
      '9b-ii: tocar o trecho corrigido sem a composta toca a materna própria',
      () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');

    final materna = await _consertarPeloCaminhoLongo(it);
    await _retomar(it);

    it.harness.room.verdictFindingPlace = 0;
    await _pedirOVeredito(it);
    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();

    it.sala.ouvirVozMaterna();
    await waitFor(
      'a materna do trecho corrigido tocar',
      () => it.estado.btTrechoTocando,
    );

    expect(
      [it.harness.playback.played.last, it.harness.playback.ranges.last],
      [materna, '0-9000'],
      reason: 'sem a composta no tablet, a melhor voz local para o trecho '
          'que ela reendereça é a materna que a equipe regravou — não a '
          'fatia velha da parte, que é a gravação sem a correção',
    );
  });

  test(
      '9b-iii: quando o download passa a funcionar, a composta substitui o '
      'fallback', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');
    await _consertarPeloCaminhoLongo(it);
    await _retomar(it);
    expect(it.parteUm.takeId, isNot(_composta));

    it.harness.room.failClipWith = null;
    await _retomar(it);
    await waitFor(
      'a sala buscar a passagem composta que ela não tinha',
      () => it.parteUm.takeId == _composta,
    );
    expect(_baixou(it, _composta), isTrue);

    it.harness.room.verdictFindingPlace = 0;
    await _pedirOVeredito(it);
    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();

    it.sala.ouvirVozMaterna();
    await waitFor(
      'a materna do trecho corrigido tocar',
      () => it.estado.btTrechoTocando,
    );

    expect(
      [
        File(it.harness.playback.played.last).readAsBytesSync(),
        it.harness.playback.ranges.last,
      ],
      [it.harness.room.takeAudio[_composta], '0-9000'],
      reason: 'com a composta finalmente no tablet, tocar o trecho lê o '
          'arquivo real, não mais o fallback da materna',
    );
  });

  test(
      '9b-iv: precisar de uma pessoa logo após a materna, com a composta '
      'sem baixar, também sobrevive à retomada fria', () async {
    final it = await _aSalaNaPergunta(apontado: 0);
    it.harness.room.failClipWith = const RoomBroke('o balde sumiu');
    it.sala.regravarAVozMaterna();
    it.sala.retroTap();
    await waitFor(
      'o microfone abrir na materna',
      () => it.estado.voice == VoiceState.listening,
    );
    it.harness.room.replaceNeedsPerson = true;
    it.sala.retroTap();
    await waitFor(
      'a sala parar por uma pessoa antes da ponte',
      () => it.estado.needsPerson,
    );

    await _retomar(it);

    expect(
      [_no(it, 0).parte, _no(it, 1).parte],
      [0, 0],
      reason: 'a materna já trocou o trecho e a composição já aconteceu no '
          'servidor antes de a sala parar por uma pessoa; a ponte nunca '
          'rodou para migrar o lugar guardado para o nome novo que o '
          'servidor deu ao segmento, e a retomada — com a composta ainda '
          'sem baixar — não pode perder o lugar por causa disso',
    );
  });
}
