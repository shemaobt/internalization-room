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
import 'package:internalization_room/features/sala/domain/scene_question.dart';
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

  ResumePoint? get linha => harness.emAberto.rows['Ruth/P01/pt'];

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
  int? regravando,
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
    partBeingRecordedAgain: regravando,
  );
  harness.emAberto.rows['Ruth/P01/pt'] = linha;
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
  unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
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
  unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
  await settle();
  return _Retomada(antes.harness, container, antes.nomeados, antes.linhaAntes);
}

/// A resume that failed takes the team back to the Choice, once the room was asked for
/// the rehearsal it holds.
Future<void> _deVoltaAEscolha(_Retomada it) => waitFor(
  'a equipe voltar à escolha',
  () =>
      it.harness.room.calls.contains('takesOf') &&
      it.estado.stage == SalaStage.escolha,
);

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
        () => it.estado.partes.length == 3 && it.estado.everyPartIsHere,
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

  test(
    'a retro reaberta pousa com as frases antes de as partes chegarem, todas '
    'apagadas, e cada uma acende ao chegar a sua parte',
    () async {
      final harness = SalaHarness()..room.holdNextClip();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2]),
      );
      await waitFor(
        'as frases na tela com a primeira parte ainda no ar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btTrechos.length == 2 &&
            harness.room.clipsFetched.isNotEmpty,
      );
      await settle();

      expect(it.estado.everyPartIsHere, isFalse);
      expect(it.estado.btTrechos.map(it.estado.aParteDoTrechoEstaAqui), [
        false,
        false,
      ]);
      expect(harness.playback.played, isEmpty);

      harness.room.finishHeldClip();
      await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
      expect(it.estado.btTrechos.map(it.estado.aParteDoTrechoEstaAqui), [
        true,
        true,
      ]);
      it.sala.ouvirOTrechoContado(0);
      await waitFor(
        'a frase tocar',
        () => harness.playback.played.contains(it.estado.partes.first.path),
      );
    },
  );

  test('numa retro reaberta o chao comeca quando chega a parte que falhou e a '
      'equipe buscou de novo ao toque', () async {
    final harness = SalaHarness()
      ..room.failClipOf['gravacao-1'] = const NetworkFailed('a rede caiu');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1]),
    );
    await waitFor(
      'as tres partes serem tentadas',
      () =>
          it.estado.stage == SalaStage.retro &&
          harness.room.clipsFetched.length == 3,
    );
    await settle(const Duration(milliseconds: 300));
    expect(harness.playback.played, isEmpty);

    harness.room.failClipOf.clear();
    it.sala.ouvirOTrechoContado(0);
    await waitFor('a parte chegar', () => it.estado.everyPartIsHere);
    await waitFor('o chao tocar', () => harness.playback.played.isNotEmpty);
  });

  test(
    'numa retro reaberta a parte que a sala nao tem mais deixa as suas '
    'frases apagadas na visita, sem mandar a equipe gravar de novo',
    () async {
      final harness = SalaHarness()..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3]),
      );
      await waitFor(
        'as tres partes serem tentadas',
        () =>
            it.estado.stage == SalaStage.retro &&
            harness.room.clipsFetched.length == 3,
      );
      await settle(const Duration(milliseconds: 300));
      it.sala.ouvirOTrechoContado(1);
      await settle();

      expect(it.estado.stage, SalaStage.retro);
      expect(it.estado.partes, hasLength(3));
      expect(it.estado.partsAway['gravacao-2'], PartAway.lost);
      expect(it.estado.aParteDoTrechoEstaAqui(it.estado.btTrechos[1]), isFalse);
      expect(harness.room.clipsFetched, hasLength(3));
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
      () => it.estado.partes.length == 3 && it.estado.everyPartIsHere,
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

  test('sem a lista das gravacoes por falta de rede a equipe volta a escolha '
      'e o ponto fica guardado', () async {
    final harness = SalaHarness()
      ..room.failTakesWith = const NetworkFailed('sem rede');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1]),
    );
    await _deVoltaAEscolha(it);
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
  });

  test('uma sessao que o servidor nao guarda mais volta a escolha', () async {
    final harness = SalaHarness()..room.forgetTheSession(_sessao);

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await _deVoltaAEscolha(it);

    expect(it.estado.needsPerson, isFalse);
    await waitFor('a linha da sessão esquecida sair', () => it.linha == null);
  });

  Future<void> oEnsaioAbre(_Retomada it) => waitFor(
    'o ensaio abrir',
    () =>
        it.estado.stage == SalaStage.ensaio &&
        !it.estado.awaitingTheGuide &&
        it.estado.everyPartIsHere,
  );

  Future<void> gravarACena(_Retomada it, int cena) async {
    it.sala.gravarACena(cena);
    await waitFor(
      'a cena $cena gravar',
      () => it.estado.ensaio == EnsaioStatus.recording,
    );
    it.sala.gravarACena(cena);
    await waitFor(
      'a cena $cena ficar pendente',
      () => it.estado.ensaio == EnsaioStatus.recorded,
    );
    it.sala.takeKeep();
    await waitFor(
      'a cena $cena ficar guardada',
      () => it.estado.ensaio == EnsaioStatus.idle,
    );
  }

  Future<int?> aPassadaQueSobe(_Retomada it, int cena) async {
    final antes = it.harness.room.takePasses.length;
    await gravarACena(it, cena);
    await waitFor(
      'a cena $cena subir',
      () => it.harness.room.takePasses.length > antes,
    );
    return it.harness.room.takePasses.last;
  }

  List<int?> numerosDasPartes(_Retomada it) => [
    for (final take in it.estado.partes) KeptScope.numberOf(take.scopeId),
  ];

  const tresCenas = [
    Scene(sceneId: 'S1', title: 'Cena um'),
    Scene(sceneId: 'S2', title: 'Cena dois'),
    Scene(sceneId: 'S3', title: 'Cena tres'),
  ];

  List<TakeView> salaComPassadas(List<int> passadas) => [
    for (final (i, passada) in passadas.indexed)
      TakeView(
        takeId: 'gravacao-${i + 1}',
        kind: 'ensaio',
        scope: KeptScope.parte(i + 1),
        ordinal: i + 1,
        pass: passada,
      ),
  ];

  Future<_Retomada> semAParteDois(
    SalaHarness harness, {
    SalaStage parouEm = SalaStage.ensaio,
  }) async {
    harness.room
      ..passageScenes = tresCenas
      ..refuseClipOf.add('gravacao-2');
    final it = await _reabrir(
      harness,
      parouEm: parouEm,
      naSala: salaComPassadas([1, 2, 1]),
      contado: parouEm == SalaStage.retro
          ? _contado([1, 3])
          : const BackTranslationProgress(),
    );
    await oEnsaioAbre(it);
    return it;
  }

  group('uma parte que a sala nao tem mais', () {
    test('deixa a linha dela nao gravada e as outras com as suas', () async {
      final it = await semAParteDois(SalaHarness());

      expect(it.estado.needsPerson, isFalse);
      expect(numerosDasPartes(it), [1, 3]);
      expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-3']);
    });

    test('guarda a linha uma vez como o que a equipe tem, no ensaio', () async {
      final it = await semAParteDois(SalaHarness());
      await settle();

      expect(it.linha?.stage, SalaStage.ensaio);
      expect(
        [for (final take in it.linha!.takes) take.takeId],
        ['gravacao-1', 'gravacao-3'],
      );
    });

    test('a cena gravada ali sobe acima da passada da sala', () async {
      final it = await semAParteDois(SalaHarness());

      expect(await aPassadaQueSobe(it, 2), 3);
    });

    test('gravar de novo outra linha nao perde a passada da sala', () async {
      final it = await semAParteDois(SalaHarness());
      await aPassadaQueSobe(it, 3);

      expect(await aPassadaQueSobe(it, 2), 3);
    });

    test('gravar uma linha nova nao perde a passada de outra ainda por '
        'gravar', () async {
      final harness = SalaHarness();
      harness.room
        ..passageScenes = tresCenas
        ..refuseClipOf.addAll(['gravacao-2', 'gravacao-3']);
      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        naSala: salaComPassadas([1, 2, 4]),
        contado: const BackTranslationProgress(),
      );
      await oEnsaioAbre(it);

      expect(numerosDasPartes(it), [1]);
      expect(await aPassadaQueSobe(it, 2), 3);
      expect(await aPassadaQueSobe(it, 3), 5);
    });

    test(
      'reabrir o app antes de gravar a linha nao perde a passada da sala',
      () async {
        final it = await semAParteDois(SalaHarness());
        await settle();

        final volta = await _reabrirDeNovo(it);
        await oEnsaioAbre(volta);

        expect(numerosDasPartes(volta), [1, 3]);
        expect(await aPassadaQueSobe(volta, 2), 3);
      },
    );

    test('o que a equipe faz depois continua guardado na linha', () async {
      final it = await semAParteDois(SalaHarness());
      await aPassadaQueSobe(it, 2);
      await settle();

      expect(it.linha?.takes, hasLength(3));
      expect(it.linha?.passesToGoAbove, isEmpty);
    });

    test('a cena gravada ali, ainda na fila, volta do tablet na proxima '
        'abertura', () async {
      final harness = SalaHarness()
        ..room.unreachableTake = 'ensaio/${KeptScope.parte(2)}';
      final it = await semAParteDois(harness);
      await gravarACena(it, 2);
      await settle();

      final volta = await _reabrirDeNovo(it);
      await oEnsaioAbre(volta);

      expect(numerosDasPartes(volta), [1, 2, 3]);
    });
  });

  test('uma correcao guardada ao lado das partes nao conta como parte: a cena '
      'por gravar ainda sobe acima da passada da sala', () async {
    final harness = SalaHarness()..room.passageScenes = tresCenas;
    final casa = Directory.systemTemp.createTempSync('sala-1355-correcao');
    addTearDown(() => casa.deleteSync(recursive: true));
    String arquivo(String nome) {
      final caminho = '${casa.path}/$nome.m4a';
      File(caminho).writeAsBytesSync([1, 2, 3]);
      harness.playback.lengths[caminho] = _parte;
      return caminho;
    }

    harness.playback.measured = _parte;
    harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
      sessionId: _sessao,
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: arquivo('p1'),
          takeId: 'gravacao-1',
        ),
        KeptTake(
          scopeId: KeptScope.parte(3),
          path: arquivo('p3'),
          takeId: 'gravacao-3',
        ),
        KeptTake(
          scopeId: 'trecho-1',
          path: arquivo('correcao'),
          takeId: 'gravacao-4',
        ),
      ],
      passesToGoAbove: const {2: 2},
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final it = _Retomada(harness, container, const [], '');
    await it.sala.abrirEscolha();
    await settle();
    unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await oEnsaioAbre(it);

    expect(await aPassadaQueSobe(it, 2), 3);
  });

  test(
    'uma linha do ensaio sem nenhuma parte abre o ensaio, nao a conversa',
    () async {
      final harness = SalaHarness()
        ..room.passageScenes = tresCenas
        ..room.refuseClipOf.addAll(['gravacao-1', 'gravacao-2', 'gravacao-3']);
      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await oEnsaioAbre(it);
      await settle();
      expect(it.linha?.takes, isEmpty);

      final volta = await _reabrirDeNovo(it);
      await oEnsaioAbre(volta);

      expect(volta.estado.partes, isEmpty);
    },
  );

  test('uma parte que a sala recusa por outro motivo deixa o ensaio de pe com '
      'as suas linhas', () async {
    final harness = SalaHarness()
      ..room.failClipWith = const Refused(RefusalCode.forbidden);

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'as partes recusadas ficarem nas suas linhas',
      () =>
          it.estado.partes.length == 3 && harness.room.clipsFetched.length == 3,
    );
    await settle();

    expect(it.estado.stage, SalaStage.ensaio);
    expect(it.estado.needsPerson, isFalse);
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);
  });

  test('uma parte que a sala recusa por outro motivo deixa a retro de pe com '
      'as frases dela apagadas', () async {
    final harness = SalaHarness()
      ..room.failClipWith = const Refused(RefusalCode.forbidden);

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1]),
    );
    await waitFor(
      'as tres partes serem tentadas',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.harness.room.clipsFetched.length == 3,
    );
    await settle();

    expect(it.estado.stage, SalaStage.retro);
    expect(it.estado.needsPerson, isFalse);
    expect(
      it.estado.aParteDoTrechoEstaAqui(it.estado.btTrechos.first),
      isFalse,
    );
  });

  test(
    'na segunda abertura com a sala de volta a equipe cai onde parou',
    () async {
      final harness = SalaHarness()
        ..room.failClipWith = const NetworkFailed('a rede caiu');

      final parada = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2]),
      );
      await waitFor(
        'as partes serem tentadas sem rede',
        () => parada.harness.room.clipsFetched.length == 3,
      );
      await settle();

      harness.room.failClipWith = null;
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

  /// A passage reopened into a room the server says needs a person, with parts 1 and 2
  /// told back whole and part 3 never told.
  Future<_Retomada> aRetomadaParada(SalaHarness harness) async {
    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      aindaNoTablet: {1, 2, 3},
      contado: _contado([1, 2]),
    );
    await waitFor(
      'a entrada medir o ensaio',
      () => it.estado.btFimDasPartesMs.length == 3,
    );
    return it;
  }

  test('uma retomada numa sala que o servidor diz parada nao mostra o sinal e '
      'poe no ar a parte por contar', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final it = await aRetomadaParada(harness);
    await waitFor('a parte entrar no ar', () => it.estado.btClipRodando);

    expect(
      it.estado.needsPerson,
      isFalse,
      reason: 'uma leitura da sessão nunca levanta o sinal (ADR 0093)',
    );
    expect(
      it.estado.btFimDasPartesMs,
      [10000, 20000, 30000],
      reason: 'a entrada mede o ensaio inteiro antes de pôr uma parte no ar',
    );
    expect(harness.playback.played, [it.estado.partes[2].path]);
    expect(
      it.estado.partes[2].takeId,
      'gravacao-3',
      reason: 'e e a primeira parte com chao por contar, nao a parte 1',
    );
  });

  test('uma retomada numa sala que o servidor diz parada conta o que a equipe '
      'ja ouvira das partes contadas', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final it = await aRetomadaParada(harness);

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
          'o que a equipe ja ouvira continua a entrar no registro, ou o '
          'terminei era recusado por partes que ela ouviu na rodada anterior',
    );
    expect(relato['gravacao-2'], [
      [0, 10000],
    ]);
  });

  test('um link lento mas vivo entrega as partes sem chamar ninguem', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 400))
      ..room.clipDelay = const Duration(milliseconds: 250);

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'as partes voltarem da sala',
      () => it.estado.partes.length == 3 && it.estado.everyPartIsHere,
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
    'uma parte que passa do teto no ensaio deixa as linhas de pe e nao chama '
    'ninguem',
    () async {
      final harness = SalaHarness(
        busyCeiling: const Duration(milliseconds: 200),
      )..room.holdNextClip();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'o ensaio abrir com as partes da sala',
        () =>
            it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 3,
      );
      await settle(const Duration(milliseconds: 500));
      expect(it.estado.needsPerson, isFalse);

      it.harness.room.finishHeldClip();
      await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
      expect(it.estado.needsPerson, isFalse);
    },
  );

  test(
    'uma parte que passa do teto solta a espera e nao chama ninguem',
    () async {
      final harness = SalaHarness(
        busyCeiling: const Duration(milliseconds: 200),
      )..room.holdNextClip();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1]),
      );
      await waitFor(
        'o vigia soltar a espera',
        () => !it.estado.awaitingTheGuide,
      );
      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'uma espera sem turno no ar que passa do teto é solta, e '
            'ninguém é chamado',
      );
      expect(
        it.estado.aParteDoTrechoEstaAqui(it.estado.btTrechos.first),
        isFalse,
      );

      it.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 500));

      expect(it.estado.needsPerson, isFalse);
      expect(
        it.estado.aParteDoTrechoEstaAqui(it.estado.btTrechos.first),
        isTrue,
        reason: 'a parte que chega atrás do pouso acende a sua frase',
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
          harness.room.failClipWith = const NetworkFailed('a rede caiu');
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
            : falha == _Falha.umaParte
            ? it.estado.stage == SalaStage.retro &&
                  it.harness.room.clipsFetched.length == 3
            : it.harness.room.calls.contains('takesOf') &&
                  it.estado.stage == SalaStage.escolha,
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
    'uma gravacao de ensaio sem numero fica de lado na sala, sem ser buscada, '
    'quando ja ha a parte de uma cena',
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
            scope: KeptScope.whole,
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
        () => it.estado.partes.isNotEmpty && it.estado.everyPartIsHere,
      );

      expect(
        _nomesDasPartes(it),
        ['gravacao-1'],
        reason:
            'o ensaio que o app de antes de 19 de agosto mandava inteiro sai '
            'da tradução assim que a primeira cena tem a sua parte',
      );
      expect(
        harness.room.clipsFetched,
        isNot(contains(_urlDaParte('gravacao-2'))),
        reason: 'e fica guardado na sala: o tablet não o busca',
      );
      expect(
        it.estado.wholeSetAside,
        contains('gravacao-2'),
        reason: 'mas o conhece pelo nome: nunca se apaga',
      );
      expect(it.estado.btFimDasPartesMs, [10000]);
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

  test(
    'um rascunho aprovado pousa logo enquanto as partes descem, e a frase de '
    'uma parte que ainda nao chegou fica calada ate ela chegar',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.holdNextClip();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        contado: _contado([1, 2, 3], checked: true),
      );
      await waitFor(
        'o rascunho aprovado pousar',
        () => it.estado.stage == SalaStage.retro,
      );
      it.sala.ouvirOTrechoContado(0);
      await settle();
      expect(harness.playback.played, isEmpty);

      harness.room.finishHeldClip();
      await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
      it.sala.ouvirOTrechoContado(0);
      await waitFor('a frase tocar', () => harness.playback.played.isNotEmpty);
      expect(it.estado.stage, SalaStage.retro);
    },
  );

  test('a busca de uma abertura deixada nunca apaga o arquivo de uma parte da '
      'abertura nova', () async {
    final harness = SalaHarness()..room.holdNextClip();

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'o ensaio abrir com as partes a caminho',
      () => it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 3,
    );
    await it.sala.abrirEscolha();
    await settle();
    unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await waitFor(
      'o ensaio abrir de novo',
      () => it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 3,
    );

    harness.room.finishHeldClip();
    await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
    await settle(const Duration(milliseconds: 300));

    final vivos = {for (final parte in it.estado.partes) parte.path};
    expect(harness.recorder.deleted.where(vivos.contains), isEmpty);
  });

  test('uma retomada que falha enquanto as partes descem, reaberta, busca as '
      'partes de novo na hora', () async {
    final harness = SalaHarness()
      ..room.holdNextClip()
      ..room.failStateOnceWith = const NetworkFailed('a rede caiu');

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await _deVoltaAEscolha(it);
    final antes = harness.room.clipsFetched.length;

    unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await waitFor(
      'a nova abertura pedir a parte de novo',
      () => harness.room.clipsFetched.length == antes + 1,
    );
    harness.room.finishHeldClip();
    await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
  });

  test(
    'um trecho de uma parte depois da que a sala perdeu fica na sua parte',
    () async {
      final harness = SalaHarness()
        ..room.refuseClipOf.add('gravacao-2')
        ..room.holdNextClip();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        contado: _contado([1, 3]),
      );
      await waitFor(
        'os trechos voltarem enquanto as partes descem',
        () => it.estado.btTrechos.length == 2,
      );
      harness.room.finishHeldClip();
      await waitFor(
        'a sala dizer que a parte 2 se foi',
        () => it.estado.partes.length == 2 && it.estado.everyPartIsHere,
      );

      expect([for (final trecho in it.estado.btTrechos) trecho.parte], [0, 1]);
    },
  );

  test(
    'uma parte que ja chegou nao e buscada de novo na abertura seguinte',
    () async {
      final harness = SalaHarness()..room.holdNextClip();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'o ensaio abrir com as partes a caminho',
        () =>
            it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 3,
      );
      harness.room
        ..finishHeldClip()
        ..holdNextClip();
      await waitFor(
        'a parte 1 chegar',
        () => !it.estado.partsAway.containsKey('gravacao-1'),
      );
      await it.sala.abrirEscolha();
      await settle();
      unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
      await waitFor(
        'o ensaio abrir de novo',
        () =>
            it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 3,
      );
      harness.room.finishHeldClip();
      await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
      await settle(const Duration(milliseconds: 300));

      expect(
        harness.room.clipsFetched.where((url) => url.contains('gravacao-1')),
        hasLength(1),
      );
      expect(
        harness.recorder.home.listSync().where(
          (arquivo) =>
              arquivo.path.contains('gravacao-1') &&
              !harness.recorder.deleted.contains(arquivo.path),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'uma vida que acaba no meio da guarda apaga o arquivo que buscou',
    () async {
      final harness = SalaHarness()..playback.holdNextMeasurement();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'a primeira parte ser medida',
        () => harness.playback.measurements.isNotEmpty,
      );
      final guardado = harness.playback.measurements.first;
      it.container.dispose();
      harness.playback.finishHeldMeasurement();
      await settle(const Duration(milliseconds: 300));

      expect(harness.recorder.deleted, contains(guardado));
    },
  );

  test(
    'sob um rascunho aprovado uma parte que a sala nao tem mais fica, calada, '
    'e a linha continua a nomea-la',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        contado: _contado([1, 2, 3], checked: true),
      );
      await waitFor(
        'as tres partes serem tentadas',
        () =>
            it.estado.stage == SalaStage.retro &&
            harness.room.clipsFetched.length == 3,
      );
      await settle(const Duration(milliseconds: 300));

      expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);
      expect(it.estado.btTrechos, hasLength(3));
      it.sala.ouvirOTrechoContado(1);
      await settle();
      expect(harness.playback.played, isEmpty);
      expect(it.linha!.stage, SalaStage.retro);
      expect([
        for (final take in it.linha!.takes) take.takeId,
      ], containsAll(['gravacao-1', 'gravacao-2', 'gravacao-3']));
    },
  );

  test(
    'um rascunho aprovado reaberto da retro sem os arquivos pousa logo, e uma '
    'parte que a sala nao tem mais fica calada nesta abertura e na seguinte',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3], checked: true),
      );
      await waitFor(
        'o rascunho aprovado pousar com as tres partes tentadas',
        () =>
            it.estado.stage == SalaStage.retro &&
            harness.room.clipsFetched.length == 3,
      );
      await settle(const Duration(milliseconds: 300));
      expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-2', 'gravacao-3']);

      final volta = await _reabrirDeNovo(it);
      await waitFor(
        'o rascunho aprovado pousar de novo',
        () =>
            volta.estado.stage == SalaStage.retro &&
            volta.estado.partes.length == 3,
      );
      await settle(const Duration(milliseconds: 300));

      expect(_nomesDasPartes(volta), [
        'gravacao-1',
        'gravacao-2',
        'gravacao-3',
      ]);
      volta.sala.ouvirOTrechoContado(1);
      await settle();
      expect(harness.playback.played, isEmpty);
    },
  );

  test('um rascunho aprovado reaberto da retro fica de pe quando uma parte nao '
      'chega, e a parte que chegou nao e buscada de novo', () async {
    final harness = SalaHarness()
      ..room.approvedDraft = const ApprovedDraft(version: 1)
      ..room.failClipOf['gravacao-2'] = const NetworkFailed('a rede caiu');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1, 2, 3], checked: true),
    );
    await waitFor(
      'o rascunho aprovado pousar com as tres partes tentadas',
      () =>
          it.estado.stage == SalaStage.retro &&
          harness.room.clipsFetched.length == 3,
    );
    await settle(const Duration(milliseconds: 300));
    it.sala.ouvirOTrechoContado(1);
    await settle();
    expect(harness.playback.played, isEmpty);

    final volta = await _reabrirDeNovo(it);
    await waitFor(
      'o rascunho aprovado pousar de novo',
      () => volta.estado.stage == SalaStage.retro,
    );
    await settle(const Duration(milliseconds: 300));

    expect(
      harness.room.clipsFetched.where((url) => url.contains('gravacao-1')),
      hasLength(1),
    );
  });

  test('a busca das partes comeca no pouso, antes de a leitura da sessao '
      'responder', () async {
    final harness = SalaHarness()
      ..room.holdNextState()
      ..room.holdNextClip();

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'a primeira parte ser pedida com a leitura ainda no ar',
      () => harness.room.clipsFetched.isNotEmpty,
    );

    harness.room
      ..finishHeldState()
      ..finishHeldClip();
    await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
  });

  test('sob um rascunho aprovado a frase de uma parte que nao chegou busca a '
      'parte de novo ao toque', () async {
    final harness = SalaHarness()
      ..room.approvedDraft = const ApprovedDraft(version: 1)
      ..room.failClipOf['gravacao-2'] = const NetworkFailed('a rede caiu');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      contado: _contado([1, 2, 3], checked: true),
    );
    await waitFor(
      'o rascunho aprovado pousar com as tres partes tentadas',
      () =>
          it.estado.stage == SalaStage.retro &&
          harness.room.clipsFetched.length == 3,
    );
    await settle(const Duration(milliseconds: 300));

    harness.room.failClipOf.clear();
    it.sala.ouvirOTrechoContado(1);
    await waitFor('a parte 2 chegar', () => it.estado.everyPartIsHere);
    expect(
      harness.room.clipsFetched.where((url) => url.contains('gravacao-2')),
      hasLength(2),
    );
    expect(harness.playback.played, isEmpty);

    it.sala.ouvirOTrechoContado(1);
    await waitFor('a frase tocar', () => harness.playback.played.isNotEmpty);
  });

  test(
    'uma busca da retro que a equipe deixou no meio apaga o arquivo que guardou',
    () async {
      final harness = SalaHarness()..room.holdNextClip();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3]),
      );
      await waitFor(
        'a primeira parte ser pedida',
        () => harness.room.clipsFetched.isNotEmpty,
      );
      await it.sala.abrirEscolha();
      harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 300));

      expect(
        harness.recorder.deleted.where((path) => path.contains('gravacao-1')),
        hasLength(1),
      );
    },
  );

  test('uma parte que a sala nao tem mais espera a leitura da sessao, e sai do '
      'ensaio quando ela diz que a equipe fica no ensaio', () async {
    final harness = SalaHarness()
      ..room.refuseClipOf.add('gravacao-2')
      ..room.holdNextState();

    final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
    await waitFor(
      'as tres partes serem tentadas com a leitura no ar',
      () => harness.room.clipsFetched.length == 3,
    );
    await settle();
    expect(it.estado.partes, hasLength(3));

    harness.room.finishHeldState();
    await waitFor(
      'a parte 2 sair do ensaio',
      () => it.estado.partes.length == 2 && it.estado.everyPartIsHere,
    );
    expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-3']);
  });

  test('um rascunho aprovado reaberto da retro com a lista da sala fora do ar '
      'volta a escolha e guarda a linha e os arquivos do tablet', () async {
    final harness = SalaHarness()
      ..room.approvedDraft = const ApprovedDraft(version: 1)
      ..room.failTakesWith = const NetworkFailed('a rede caiu');

    final it = await _reabrir(
      harness,
      parouEm: SalaStage.retro,
      aindaNoTablet: {1, 3},
      contado: _contado([1, 2, 3], checked: true),
    );
    await _deVoltaAEscolha(it);
    await settle(const Duration(milliseconds: 300));

    expect(it.linhaAgora, it.linhaAntes);
    expect(harness.room.clipsFetched, isEmpty);
  });

  test(
    'sob um rascunho aprovado a frase de uma parte que a sala nao tem mais nao '
    'busca de novo ao toque',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3], checked: true),
      );
      await waitFor(
        'o rascunho aprovado pousar com as tres partes tentadas',
        () =>
            it.estado.stage == SalaStage.retro &&
            harness.room.clipsFetched.length == 3,
      );
      await settle(const Duration(milliseconds: 300));

      it.sala.ouvirOTrechoContado(1);
      await settle(const Duration(milliseconds: 300));
      expect(harness.room.clipsFetched, hasLength(3));
    },
  );

  test(
    'uma retro sem rascunho aprovado e sem os arquivos le a sessao uma vez so',
    () async {
      final harness = SalaHarness();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2]),
      );
      await waitFor('a retro voltar', () => it.estado.stage == SalaStage.retro);
      await settle(const Duration(milliseconds: 300));

      expect(
        harness.room.calls.where((call) => call == 'fetchState'),
        hasLength(1),
      );
    },
  );

  test(
    'uma parte que a sala nao tem mais sob um rascunho aprovado sai da linha '
    'quando a equipe volta ao ensaio',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.refuseClipOf.add('gravacao-2');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        contado: _contado([1, 2, 3], checked: true),
      );
      await waitFor(
        'o rascunho aprovado pousar com as tres partes tentadas',
        () =>
            it.estado.stage == SalaStage.retro &&
            harness.room.clipsFetched.length == 3,
      );
      await settle(const Duration(milliseconds: 300));

      it.sala.goEnsaio();
      await waitFor(
        'a parte 2 sair do ensaio',
        () =>
            it.estado.stage == SalaStage.ensaio && it.estado.partes.length == 2,
      );
      expect(_nomesDasPartes(it), ['gravacao-1', 'gravacao-3']);
    },
  );

  test('uma linha do fim nao volta a ser escrita no fim depois que a leitura '
      'tirou do ensaio uma parte que a sala nao tem mais', () async {
    final harness = SalaHarness()
      ..room.refuseClipOf.add('gravacao-2')
      ..room.holdNextState()
      ..room.holdNextClip();

    final it = await _reabrir(harness, parouEm: SalaStage.fim);
    await waitFor(
      'a parte 1 ser pedida',
      () => harness.room.clipsFetched.length == 1,
    );
    harness.room
      ..finishHeldClip()
      ..holdNextClip();
    await waitFor(
      'a parte 2 ser pedida',
      () => harness.room.clipsFetched.length == 2,
    );
    harness.room
      ..finishHeldClip()
      ..holdNextClip();
    await waitFor(
      'a parte 3 ser pedida',
      () => harness.room.clipsFetched.length == 3,
    );
    harness.room.finishHeldState();
    await waitFor('a parte 2 sair', () => it.estado.partes.length == 2);
    harness.room.finishHeldClip();
    await waitFor('as partes chegarem', () => it.estado.everyPartIsHere);
    await settle(const Duration(milliseconds: 300));

    expect(it.linha!.stage, SalaStage.ensaio);
  });

  test(
    'a parte a regravar continua a mesma cena quando uma parte antes dela sai '
    'do ensaio',
    () async {
      final harness = SalaHarness()
        ..room.refuseClipOf.add('gravacao-1')
        ..room.holdNextState();

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.ensaio,
        regravando: 2,
      );
      await waitFor(
        'as tres partes serem tentadas com a leitura no ar',
        () => harness.room.clipsFetched.length == 3,
      );
      expect(it.estado.sceneForTheCircle, 3);

      harness.room.finishHeldState();
      await waitFor('a parte 1 sair', () => it.estado.partes.length == 2);

      expect(it.estado.sceneForTheCircle, 3);
    },
  );

  test(
    'um rascunho aprovado da retro com a lista fora do ar pede a lista uma vez '
    'so',
    () async {
      final harness = SalaHarness()
        ..room.approvedDraft = const ApprovedDraft(version: 1)
        ..room.failTakesWith = const NetworkFailed('a rede caiu');

      final it = await _reabrir(
        harness,
        parouEm: SalaStage.retro,
        aindaNoTablet: {1, 3},
        contado: _contado([1, 2, 3], checked: true),
      );
      await _deVoltaAEscolha(it);
      await settle(const Duration(milliseconds: 300));

      expect(
        harness.room.calls.where((call) => call == 'takesOf'),
        hasLength(1),
      );
    },
  );

  for (final (achado, cena) in [
    ('trecho-2', 2),
    ('trecho-3', 3),
    ('trecho-1', 1),
  ]) {
    test(
      'sob um rascunho aprovado sem a parte 1, regravar pelo achado em $achado '
      'leva o circulo a cena $cena',
      () async {
        final harness = SalaHarness()
          ..room.approvedDraft = const ApprovedDraft(version: 1)
          ..room.refuseClipOf.add('gravacao-1');

        final it = await _reabrir(
          harness,
          parouEm: SalaStage.retro,
          contado: _contado([1, 2, 3], checked: true),
        );
        await waitFor(
          'o rascunho aprovado pousar com as tres partes tentadas',
          () =>
              it.estado.stage == SalaStage.retro &&
              harness.room.clipsFetched.length == 3,
        );
        await settle(const Duration(milliseconds: 300));
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        it.sala.state = it.estado.copyWith(
          btPhase: BtPhase.playing,
          btFindingSegmentId: achado,
        );

        it.sala.gravarAParteDeNovo();
        await settle(const Duration(milliseconds: 300));

        expect(it.estado.stage, SalaStage.ensaio);
        expect(_nomesDasPartes(it), ['gravacao-2', 'gravacao-3']);
        expect(it.estado.sceneForTheCircle, cena);
      },
    );
  }

  test(
    'uma parte que a sala nao tem mais saindo do ensaio nao cala a parte que '
    'a equipe ouve',
    () async {
      final harness = SalaHarness()
        ..room.refuseClipOf.add('gravacao-1')
        ..room.holdNextState();

      final it = await _reabrir(harness, parouEm: SalaStage.ensaio);
      await waitFor(
        'as tres partes serem tentadas com a leitura no ar',
        () => harness.room.clipsFetched.length == 3,
      );
      await settle();
      it.sala.ouvirACena(3);
      await waitFor(
        'a parte 3 tocar',
        () => it.estado.parteDoEnsaioTocando == 2,
      );
      final tocadas = harness.playback.played.length;

      harness.room.finishHeldState();
      await waitFor('a parte 1 sair', () => it.estado.partes.length == 2);
      await settle();

      expect(harness.playback.played, hasLength(tocadas));
      expect(
        it.estado.partes[it.estado.parteDoEnsaioTocando!].takeId,
        'gravacao-3',
      );
    },
  );
}
