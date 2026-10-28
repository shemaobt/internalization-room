import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/pause_adjust_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, traduzirOApontadoDeNovo;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        contarAteOFimDaParte,
        entrarNaTraducao,
        fimDaGravacao,
        parte,
        tocar,
        tocarNoCirculo;

const _quatroFrases = [
  SegmentView(
    segmentId: 'trecho-1',
    takeId: 'gravacao-1',
    startsMs: 0,
    endsMs: 4000,
    frase: 1,
  ),
  SegmentView(
    segmentId: 'trecho-2',
    takeId: 'gravacao-1',
    startsMs: 4000,
    endsMs: 9000,
    frase: 2,
  ),
  SegmentView(
    segmentId: 'trecho-3',
    takeId: 'gravacao-2',
    startsMs: 0,
    endsMs: 6000,
    frase: 3,
  ),
  SegmentView(
    segmentId: 'trecho-4',
    takeId: 'gravacao-2',
    startsMs: 6000,
    endsMs: 8000,
    frase: 4,
  ),
];

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  BackTranslationProgress contado, {
  SalaStage parouEm = SalaStage.retro,
  String lingua = testLanguage,
  bool juntada = false,
  bool inteira = false,
}) async {
  _telaAlta(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1205');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final partes = [
    if (inteira)
      KeptTake(
        scopeId: KeptScope.whole,
        path: (File(
          '${pasta.path}/inteira.m4a',
        )..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-inteira',
      )
    else
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
          origin: juntada ? 'ensaio-da-cena-$n' : null,
        ),
  ];
  harness.emAberto.rows['Ruth/P01/$lingua'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: partes,
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'a tradução voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).stage == parouEm &&
        container.read(salaSessionProvider).btTrechos.length ==
            contado.segments.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _subTell =
    'Toquem no círculo para pausar onde a frase acaba; toquem de novo para '
    'traduzir só o que aquela frase diz, e de novo para a gravação seguir.';

const _subVerdict =
    'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar uma '
    'parte; ou toquem em terminei para conferir de novo.';

Finder _cabecalho(String texto) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.header == true &&
      widget.properties.label == texto,
);

Future<ProviderContainer> _quatroFrasesConferidas(
  WidgetTester tester,
  SalaHarness harness,
  List<BtFinding> achados,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness);
  for (var parte = 1; parte <= 2; parte++) {
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    await waitFor(
      'a parte $parte ficar contada em duas frases',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          parte * 2,
      step: () => _passo(tester),
    );
  }
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 1
    ..verdictFindings = achados;
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar com os achados',
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

const _achadosDaDoisEDaQuatro = [
  BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
  BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
];

Future<void> _traduzirAFraseApontadaDeNovo(
  WidgetTester tester,
  ProviderContainer container,
) async {
  traduzirOApontadoDeNovo(container);
  await _passo(tester);
  await tocar(tester, 'ouvindo a gravação de vocês…');
  await tocar(tester, 'Tocar ao terminar');
  await _passo(tester);
  await waitFor(
    'a frase traduzida de novo pousar',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

Future<ProviderContainer> _aParteUmRegravada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _quatroFrasesConferidas(tester, harness, const [
    BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
  ]);
  await tocar(tester, 'voltar e regravar uma parte');
  await waitFor(
    'o ensaio abrir na parte 1',
    () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
    step: () => _passo(tester),
  );
  for (final gesto in ['Gravar de novo', 'Parar', 'Enviar a gravação']) {
    await tocar(tester, gesto);
  }
  await waitFor(
    'a parte 1 regravada ficar no lugar',
    () => container
        .read(salaSessionProvider)
        .btTrechos
        .every((trecho) => trecho.parte != 0),
    step: () => _passo(tester),
  );
  container.read(salaSessionProvider.notifier).startRetro();
  await waitFor(
    'a volta à tradução',
    () => container.read(salaSessionProvider).stage == SalaStage.retro,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _comUmaFraseRegravada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room.takes.add(
    const TakeView(
      takeId: 'gravacao-velha-1',
      scope: 'parte-1',
      kind: 'ensaio',
      ordinal: 1,
    ),
  );
  final container = await _voltaATraducao(
    tester,
    harness,
    const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-3',
          takeId: 'gravacao-2',
          startsMs: 0,
          endsMs: 6000,
          frase: 2,
        ),
      ],
      stale: [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-velha-1',
          startsMs: 0,
          endsMs: 4000,
          frase: 1,
        ),
      ],
    ),
  );
  await waitFor(
    'a frase regravada achar a sua parte',
    () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Finder _oCartao(Finder dentro) => find.ancestor(
  of: dentro,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(16),
  ),
);

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

