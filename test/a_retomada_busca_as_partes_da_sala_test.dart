import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _sessao = 'sessao-antiga';
const _parte = Duration(seconds: 10);

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

/// Where a resume can break: nowhere, the room's listing, or one part's audio.
enum _Falha { nenhuma, aLista, umaParte }

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
  Set<int> aindaSemNome = const {},
  Map<int, int> passadas = const {},
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
          takeId: aindaSemNome.contains(n) ? null : 'gravacao-$n',
          pass: passadas[n] ?? 1,
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

List<String?> _nomesDasPartes(_Retomada it) => [
  for (final take in it.estado.partes) take.takeId,
];

/// Stand on a finding addressed to the stretch of part 2 and record that part again,
/// which is the gesture the part's own count has to survive a resume for.
Future<void> _regravarAParteDois(_Retomada it) async {
  it.harness.playback.finishPlayback();
  await waitFor('a parte no ar acabar de tocar', () => it.estado.btClipEnded);
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingSegmentId = 'trecho-2';
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
  expect(
    it.estado.btFindingTrecho?.parte,
    1,
    reason: 'o cenário só mede alguma coisa se o achado apontar a parte 2',
  );

  final antiga = it.estado.partes[1].path;
  it.sala.gravarAParteDeNovo();
  await waitFor(
    'a equipe voltar ao ensaio',
    () => it.estado.stage == SalaStage.ensaio,
  );
  it.sala.ensaioTap();
  await waitFor(
    'a gravação começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.ensaioTap();
  await waitFor(
    'a gravação terminar',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  it.sala.takeKeep();
  await waitFor(
    'a gravação nova tomar o lugar da parte 2',
    () => it.estado.partes[1].path != antiga,
  );
  await waitFor(
    'a gravação nova chegar à sala',
    () => it.harness.room.takesKept.contains('ensaio/${KeptScope.parte(2)}'),
  );
}

void main() {
  test(
    'uma linha do ensaio sem os arquivos reabre no ensaio com as partes da sala',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'as partes voltarem da sala',
        () => it.estado.partes.length == 3,
      );

      expect(
        it.estado.stage,
        SalaStage.ensaio,
        reason:
            'a equipe parou no ensaio e a sala ainda guarda o ensaio: '
            'devolvê-la à conversa é mandá-la gravar a passagem de novo por '
            'cima do trabalho que já existe',
      );
      expect(
        _nomesDasPartes(it),
        ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason: 'as partes correntes da sala, na ordem em que a sala as lista',
      );
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
      expect(
        it.estado.btFimDasPartesMs,
        [10000, 20000, 30000],
        reason: 'e medida ao chegar: sem régua o colar não desenha nada',
      );

      await waitFor(
        'a linha passar a nomear os arquivos que existem',
        () => it.linha!.takes.first.path != it.nomeados.first,
      );
      expect(
        [for (final take in it.linha!.takes) take.path],
        [for (final take in it.estado.partes) take.path],
        reason:
            'a linha nomeia os arquivos que o tablet tem agora; deixada '
            'apontando para os que sumiram, a próxima abertura busca tudo de '
            'novo e a equipe paga a rede duas vezes',
      );
      expect(
        [for (final take in it.linha!.takes) take.takeId],
        ['gravacao-1', 'gravacao-2', 'gravacao-3'],
      );
    },
  );

  test(
    'a mesma linha com trechos na sala desenha os trechos nas partes',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        contado: _contado([1, 2]),
      );
      await waitFor(
        'os trechos voltarem',
        () => it.estado.btTrechos.length == 2,
      );

      expect(
        [for (final trecho in it.estado.btTrechos) trecho.parte],
        [0, 1],
        reason: 'cada trecho mora na parte que a equipe gravou (ADR 0022)',
      );
    },
  );

  test(
    'uma linha da retro sem os arquivos reabre na retro no cursor',
    () async {
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
      await waitFor(
        'a parte do cursor entrar no ar',
        () => it.harness.playback.played.isNotEmpty,
      );
      expect(
        it.harness.playback.played.last,
        it.estado.partes[2].path,
        reason:
            'as partes 1 e 2 já foram contadas, então a retomada começa na '
            '3: recomeçar do chão manda contar de novo o que já está contado',
      );
    },
  );

  test('uma passagem conferida reabre na aprovacao com audio', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1], checked: true),
    );
    await waitFor(
      'a aprovação voltar',
      () => it.estado.btPhase == BtPhase.conferida,
    );

    expect(it.estado.stage, SalaStage.retro);
    expect(it.estado.voice, VoiceState.done);
    expect(
      it.estado.partes,
      hasLength(3),
      reason: 'a última audição que o veredito convida precisa do ensaio de pé',
    );

    it.sala.ouvirGravacao();
    await settle();

    expect(
      it.harness.playback.played.last,
      it.estado.partes.first.path,
      reason: 'e ela toca: o botão estava na tela sobre o silêncio',
    );
    expect(it.harness.playback.playedFrom.last, Duration.zero);
  });

  test('um arquivo que ainda esta no tablet nao e buscado de novo', () async {
    final harness = SalaHarness();

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.ensaio,
      aindaNoTablet: {2},
    );
    await waitFor(
      'as partes voltarem da sala',
      () => it.estado.partes.length == 3,
    );

    expect(
      it.harness.room.clipsFetched,
      unorderedEquals([_urlDaParte('gravacao-1'), _urlDaParte('gravacao-3')]),
      reason:
          'baixar de novo um arquivo que está aqui gasta a rede da equipe '
          'e troca a gravação dela por uma cópia',
    );
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);
    expect(
      it.estado.partes[1].path,
      it.nomeados[1],
      reason: 'a parte 2 continua sendo o arquivo que o tablet já tinha',
    );
  });

  test(
    'sem a lista das gravacoes por falta de rede a sala fica fora de alcance '
    'e guarda o ponto',
    () async {
      final harness = SalaHarness()
        ..room.failTakesWith = const NetworkFailed('sem rede');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1]),
      );
      await waitFor(
        'a sala ficar fora de alcance',
        () => it.estado.unreachable,
      );
      expect(it.estado.needsPerson, isFalse);

      expect(
        it.linhaAgora,
        it.linhaAntes,
        reason:
            'o ponto de retomada é a única coisa que sabe qual sessão é '
            'desta passagem: reescrevê-lo depois de uma falha da sala tira da '
            'equipe o caminho de volta para sempre',
      );
      expect(
        it.harness.room.calls,
        isNot(contains('openSession')),
        reason:
            'abrir a conversa põe a equipe a caminho de gravar por cima do '
            'que a sala guarda',
      );
      expect(
        it.estado.partes,
        isEmpty,
        reason: 'e meia fila de partes não é um ensaio: a sala para onde está',
      );
    },
  );

  test('uma parte que nao baixa chama uma pessoa e guarda o ponto', () async {
    final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);

    expect(
      it.linhaAgora,
      it.linhaAntes,
      reason:
          'meia retomada não é retomada: a linha continua nomeando as '
          'três gravações que a equipe fez, para a próxima abertura tentar '
          'de novo',
    );
    expect(it.harness.room.calls, isNot(contains('openSession')));
    expect(
      it.estado.partes,
      isEmpty,
      reason:
          'as duas partes que baixaram não fazem um ensaio: tocá-lo com '
          'um buraco no meio conta à equipe uma história cortada',
    );
  });

  test(
    'na segunda abertura com a sala de volta a equipe cai onde parou',
    () async {
      final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

      final parada = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2]),
      );
      await waitFor(
        'a sala chamar uma pessoa',
        () => parada.estado.needsPerson,
      );

      harness.room.refuseClipOf.clear();
      harness.room.theDeskAttended();
      final volta = await _reabrirDeNovo(parada);
      await waitFor(
        'a retro voltar',
        () => volta.estado.stage == SalaStage.retro,
      );

      expect(
        _nomesDasPartes(volta),
        ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason: 'a sala voltou e o ponto estava de pé: a equipe cai onde parou',
      );
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
    },
  );

  /// A passage reopened into a room the server is still holding, with parts 1 and 2 told
  /// back whole and part 3 never told.
  Future<_Retomada> aRetomadaParada(SalaHarness harness) async {
    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      aindaNoTablet: {1, 2, 3},
      contado: _contado([1, 2]),
    );
    await waitFor('a sala parar ao reabrir', () => it.estado.needsPerson);
    await waitFor(
      'a entrada medir o ensaio',
      () => it.estado.btFimDasPartesMs.length == 3,
    );
    return it;
  }

  test('uma retomada numa sala parada mede o ensaio e nao toca nada', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final it = await aRetomadaParada(harness);

    expect(
      it.estado.needsPerson,
      isTrue,
      reason: 'a parada e do servidor e so a mesa a levanta (ADR 0009)',
    );
    expect(
      harness.playback.played,
      isEmpty,
      reason:
          'uma parada que bloqueia nao toca nada: por o ensaio no ar '
          'cala a sala pelo caminho, e corta a unica chamada por uma pessoa',
    );
    expect(
      it.estado.btPhase,
      BtPhase.playing,
      reason: 'e a sala nao fica presa a pensar: a medicao acabou',
    );
    expect(
      it.estado.btFimDasPartesMs,
      [10000, 20000, 30000],
      reason:
          'a entrada mede o ensaio inteiro mesmo parada, para o colar ja '
          'estar desenhado quando a mesa soltar a equipe',
    );
  });

  test(
    'a mesa a soltar poe no ar a parte que a entrada tinha escolhido',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.blocking;
      final it = await aRetomadaParada(harness);

      harness.room.theDeskAttended();
      await waitFor('a mesa soltar a parada', () => !it.estado.needsPerson);
      await waitFor('a parte entrar no ar', () => it.estado.btClipRodando);

      expect(
        harness.playback.played,
        [it.estado.partes[2].path],
        reason:
            'sem gesto nenhum: a entrada so reteve o som, e soltar a parada '
            'e o que a acaba. A sala parada na tradução sem clipe nenhum '
            'deixava a tesoura passar por todos os guardas e cortar sobre o '
            'silencio',
      );
      expect(
        it.estado.partes[2].takeId,
        'gravacao-3',
        reason: 'e e a primeira parte com chao por contar, nao a parte 1',
      );
    },
  );

  test(
    'a parada nao apaga o que a equipe ja ouvira das partes contadas',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.blocking;
      final it = await aRetomadaParada(harness);

      harness.room.theDeskAttended();
      await waitFor('a mesa soltar a parada', () => !it.estado.needsPerson);
      await waitFor('a parte entrar no ar', () => it.estado.btClipRodando);
      harness.playback
        ..length = _parte
        ..at = _parte
        ..finishPlayback();
      await waitFor('a terceira parte acabar', () => it.estado.btClipEnded);
      await it.sala.finishBackTranslation();
      await waitFor(
        'a sala responder ao terminei',
        () => harness.room.playedByTakeSent.isNotEmpty,
      );

      final relato = {
        for (final parte in harness.room.playedByTakeSent.last)
          parte['take_id']! as String: (parte['played_ranges']! as List)
              .cast<List<int>>(),
      };
      expect(
        relato['gravacao-1'],
        [
          [0, 10000],
        ],
        reason:
            'a parada reteve o som e mais nada: o que a equipe ja ouvira '
            'continua a entrar no registro, ou o terminei era recusado por partes '
            'que ela ouviu na rodada anterior',
      );
      expect(relato['gravacao-2'], [
        [0, 10000],
      ]);
    },
  );

  test(
    'uma sessao que a sala esqueceu recomeca limpa, nao para para sempre',
    () async {
      final harness = SalaHarness()..room.failTakesWith = const SessionGone();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'a sala abrir a passagem de novo',
        () => it.harness.room.calls.contains('createSession'),
      );

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'a sessão que a linha nomeia não existe mais no servidor, e '
            'guardar o ponto seria pedir a mesma sessão morta em toda '
            'abertura: a passagem ficaria parada para sempre, chamando uma '
            'pessoa que não tem o que resolver (ADR 0019)',
      );
      expect(
        it.linha!.sessionId,
        isNot(_sessao),
        reason: 'a linha passa a nomear a sessão nova',
      );
    },
  );

  test(
    'o toque longo depois de uma busca parada tenta a retomada de novo',
    () async {
      final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2]),
      );
      await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);

      // A pessoa chegou, olhou e liberou a sala na mesa; a rede voltou com ela.
      it.harness.room
        ..refuseClipOf.clear()
        ..theDeskAttended();
      it.sala.resolveWithPerson();
      await waitFor('a retro voltar', () => it.estado.stage == SalaStage.retro);

      expect(
        _nomesDasPartes(it),
        ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason:
            'soltar a equipe na conversa desta mesma sessão é pô-la a '
            'gravar um ensaio novo por cima do que a sala guarda — o mal que '
            'este ticket existe para impedir',
      );
      expect(it.estado.btTrechos, hasLength(2));
    },
  );

  test('o toque longo com a sala ainda fora chama uma pessoa de novo', () async {
    // O mesmo link morto que recusa a parte também recusa o pedido de uma
    // pessoa, então não há vigia de sala nenhum e o toque longo é a solta
    // local — que é o caminho em que a equipe cairia na conversa desta sessão.
    final harness = SalaHarness()
      ..room.refuseClipOf.add('gravacao-2')
      ..room.askForAPersonFailsWith = const NetworkFailed('sem rede');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1, 2]),
    );
    await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);

    it.sala.resolveWithPerson();
    await settle(const Duration(milliseconds: 400));

    expect(
      it.estado.needsPerson,
      isTrue,
      reason:
          'a sala continua sem entregar a parte, então a saída continua '
          'sendo a mesma: uma pessoa',
    );
    expect(
      it.linhaAgora,
      it.linhaAntes,
      reason: 'e o ponto de retomada continua intacto para a próxima vez',
    );
    expect(it.harness.room.calls, isNot(contains('openSession')));
  });

  test('um link lento mas vivo entrega as partes sem chamar ninguem', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 400))
      ..room.clipDelay = const Duration(milliseconds: 250);

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'as partes voltarem da sala',
      () => it.estado.partes.length == 3,
    );

    expect(
      it.estado.needsPerson,
      isFalse,
      reason:
          'o teto é o que uma espera pode durar, não o que a busca '
          'inteira soma: três partes que chegam cada uma a tempo são um link '
          'lento, não um que parou, e chamar uma pessoa para ele tira a '
          'equipe do trabalho por nada',
    );
    expect(it.estado.stage, SalaStage.ensaio);
  });

  test(
    'uma parte que nunca chega chama uma pessoa e o pouso nao a apaga',
    () async {
      final harness = SalaHarness(
        busyCeiling: const Duration(milliseconds: 200),
      )..room.holdNextClip();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor('o vigia chamar uma pessoa', () => it.estado.needsPerson);

      it.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 500));

      expect(
        it.estado.needsPerson,
        isTrue,
        reason:
            'a espera pela parte estourou o teto e alguém foi chamado; '
            'pousar por cima disso deixa a equipe a trabalhar dentro de uma '
            'sala que já parou, com o chamado de pé e ninguém a caminho',
      );
      expect(
        it.linhaAgora,
        it.linhaAntes,
        reason:
            'e a linha não é reescrita por uma busca que ninguém esperava '
            'mais',
      );
    },
  );

  for (final falha in _Falha.values) {
    test('a linha nunca e reescrita sem as gravacoes (${falha.name})', () async {
      final harness = SalaHarness();
      switch (falha) {
        case _Falha.nenhuma:
          break;
        case _Falha.aLista:
          harness.room.failTakesWith = const Refused('UNKNOWN_REFERENCE');
        case _Falha.umaParte:
          harness.room.refuseClipOf.add('gravacao-2');
      }

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1]),
      );
      await waitFor(
        'a retomada assentar',
        () => falha == _Falha.nenhuma
            ? it.estado.partes.length == 3
            : it.estado.needsPerson,
      );
      await settle();

      expect(
        [for (final escrita in harness.emAberto.written) escrita.takes],
        everyElement(isNotEmpty),
        reason:
            'uma linha escrita sem gravação nenhuma faz a próxima abertura '
            'passar direto: o ensaio que a sala guarda fica inalcançável para '
            'sempre',
      );
    });
  }

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
    await waitFor(
      'as partes voltarem da sala',
      () => it.estado.partes.length == 2,
    );

    expect(
      _nomesDasPartes(it),
      ['gravacao-1', 'gravacao-2'],
      reason:
          'a voz da equipe a contar um trecho na língua ponte não é uma '
          'parte do ensaio: posta na fila, a retro tocaria a tradução no '
          'lugar da história',
    );
    expect(
      it.harness.room.clipsFetched,
      isNot(contains(_urlDaParte('contado-1'))),
    );
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
    await waitFor(
      'as partes voltarem da sala',
      () => it.estado.partes.length == 3,
    );

    expect(
      _nomesDasPartes(it),
      ['gravacao-1', 'gravacao-9', 'gravacao-3'],
      reason:
          'a parte 2 foi gravada de novo e guarda o seu número e o seu '
          'lugar (ADR 0020): buscar a velha devolve à equipe a gravação que '
          'ela refez de propósito',
    );
  });

  test(
    'uma gravacao de ensaio sem numero e a parte no lugar em que a lista a traz',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        partes: 2,
        // Na ordem em que a sala responde: o ordinal sobe e o que não tem número
        // vem primeiro, que é o que `takes_of` diz por escrito.
        naSala: [
          const TakeView(
            takeId: 'gravacao-2',
            kind: 'ensaio',
            scope: 'parte-2',
          ),
          const TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
        ],
      );
      await waitFor(
        'as partes voltarem da sala',
        () => it.estado.partes.length == 2,
      );

      expect(
        _nomesDasPartes(it),
        ['gravacao-2', 'gravacao-1'],
        reason:
            'um ensaio que a sala não numera é a parte do lugar em que a '
            'lista o traz: fora da fila das partes ele não toca nem se mede',
      );
      expect(
        it.estado.btFimDasPartesMs,
        [10000, 20000],
        reason: 'e o colar o desenha como a qualquer outra parte',
      );
    },
  );

  test(
    'uma retomada com os arquivos aqui devolve cada parte na gravação dela',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        aindaNoTablet: const {1, 2, 3},
        passadas: const {2: 2},
        contado: _contado([1, 2, 3]),
      );
      await waitFor(
        'a equipe voltar à tradução',
        () => it.estado.partes.length == 3,
      );

      await _regravarAParteDois(it);

      expect(
        it.harness.room.takePasses,
        [3],
        reason:
            'a parte 2 voltou na sua segunda gravação, e a terceira subir sob '
            'a passada que a sala já tem deixa a sala escolher entre as duas pela '
            'ordem de chegada',
      );
    },
  );

  test(
    'uma parte buscada na sala volta na gravação que a sala conta',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3]),
        naSala: [
          for (var n = 1; n <= 3; n++)
            TakeView(
              takeId: 'gravacao-$n',
              kind: 'ensaio',
              scope: KeptScope.parte(n),
              ordinal: n,
              pass: n == 2 ? 3 : 1,
            ),
        ],
      );
      await waitFor(
        'as partes voltarem da sala',
        () => it.estado.partes.length == 3,
      );

      await _regravarAParteDois(it);

      expect(
        it.harness.room.takePasses,
        [4],
        reason:
            'a sala é quem sabe quantas gravações da parte 2 ela já tem: o '
            'tablet que buscou a parte não gravou nenhuma delas',
      );
    },
  );

  test(
    'uma retomada para dentro de um aviso o vigia até a mesa atender',
    () async {
      final harness = SalaHarness()
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning;

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        aindaNoTablet: const {1, 2, 3},
        contado: _contado([1, 2, 3]),
      );
      await waitFor('a equipe voltar à tradução', () => it.estado.warning);

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'o aviso não é uma parada, e reabrir dentro dele não fecha a '
            'estação em que a equipe parou',
      );

      // Ninguém vai tocar no tablet: a equipe reabriu e ficou a ouvir.
      harness.room.theDeskAttended();

      await waitFor('o círculo sair do verde', () => !it.estado.warning);
    },
  );
}
