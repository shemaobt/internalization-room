import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_cord.dart';

import 'fakes.dart';

const _sessao = 'sessao-antiga';
const _parte = Duration(seconds: 10);

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

/// The room's own recordings of a rehearsal of [partes] parts, as the listing answers.
List<TakeView> _naSala(int partes) => [
      for (var n = 1; n <= partes; n++)
        TakeView(
          takeId: 'gravacao-$n',
          kind: 'ensaio',
          scope: KeptScope.parte(n),
          ordinal: n,
        ),
    ];

/// A telling-back of the whole of each named part, as the room hands it back.
BackTranslationProgress _contado(List<int> partes, {bool checked = false}) =>
    BackTranslationProgress(
      segments: [
        for (final n in partes)
          SegmentView(
            segmentId: 'trecho-$n',
            takeId: 'gravacao-$n',
            startsMs: 0,
            endsMs: _parte.inMilliseconds,
          ),
      ],
      checked: checked,
    );

String _urlDaParte(String take) => RoomRepository.takeAudioUrl(_sessao, take);

class _Retomada {
  final SalaHarness harness;
  final ProviderContainer container;

  /// The files the resume row names, in part order. A restore leaves them gone.
  final List<String> nomeados;

  /// The row exactly as it was written, so a halt can be asked to have changed nothing.
  final String linhaAntes;

  _Retomada(this.harness, this.container, this.nomeados, this.linhaAntes);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  ResumePoint? get linha => harness.emAberto.rows['Ruth/P01'];

  String get linhaAgora => jsonEncode(linha?.toJson());
}

/// A passage reopened on a tablet that no longer holds the recordings the row names.
///
/// [aindaNoTablet] are the part numbers whose files a restore happened to leave behind;
/// every other file is gone the way a reinstall leaves it.
Future<_Retomada> _reabrir(
  SalaHarness harness, {
  required SalaStage parouEm,
  int partes = 3,
  Set<int> aindaNoTablet = const {},
  BackTranslationProgress contado = const BackTranslationProgress(),
  List<TakeView>? naSala,
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-retomada-busca');
  addTearDown(() => casa.deleteSync(recursive: true));
  final nomeados = [for (var n = 1; n <= partes; n++) '${casa.path}/p$n.m4a'];
  for (var n = 1; n <= partes; n++) {
    if (!aindaNoTablet.contains(n)) continue;
    File(nomeados[n - 1]).writeAsBytesSync([1, 2, 3]);
    harness.playback.lengths[nomeados[n - 1]] = _parte;
  }
  final linha = ResumePoint(
    sessionId: _sessao,
    stage: parouEm,
    takes: [
      for (var n = 1; n <= partes; n++)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: nomeados[n - 1],
          takeId: 'gravacao-$n',
        ),
    ],
  );
  harness.emAberto.rows['Ruth/P01'] = linha;
  harness.playback.measured = _parte;
  harness.room
    ..retroSoFar = contado
    ..takes.addAll(naSala ?? _naSala(partes));

  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  // Not awaited: a room that keeps the tablet waiting — a held measurement, a clip
  // that never lands — is a case these tests have to be able to look at while it is
  // still waiting. Every one of them reads the room through `waitFor` anyway.
  unawaited(sala.goConversa(pericope: 'P01'));
  await settle();
  return _Retomada(harness, container, nomeados, jsonEncode(linha.toJson()));
}

/// Open the same passage a second time, on the same tablet and the same ledger.
Future<_Retomada> _reabrirDeNovo(_Retomada antes) async {
  antes.container.dispose();
  final container = antes.harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  unawaited(sala.goConversa(pericope: 'P01'));
  await settle();
  return _Retomada(antes.harness, container, antes.nomeados, antes.linhaAntes);
}

List<String?> _nomesDasPartes(_Retomada it) =>
    [for (final take in it.estado.partes) take.takeId];