Future<ProviderContainer> _aFraseTresContada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  harness.room.fraseDaProximaFrase = 3;
  await tocarNoCirculo(tester);
  await waitFor(
    'a frase contada pousar',
    () => container
        .read(salaSessionProvider)
        .btTrechos
        .any((trecho) => trecho.contado),
    step: () => _passo(tester),
  );
  return container;
}

Future<void> _naTelaDeUmAparelho(
  WidgetTester tester, {
  required double largura,
  required double barra,
}) async {
  tester.view
    ..physicalSize = Size(largura, 844)
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: barra)
    ..viewPadding = FakeViewPadding(top: barra);
  addTearDown(tester.view.reset);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('four frases the room numbered are listed one to four, each '
      'under its parte, below her heading', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'a tela não tinha número nenhum: a voz dizia «na frase 3» e não '
          'havia nada para apontar',
    );
    closeTheRoom(container);
  });

  testWidgets('a passage recorded whole lists its frases by number alone, '
      'never under a parte the team did not make', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-inteira',
            startsMs: 4000,
            endsMs: 9000,
            frase: 2,
          ),
        ],
      ),
      inteira: true,
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', '2'],
      reason:
          'gravada a passagem de uma vez, cada frase dizia «parte 1», uma '
          'parte que a equipe nunca fez',
    );
    closeTheRoom(container);
  });

  testWidgets('a session picked back up lists the stale frases the room '
      'serves, on the part their recording answered for', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        'parte 1',
        'regravada — traduzam de novo',
        '1',
        'parte 2',
      ],
      reason:
          'reaberta a sessão, a sala servia a frase regravada e a lista não a '
          'mostrava',
    );
    expect(container.read(salaSessionProvider).btTrechos, hasLength(1));
    closeTheRoom(container);
  });

  testWidgets('a session picked back up on the rehearsal still lists its '
      'stale frases when the team comes to the check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      parouEm: SalaStage.ensaio,
    );
    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a ida à tradução',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
      step: () => _passo(tester),
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        'parte 1',
        'regravada — traduzam de novo',
        '1',
        'parte 2',
      ],
      reason:
          'reaberta no ensaio, a sessão perdia as frases regravadas que a sala '
          'servia',
    );
    closeTheRoom(container);
  });

  testWidgets('a session picked back up on the rehearsal marks the scene whose '
      'frases the room serves as stale, and only that one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      parouEm: SalaStage.ensaio,
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    Finder naLinha(int n) => find.descendant(
      of: byLabel('Cena $n'),
      matching: find.text('regravada — traduzam de novo'),
    );
    expect(
      naLinha(1),
      findsOneWidget,
      reason: 'reaberta no ensaio, a casa não dizia que a cena foi regravada',
    );
    expect(naLinha(2), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('starting the translation over clears the stale frases too', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );

    await tocar(tester, 'recomeçar a tradução');
    await tester.pump(const Duration(milliseconds: 700));
    await tocar(tester, 'toque de novo para apagar as 2 frases traduzidas');
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      isEmpty,
      reason:
          'recomeçada a tradução, as frases regravadas ficavam na lista de uma '
          'tradução que já não existia',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('with every part recorded again and only its stale frases '
      'listed, the team can still start the translation over', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.addAll(const [
      TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
      TakeView(
        takeId: 'gravacao-velha-2',
        scope: 'parte-2',
        kind: 'ensaio',
        ordinal: 2,
      ),
    ]);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-2',
            startsMs: 0,
            endsMs: 6000,
          ),
        ],
      ),
    );
    await waitFor(
      'as frases regravadas acharem as suas partes',
      () => container.read(salaSessionProvider).btTrechosRegravados.length == 2,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      byLabel('recomeçar a tradução'),
      findsOneWidget,
      reason:
          'com todas as partes regravadas a lista só tinha frases regravadas '
          'e não havia como recomeçar a tradução',
    );
    expect(find.text('recomeçar a tradução'), findsOneWidget);

    await tocar(tester, 'recomeçar a tradução');
    await tester.pump(const Duration(milliseconds: 700));
    await tocar(tester, 'toque de novo para apagar as 2 frases traduzidas');
    await waitFor(
      'a tradução recomeçar',
      () =>
          harness.room.restartsAsked.isNotEmpty &&
          container.read(salaSessionProvider).btTrechosRegravados.isEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.restartsAsked,
      hasLength(1),
      reason: 'o segundo toque não recomeçava uma tradução sem frase contada',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('armed, «start the translation over» counts the stale frases '
      'it discards with the told ones', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      lingua: 'en',
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );

    await tocar(tester, 'start the translation over');

    expect(
      find.text('tap again to discard the 2 translated sentences'),
      findsOneWidget,
      reason:
          'armado, o botão contava só as frases contadas e não as regravadas '
          'que o segundo toque também apaga',
    );
    expect(
      byLabel('tap again to discard the 2 translated sentences'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('armed on a joined recording, the restart counts the stale '
      'frases among the translations that leave the screen', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-1',
        scope: 'parte-1',
        kind: 'ensaio',
        ordinal: 1,
      ),
    );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-3',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 6000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
      juntada: true,
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    expect(container.read(salaSessionProvider).joined, isTrue);

    await tocar(tester, 'recomeçar a tradução');

    expect(
      find.text(
        'toquem de novo: as 2 traduções saem da tela e vocês traduzem a '
        'passagem inteira de novo',
      ),
      findsOneWidget,
      reason:
          'numa gravação juntada o botão armado contava só as frases contadas',
    );
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(container);
  });

  testWidgets('during the First listen «recomeçar a tradução» stays hidden, '
      'even with stale frases listed', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room
      ..listeningUnheardTakeIds = const ['gravacao-1', 'gravacao-2']
      ..takes.add(
        const TakeView(
          takeId: 'gravacao-velha-1',
          scope: 'parte-1',
          kind: 'ensaio',
          ordinal: 1,
        ),
      );
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [],
        stale: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-velha-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      ),
    );
    await waitFor(
      'a primeira escuta começar com a frase regravada na lista',
      () =>
          container.read(salaSessionProvider).btSoOuvir &&
          container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      byLabel('recomeçar a tradução'),
      findsNothing,
      reason: 'na primeira escuta não há tradução para recomeçar',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase just told shows the number its answer carries, not '
      'a count the tablet keeps, before the session is read again', (
    tester,
  ) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.fraseDaProximaFrase = 7;
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '7', 'parte 1'],
      reason:
          'a frase recém-contada entrava sem número até a próxima leitura da '
          'sessão',
    );
    closeTheRoom(container);
  });

  testWidgets('a told stretch the room gave no number is listed with no '
      'number, never one the tablet counted', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      BackTranslationProgress(
        segments: [
          _quatroFrases[0],
          const SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-1',
            startsMs: 4000,
            endsMs: 9000,
          ),
          _quatroFrases[2],
        ],
      ),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', 'parte 1', 'parte 1', '3', 'parte 2'],
      reason:
          'um número contado no aparelho não é o da voz, e a «frase 2» da '
          'tela seria outra',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'of it, named by its number', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.fraseDaProximaFrase = 3;
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );
    final contada = harness.room.chunkFiles.last;
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      contada,
      reason: 'a lista não tinha como ouvir a tradução de uma frase',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'while the verdict is on the screen, as it does before one', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    final terceira = harness.room.chunkFiles[2];
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      terceira,
      reason:
          'depois do veredito o alto-falante da linha ficava apagado, e a '
          'equipe não ouvia o que contou justo quando queria',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'on a conferida passage too', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const [];
    await _traduzirAFraseApontadaDeNovo(tester, container);
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    final terceira = harness.room.chunkFiles[2];
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      terceira,
      reason:
          'na passagem conferida o alto-falante da linha ficava apagado, e a '
          'equipe não ouvia o que contou',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase is dimmed while the microphone is '
      'open for the next one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, fimDaGravacao);
    await tocar(tester, fimDaGravacao);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      aceso(tester, 'ouvir a minha tradução da frase 3'),
      isFalse,
      reason:
          'o alto-falante seguia aceso com o microfone aberto, e o toque '
          'não fazia nada',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase is dimmed while the check runs', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.room.fraseDaProximaFrase = 4;
    await contarAteOFimDaParte(tester, harness);
    harness.room.holdNextVerdict();
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência começar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 3'),
      isFalse,
      reason:
          'o alto-falante seguia aceso enquanto a sala conferia, e o toque '
          'não fazia nada',
    );
    harness.room.finishHeldVerdict();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase stays lit when the check falls on '
      'the network', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aFraseTresContada(tester, harness);
    harness.room.fraseDaProximaFrase = 4;
    await contarAteOFimDaParte(tester, harness);
    harness.room.reachable = false;
    var conferiu = false;
    harness.room
      ..failFinishWith = const NetworkFailed('timeout')
      ..duranteOVeredito = () => conferiu = true;
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência cair na rede',
      () => conferiu,
      step: () => _passo(tester),
    );
    for (var passo = 0; passo < 5; passo++) {
      await _passo(tester);
    }

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 3'),
      isTrue,
      reason: 'uma rede que cai fora de uma entrada não muda nada',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the loudspeaker of a frase plays nothing while a person is called',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _aFraseTresContada(tester, harness);
      harness.room.fraseDaProximaFrase = 4;
      await contarAteOFimDaParte(tester, harness);
      container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      await waitFor(
        'a tela chamar uma pessoa',
        () => container.read(salaSessionProvider).needsPerson,
        step: () => _passo(tester),
      );

      final antes = harness.playback.played.length;

      container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
      await _passo(tester);

      expect(container.read(salaSessionProvider).canHearAFrase, isFalse);
      expect(
        harness.playback.played,
        hasLength(antes),
        reason:
            'a tela chamava uma pessoa e o alto-falante da linha ainda tocava '
            'por cima',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the loudspeaker of a frase is dimmed when this tablet holds no '
      'rehearsal to play it from', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    harness.emAberto.rows['Ruth/P01/pt'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      checked: true,
      segments: _quatroFrases,
    );
    final container = harness.container();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await _passo(tester);
    unawaited(
      container
          .read(salaSessionProvider.notifier)
          .goConversa(book: 'Ruth', pericope: 'P01'),
    );
    await waitFor(
      'a tradução conferida voltar sem gravação neste tablet',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).partes, isEmpty);

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 3'),
      isFalse,
      reason:
          'o alto-falante seguia aceso numa sessão sem gravação nenhuma no '
          'aparelho, e respondia com silêncio',
    );
    closeTheRoom(container);
  });

  testWidgets('the check screen is headed with her words, «Traduzir a '
      'gravação», not left without a title', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      find.descendant(
        of: _cabecalho('Traduzir a gravação'),
        matching: find.text('Traduzir a gravação'),
      ),
      findsOneWidget,
      reason: 'a tela da tradução não dizia o que era',
    );
    closeTheRoom(container);
  });

  testWidgets('the sub-line tells the team to pause and translate before a '
      'verdict, and to tap a frase or terminei after one', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    expect(
      find.text(_subTell),
      findsOneWidget,
      reason: 'nada na tela dizia à equipe o que fazer',
    );

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictFindingPlace = 0;
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'o veredito chegar com um achado',
      () =>
          container.read(salaSessionProvider).btPhase == BtPhase.playing &&
          container.read(salaSessionProvider).btVeredito,
      step: () => _passo(tester),
    );

    expect(
      find.text(_subVerdict),
      findsOneWidget,
      reason: 'depois do veredito a linha seguia dizendo para pausar',
    );
    expect(find.text(_subTell), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('on a phone as narrow as the iPhone SE the line before a '
      'verdict keeps the margin the frase rows keep, not the screen edge', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );
    tester.view.physicalSize = const Size(375, 2400);
    await _passo(tester);

    final linha = tester.getRect(find.text(_subTell));
    expect(
      linha.left,
      16,
      reason: 'a linha antes do veredito encostava na borda esquerda',
    );
    expect(
      linha.right,
      375 - 16,
      reason: 'a linha antes do veredito encostava na borda direita',
    );
    closeTheRoom(container);
  });

  testWidgets('every frase the check named carries its word, and a frase it '
      'did not name carries none', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
      BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'só o achado que liderava marcava alguma coisa, e os outros não '
          'apareciam como pista',
    );
    closeTheRoom(container);
  });

  testWidgets('a missing element is marked on the frase the check named, '
      'never on the stretch after it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.missing, frase: 3, segmentId: 'trecho-4'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        'faltou depois desta',
        '4',
        'parte 2',
      ],
      reason:
          'a falta depois da frase 3 aponta o trecho da frase 4; marcada pelo '
          'trecho, a palavra cairia na frase errada',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase two findings name carries the word of the first, not '
      'the second', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: BtFindingKind.unclear, frase: 2, segmentId: 'trecho-2'),
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
    ]);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'não ficou claro',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'uma frase leva uma palavra só, a do primeiro achado que a nomeia',
    );
    closeTheRoom(container);
  });

  testWidgets('a finding of a kind this tablet does not know marks nothing, '
      'and the others are still marked', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(tester, harness, const [
      BtFinding(kind: null, frase: 1, segmentId: 'trecho-1'),
      BtFinding(kind: BtFindingKind.addition, frase: 3, segmentId: 'trecho-3'),
    ]);

    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 2',
      'acrescentado',
      '4',
      'parte 2',
    ], reason: 'uma nuance não leva palavra nenhuma');
    closeTheRoom(container);
  });

  testWidgets('a frase translated again loses its mark at once, and the '
      'other frases keep theirs', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room.failFinishWith = const NetworkFailed('timeout');

    await _traduzirAFraseApontadaDeNovo(tester, container);

    expect(harness.room.replacesAsked, hasLength(1));
    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason:
          'a frase traduzida de novo seguia marcada como se o achado ainda '
          'valesse',
    );
    closeTheRoom(container);
  });

  testWidgets('a check that comes back clean takes every mark away', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const [];

    await _traduzirAFraseApontadaDeNovo(tester, container);
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );

    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 2',
      '4',
      'parte 2',
    ], reason: 'a última conferência não nomeou frase nenhuma');
    closeTheRoom(container);
  });

  testWidgets('a part recorded again and kept loses the marks on its frases, '
      'and the other part keeps its own', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );

    await tocar(tester, 'voltar e regravar uma parte');
    await waitFor(
      'o ensaio abrir na parte 1',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
      step: () => _passo(tester),
    );
    for (final gesto in ['Gravar de novo', 'Parar', 'Enviar a gravação']) {
      await tocar(tester, gesto);
    }
    await waitFor(
      'a parte 1 regravada ficar no lugar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .every((trecho) => trecho.parte != 0),
      step: () => _passo(tester),
    );

    expect(
      [
        for (final achado in container.read(salaSessionProvider).btFindings)
          achado.frase,
      ],
      [4],
      reason:
          'a marca da frase 2 ficava de pé e caía na frase 2 nova, que o '
          'veredito nunca ouviu',
    );
    closeTheRoom(container);
  });

  testWidgets('a part recorded again keeps its frases listed in its place, '
      'marked «regravada — traduzam de novo», with their numbers and out of '
      'the check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        'regravada — traduzam de novo',
        '2',
        'parte 1',
        'regravada — traduzam de novo',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'as frases da parte gravada de novo sumiam da lista, e a equipe '
          'perdia de vista o que tinha traduzido dela',
    );
    expect(
      {
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          trecho.parte,
      },
      {1},
      reason: 'uma frase regravada fica fora da conferência',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» card lines up with the other frase cards, on '
      'the iPhone SE as on the iPad', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);

    for (final largura in [820.0, 375.0]) {
      tester.view.physicalSize = Size(largura, 2400);
      await _passo(tester);
      final regravada = tester.getRect(
        _oCartao(find.text('regravada — traduzam de novo')).first,
      );
      final fresca = tester.getRect(_oCartao(find.text('3')).first);
      expect(
        [regravada.left, regravada.width],
        [fresca.left, fresca.width],
        reason:
            'o cartão regravado ficava uns 50 px à direita no iPad e na '
            'largura toda no SE',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a «regravada» frase plays the translation '
      'the team told of it before the part was recorded again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _aParteUmRegravada(tester, harness);
    final primeira = harness.room.chunkFiles.first;
    harness.playback.finishPlayback();
    await _passo(tester);

    expect(
      aceso(tester, 'ouvir a minha tradução da frase 1'),
      isTrue,
      reason: 'a frase regravada não tinha alto-falante',
    );
    await tocar(tester, 'ouvir a minha tradução da frase 1');

    expect(
      harness.playback.played.last,
      primeira,
      reason: 'a tradução de antes da frase regravada não se ouvia mais',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase is told again over the part as it stands '
      'now, at the place it had', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _comUmaFraseRegravada(tester, harness);
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');
    expect(
      [harness.playback.played.last, harness.playback.ranges.lastOrNull],
      [container.read(salaSessionProvider).partes.first.path, '0-4000'],
      reason: 'a barra da frase regravada não tocava nada',
    );
    await tocar(tester, 'ouvindo a gravação de vocês…');
    await tocar(tester, 'Tocar ao terminar');
    await waitFor(
      'a frase regravada traduzida de novo subir',
      () => harness.room.replacesAsked.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-1@gravacao-1:0-4000'],
      reason:
          'a frase regravada não se traduzia de novo, e a equipe só podia '
          'recomeçar a tradução inteira',
    );
    closeTheRoom(container);
  });

  testWidgets('a team that comes back to the check sees the marks its last '
      'check left', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: _quatroFrases,
        findings: _achadosDaDoisEDaQuatro,
      ),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason: 'a equipe que voltava perdia as marcas da última conferência',
    );
    closeTheRoom(container);
  });

  testWidgets('a team that comes back to the rehearsal finds the marks again '
      'when it reaches the check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: _quatroFrases,
        findings: _achadosDaDoisEDaQuatro,
      ),
      parouEm: SalaStage.ensaio,
    );

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a tradução abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        'acrescentado',
        '3',
        'parte 2',
        '4',
        'parte 2',
        'não ficou claro',
      ],
      reason: 'voltando pelo ensaio, as marcas da última conferência sumiam',
    );
    closeTheRoom(container);
  });

  testWidgets('while a mark still stands the sub-line stays the verdict\'s, '
      'even with the recording playing again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesConferidas(
      tester,
      harness,
      _achadosDaDoisEDaQuatro,
    );
    harness.room.failFinishWith = const NetworkFailed('timeout');

    await _traduzirAFraseApontadaDeNovo(tester, container);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(
      find.text(_subVerdict),
      findsOneWidget,
      reason:
          'com a frase 4 ainda marcada a linha voltava a mandar pausar, como '
          'se não houvesse veredito',
    );
    closeTheRoom(container);
  });

  testWidgets('a screen reader on the done button reads «terminei», and the '
      'button shows it, never «Conferir a tradução»', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    expect(
      find.descendant(of: byLabel('terminei'), matching: find.text('terminei')),
      findsOneWidget,
      reason: 'o botão de terminar era um disco mudo chamado de outra coisa',
    );
    expect(byLabel('Conferir a tradução'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while the check runs the done button reads «conferindo…», and '
      'a frase being sent never makes it say so', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.holdNextChunk();
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase seguir para a sala',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      byLabel('conferindo…'),
      findsNothing,
      reason: 'mandar uma frase não é conferir',
    );
    expect(byLabel('terminei'), findsOneWidget);

    harness.room.finishHeldChunk();
    await waitFor(
      'a frase pousar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
      step: () => _passo(tester),
    );
    await contarAteOFimDaParte(tester, harness);
    harness.room.holdNextVerdict();
    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência começar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
      step: () => _passo(tester),
    );

    expect(
      find.descendant(
        of: byLabel('conferindo…'),
        matching: find.text('conferindo…'),
      ),
      findsOneWidget,
      reason: 'a equipe apertava terminei e nada na tela dizia que conferia',
    );
    harness.room.finishHeldVerdict();
    await _passo(tester);
    closeTheRoom(container);
  });

  testWidgets('a check that cannot run says so in her words, and «terminei» '
      'is there again to try once more', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);
    harness.room.failFinishWith = const NetworkFailed('HTTP 502');

    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência cair',
      () =>
          container.read(salaSessionProvider).btRecusa ==
          CheckRefusal.checkUnavailable,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('não deu para conferir agora — tentem de novo'),
      findsOneWidget,
      reason:
          'a conferência que não rodou não dizia nada na tela além do sem '
          'conexão',
    );
    expect(
      byLabel('terminei'),
      findsOneWidget,
      reason: 'terminei é o jeito de tentar de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told with nothing understood shows her line on the '
      'screen, not only to a screen reader', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    harness.room.failChunkWith = const Refused(RefusalCode.wordlessTelling);
    await tocarNoCirculo(tester);
    await waitFor(
      'a sala não entender a frase',
      () => container.read(salaSessionProvider).wordlessTelling,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('não entendi — traduzam de novo esse pedaço'),
      findsOneWidget,
      reason: 'a frase sem palavras não dizia nada na tela',
    );
    closeTheRoom(container);
  });

  testWidgets('a clean check shows «✓ traduzida e conferida», and the circle '
      'says it too', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await contarAteOFimDaParte(tester, harness);

    await tocar(tester, 'terminei');
    await waitFor(
      'a conferência limpa chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('✓ traduzida e conferida'),
      findsOneWidget,
      reason: 'a passagem conferida não dizia na tela que estava conferida',
    );
    expect(
      tester
          .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
          .semanticLabel,
      'traduzida e conferida',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'after a verdict the way back is «voltar e regravar uma parte», never '
    '«achado»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrasesConferidas(
        tester,
        harness,
        _achadosDaDoisEDaQuatro,
      );

      expect(
        byLabel('voltar e regravar uma parte'),
        findsOneWidget,
        reason: '«achado» é palavra da mecânica, não dela',
      );
      expect(byLabel('Gravar a parte de novo na língua materna'), findsNothing);
      closeTheRoom(container);
    },
  );

  for (final (largura, barra) in [(390.0, 59.0), (768.0, 0.0)]) {
    testWidgets(
      'the check screen starts below the status bar and scrolls from there, '
      'not from under it, on a ${largura.toInt()} px screen',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _voltaATraducao(
          tester,
          harness,
          const BackTranslationProgress(segments: _quatroFrases),
        );
        await _naTelaDeUmAparelho(tester, largura: largura, barra: barra);

        final tela = find.byType(RetroView);
        expect(
          tester
              .getTopLeft(
                find.descendant(of: tela, matching: find.byType(Scrollable)),
              )
              .dy,
          greaterThanOrEqualTo(barra),
          reason:
              'a lista rolava por baixo do relógio: a linha de pausa passava '
              'sobre o sinal e a hora',
        );
        expect(
          tester.getTopLeft(_cabecalho('Traduzir a gravação')).dy,
          greaterThanOrEqualTo(barra),
          reason: 'o título ficava debaixo da barra de estado',
        );
        expect(
          tester.getTopLeft(find.byType(PauseAdjustRow)).dy,
          greaterThanOrEqualTo(barra),
          reason: 'a linha dos controles da pausa ficava sobre o relógio',
        );
        closeTheRoom(container);
      },
    );
  }

  for (final (largura, barra) in [(390.0, 59.0), (768.0, 0.0)]) {
    testWidgets(
      'the corner button covers no line of the check screen, at rest or '
      'scrolled, on a ${largura.toInt()} px screen',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await _voltaATraducao(
          tester,
          harness,
          const BackTranslationProgress(segments: _quatroFrases),
        );
        await _naTelaDeUmAparelho(tester, largura: largura, barra: barra);

        final tela = find.byType(RetroView);
        final rolagem = find.descendant(
          of: tela,
          matching: find.byType(Scrollable),
        );
        final posicao = tester.state<ScrollableState>(rolagem).position;
        final janela = tester.getRect(rolagem);
        final botao = byLabel('Voltar para a gravação');
        expect(botao, findsOneWidget);
        expect(posicao.maxScrollExtent, greaterThan(0));

        for (final onde in [
          0.0,
          posicao.maxScrollExtent / 2,
          posicao.maxScrollExtent,
        ]) {
          posicao.jumpTo(onde);
          await _passo(tester);
          final area = tester.getRect(botao);
          final cobertas = [
            for (final texto in tester.widgetList<Text>(
              find.descendant(of: tela, matching: find.byType(Text)),
            ))
              if (tester
                      .getRect(find.byWidget(texto))
                      .intersect(janela)
                      .overlaps(area) &&
                  tester.getRect(find.byWidget(texto)).overlaps(area))
                texto.data,
          ];
          expect(
            cobertas,
            isEmpty,
            reason:
                'o botão do canto ficava parado sobre a tela que rolava e '
                'cobria a linha que passasse por baixo, rolado em $onde',
          );
        }
        closeTheRoom(container);
      },
    );
  }
}