void main() {
  test('uma linha do ensaio sem os arquivos reabre no ensaio com as partes da sala',
      () async {
    final harness = SalaHarness();

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor('as partes voltarem da sala', () => it.estado.partes.length == 3);

    expect(it.estado.stage, SalaStage.ensaio,
        reason: 'a equipe parou no ensaio e a sala ainda guarda o ensaio: '
            'devolvê-la à conversa é mandá-la gravar a passagem de novo por '
            'cima do trabalho que já existe');
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason: 'as partes correntes da sala, na ordem em que a sala as lista');
    expect(
      [for (final take in it.estado.partes) File(take.path).existsSync()],
      [true, true, true],
      reason: 'e com áudio no tablet: uma parte sem arquivo não toca nada',
    );
    expect(
      it.harness.room.clipsFetched,
      unorderedEquals([
        _urlDaParte('gravacao-1'),
        _urlDaParte('gravacao-2'),
        _urlDaParte('gravacao-3'),
      ]),
      reason: 'cada parte é buscada pela sua própria porta de áudio',
    );
    expect(it.estado.btFimDasPartesMs, [10000, 20000, 30000],
        reason: 'e medida ao chegar: sem régua o colar não desenha nada');

    await waitFor(
      'a linha passar a nomear os arquivos que existem',
      () => it.linha!.takes.first.path != it.nomeados.first,
    );
    expect(
      [for (final take in it.linha!.takes) take.path],
      [for (final take in it.estado.partes) take.path],
      reason: 'a linha nomeia os arquivos que o tablet tem agora; deixada '
          'apontando para os que sumiram, a próxima abertura busca tudo de '
          'novo e a equipe paga a rede duas vezes',
    );
    expect(
      [for (final take in it.linha!.takes) take.takeId],
      ['gravacao-1', 'gravacao-2', 'gravacao-3'],
    );
  });

  test('a mesma linha com trechos na sala desenha os trechos nas partes', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      contado: _contado([1, 2]),
    );
    await waitFor('os trechos voltarem', () => it.estado.btTrechos.length == 2);

    expect([for (final trecho in it.estado.btTrechos) trecho.parte], [0, 1],
        reason: 'cada trecho mora na parte que a equipe gravou (ADR 0022)');
    expect(
      [
        for (final trecho in it.estado.btTrechos)
          cordSpanMs(trecho: trecho, fimDasPartes: it.estado.btFimDasPartesMs),
      ],
      [(0, 10000), (10000, 20000)],
      reason: 'e o colar desenha a faixa por cima da parte em que ele mora: é '
          'o único lugar em que uma equipe que não lê vê onde o trabalho está',
    );
  });

  test('uma linha da retro sem os arquivos reabre na retro no cursor', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1, 2]),
    );
    await waitFor('a retro voltar', () => it.estado.stage == SalaStage.retro);

    expect(it.estado.btPhase, BtPhase.playing);
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);
    expect(it.estado.btTrechos, hasLength(2));
    await waitFor('a parte do cursor entrar no ar',
        () => it.harness.playback.played.isNotEmpty);
    expect(it.harness.playback.played.last, it.estado.partes[2].path,
        reason: 'as partes 1 e 2 já foram contadas, então a retomada começa na '
            '3: recomeçar do chão manda contar de novo o que já está contado');
  });

  test('uma passagem conferida reabre na aprovacao com audio', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1], checked: true),
    );
    await waitFor('a aprovação voltar', () => it.estado.btPhase == BtPhase.conferida);

    expect(it.estado.stage, SalaStage.retro);
    expect(it.estado.voice, VoiceState.done);
    expect(it.estado.partes, hasLength(3),
        reason: 'a última audição que o veredito convida precisa do ensaio de pé');

    it.sala.ouvirGravacao();
    await settle();

    expect(it.harness.playback.played.last, it.estado.partes.first.path,
        reason: 'e ela toca: o botão estava na tela sobre o silêncio');
    expect(it.harness.playback.playedFrom.last, Duration.zero);
  });

  test('um arquivo que ainda esta no tablet nao e buscado de novo', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      aindaNoTablet: {2},
    );
    await waitFor('as partes voltarem da sala', () => it.estado.partes.length == 3);

    expect(
        it.harness.room.clipsFetched,
        unorderedEquals([_urlDaParte('gravacao-1'), _urlDaParte('gravacao-3')]),
        reason: 'baixar de novo um arquivo que está aqui gasta a rede da equipe '
            'e troca a gravação dela por uma cópia');
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);
    expect(it.estado.partes[1].path, it.nomeados[1],
        reason: 'a parte 2 continua sendo o arquivo que o tablet já tinha');
  });

  test('sem a lista das gravacoes a sala chama uma pessoa e guarda o ponto',
      () async {
    final harness = SalaHarness()..room.failTakesWith = const RoomUnavailable('sem rede');

    final it = await _reabrir(harness, parouEm: SalaStage.retro, contado: _contado([1]));
    await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);

    expect(it.linhaAgora, it.linhaAntes,
        reason: 'o ponto de retomada é a única coisa que sabe qual sessão é '
            'desta passagem: reescrevê-lo depois de uma falha da sala tira da '
            'equipe o caminho de volta para sempre');
    expect(it.harness.room.calls, isNot(contains('openSession')),
        reason: 'abrir a conversa põe a equipe a caminho de gravar por cima do '
            'que a sala guarda');
    expect(it.estado.partes, isEmpty,
        reason: 'e meia fila de partes não é um ensaio: a sala para onde está');
  });

  test('uma parte que nao baixa chama uma pessoa e guarda o ponto', () async {
    final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);

    expect(it.linhaAgora, it.linhaAntes,
        reason: 'meia retomada não é retomada: a linha continua nomeando as '
            'três gravações que a equipe fez, para a próxima abertura tentar '
            'de novo');
    expect(it.harness.room.calls, isNot(contains('openSession')));
    expect(it.estado.partes, isEmpty,
        reason: 'as duas partes que baixaram não fazem um ensaio: tocá-lo com '
            'um buraco no meio conta à equipe uma história cortada');
  });

  test('na segunda abertura com a sala de volta a equipe cai onde parou', () async {
    final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

    final parada = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1, 2]),
    );
    await waitFor('a sala chamar uma pessoa', () => parada.estado.needsPerson);

    harness.room.refuseClipOf.clear();
    final volta = await _reabrirDeNovo(parada);
    await waitFor('a retro voltar', () => volta.estado.stage == SalaStage.retro);

    expect(_nomesDasPartes(volta), ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason: 'a sala voltou e o ponto estava de pé: a equipe cai onde parou');
    expect(volta.estado.btTrechos, hasLength(2));
    expect(volta.estado.needsPerson, isFalse);
    await waitFor(
      'a linha passar a nomear os arquivos que existem',
      () => volta.linha!.takes.first.path != volta.nomeados.first,
    );
    expect(
      [for (final take in volta.linha!.takes) take.path],
      [for (final take in volta.estado.partes) take.path],
      reason: 'e agora a linha nomeia os arquivos que este tablet tem',
    );
  });

  test('uma sessao que a sala esqueceu recomeca limpa, nao para para sempre',
      () async {
    final harness = SalaHarness()..room.failTakesWith = const SessionGone();

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'a sala abrir a passagem de novo',
      () => it.harness.room.calls.contains('createSession'),
    );

    expect(it.estado.needsPerson, isFalse,
        reason: 'a sessão que a linha nomeia não existe mais no servidor, e '
            'guardar o ponto seria pedir a mesma sessão morta em toda '
            'abertura: a passagem ficaria parada para sempre, chamando uma '
            'pessoa que não tem o que resolver (ADR 0019)');
    expect(it.linha!.sessionId, isNot(_sessao),
        reason: 'a linha passa a nomear a sessão nova');
  });

  test('a linha nunca e reescrita sem as gravacoes', () async {
    for (final falha in [null, 'lista', 'parte']) {
      final harness = SalaHarness();
      if (falha == 'lista') {
        harness.room.failTakesWith = const RoomUnavailable('sem rede');
      }
      if (falha == 'parte') harness.room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1]),
      );
      await waitFor(
        'a retomada assentar (falha: ${falha ?? 'nenhuma'})',
        () => falha == null
            ? it.estado.partes.length == 3
            : it.estado.needsPerson,
      );
      await settle();

      expect(
        [for (final escrita in harness.emAberto.written) escrita.takes.isEmpty],
        isNot(contains(true)),
        reason: 'uma linha escrita sem gravação nenhuma faz a próxima abertura '
            'passar direto: o ensaio que a sala guarda fica inalcançável para '
            'sempre (falha: ${falha ?? 'nenhuma'})',
      );
    }
  });

  test('uma gravacao de traducao nunca vira parte', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      naSala: [
        const TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
        const TakeView(
          takeId: 'contado-1',
          kind: 'retro',
          scope: 'trecho-1',
          ordinal: 1,
        ),
        const TakeView(
          takeId: 'gravacao-2',
          kind: 'ensaio',
          scope: 'parte-2',
          ordinal: 2,
        ),
      ],
    );
    await waitFor('as partes voltarem da sala', () => it.estado.partes.length == 2);

    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2'],
        reason: 'a voz da equipe a contar um trecho na língua ponte não é uma '
            'parte do ensaio: posta na fila, a retro tocaria a tradução no '
            'lugar da história');
    expect(it.harness.room.clipsFetched, isNot(contains(_urlDaParte('contado-1'))));
  });

  test('a parte gravada de novo na sala e a mais nova', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      naSala: [
        ..._naSala(3),
        const TakeView(
          takeId: 'gravacao-9',
          kind: 'ensaio',
          scope: 'parte-2',
          ordinal: 2,
        ),
      ],
    );
    await waitFor('as partes voltarem da sala', () => it.estado.partes.length == 3);

    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-9', 'gravacao-3'],
        reason: 'a parte 2 foi gravada de novo e guarda o seu número e o seu '
            'lugar (ADR 0020): buscar a velha devolve à equipe a gravação que '
            'ela refez de propósito');
  });

  test('uma gravacao de ensaio sem numero e a parte no lugar em que a lista a traz',
      () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      partes: 2,
      // Na ordem em que a sala responde: o ordinal sobe e o que não tem número
      // vem primeiro, que é o que `takes_of` diz por escrito.
      naSala: [
        const TakeView(takeId: 'gravacao-2', kind: 'ensaio', scope: 'parte-2'),
        const TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      ],
    );
    await waitFor('as partes voltarem da sala', () => it.estado.partes.length == 2);

    expect(_nomesDasPartes(it), ['gravacao-2', 'gravacao-1'],
        reason: 'um ensaio que a sala não numera é a parte do lugar em que a '
            'lista o traz: fora da fila das partes ele não toca nem se mede');
    expect(it.estado.btFimDasPartesMs, [10000, 20000],
        reason: 'e o colar o desenha como a qualquer outra parte');
  });
}
