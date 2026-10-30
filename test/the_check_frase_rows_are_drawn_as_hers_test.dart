import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/dashed_edge.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show holdTheSession, intoTheBackTranslation;
import 'the_back_translation_is_told_by_beads_test.dart' show tocar;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  BackTranslationProgress contado, {
  List<int> partes = const [1, 2],
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1937');
  addTearDown(() => pasta.deleteSync(recursive: true));
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        for (final n in partes)
          KeptTake(
            scopeId: KeptScope.parte(n),
            path: (File(
              '${pasta.path}/p$n.m4a',
            )..writeAsBytesSync([1, 2, 3])).path,
            takeId: 'gravacao-$n',
          ),
      ],
    ),
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  await intoTheBackTranslation(
    container.read(salaSessionProvider.notifier),
    () => container.read(salaSessionProvider),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await waitFor(
    'a tradução voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).btTrechos.length ==
        contado.segments.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

Finder _aFrase(int n) => find.ancestor(
  of: find.descendant(of: find.byType(FraseList), matching: find.text('$n')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border != null &&
        (widget.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(16),
  ),
);

double _barra(WidgetTester tester, int n) => tester
    .widget<FractionallySizedBox>(
      find.descendant(
        of: _aFrase(n).first,
        matching: find.byType(FractionallySizedBox),
      ),
    )
    .widthFactor!;

Color _borda(WidgetTester tester, int n) =>
    ((tester.widget<Container>(_aFrase(n).first).decoration as BoxDecoration)
                .border!
            as Border)
        .top
        .color;

Color? _corDaBarra(WidgetTester tester, int n) =>
    (tester
                .widget<Container>(
                  find.descendant(
                    of: find.descendant(
                      of: _aFrase(n).first,
                      matching: find.byType(FractionallySizedBox),
                    ),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration)
        .color;

Color? _corDaPalavra(WidgetTester tester, int n, String palavra) => tester
    .widget<Text>(
      find.descendant(of: _aFrase(n).first, matching: find.text(palavra)),
    )
    .style
    ?.color;

Future<ProviderContainer> _quatroFrasesComAchados(
  WidgetTester tester,
  SalaHarness harness,
  List<BtFinding> achados,
) async {
  final container = await quatroFrasesEmWav(tester, harness);
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

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

void main() {
  testWidgets('a frase the room serves with no span fills its whole bar, '
      'not the sliver of a frase too short to see', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 0,
            frase: 2,
          ),
        ],
      ),
    );

    expect(
      _barra(tester, 2),
      1.0,
      reason:
          'uma frase sem trecho desenhava a lasca de 8% ao lado das outras, '
          'onde a dela enche a linha',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase of two seconds beside one of nine draws 22% of the '
      'bar, a whole percent as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 9000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 2000,
            frase: 2,
          ),
        ],
      ),
    );

    expect(
      _barra(tester, 2),
      0.22,
      reason: 'a barra media 22,2%, uma fração que a dela arredonda',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase on the part the room numbers 3 reads «parte 3», not '
      'its place in the list of parts', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-3',
            startsMs: 0,
            endsMs: 5000,
            frase: 2,
          ),
        ],
      ),
      partes: [1, 3],
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', 'parte 1', '2', 'parte 3'],
      reason:
          'a frase da parte 3 dizia «parte 2», o lugar dela na lista, e não a '
          'parte que a equipe gravou',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase on the part the room numbers 3 reads '
      '«parte 3» too', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-3',
        scope: 'parte-3',
        kind: 'ensaio',
        ordinal: 3,
      ),
    );
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-3',
            startsMs: 0,
            endsMs: 5000,
          ),
        ],
      ),
      partes: [1, 3],
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
        '1',
        'parte 1',
        '2',
        'parte 3',
        'regravada — traduzam de novo',
      ],
      reason:
          'a frase regravada da parte 3 dizia «parte 2», o lugar da parte na '
          'lista',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase told on an earlier visit keeps a live '
      'loudspeaker, not a dimmed one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-2',
        scope: 'parte-2',
        kind: 'ensaio',
        ordinal: 2,
      ),
    );
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
        stale: [
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-2',
            startsMs: 0,
            endsMs: 5000,
            bridgeTakeId: 'retro-2',
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
      tester
          .widget<FraseList>(find.byType(FraseList))
          .rows
          .singleWhere((row) => row.regravada)
          .onHear,
      isNotNull,
      reason:
          'a frase regravada contada numa visita anterior ficava com o '
          'alto-falante apagado, sem cópia da tradução no tablet',
    );
    closeTheRoom(container);
  });

  testWidgets('a «regravada» frase whose stretch carries a nuance before its '
      'missing finding still wears her blue', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.takes.add(
      const TakeView(
        takeId: 'gravacao-velha-3',
        scope: 'parte-3',
        kind: 'ensaio',
        ordinal: 3,
      ),
    );
    final container = await voltaATraducao(
      tester,
      harness,
      BackTranslationProgress(
        segments: const [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
        ],
        stale: const [
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-velha-3',
            startsMs: 0,
            endsMs: 5000,
          ),
        ],
        findings: BtFinding.listFrom({
          'findings': [
            {'kind': 'nuance', 'frase': 2, 'segment_id': 'trecho-2'},
            {'kind': 'missing', 'frase': 2, 'segment_id': 'trecho-2'},
          ],
        }),
      ),
      partes: [1, 3],
    );
    await waitFor(
      'a frase regravada achar a sua parte',
      () => container.read(salaSessionProvider).btTrechosRegravados.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    final cartao = find
        .ancestor(
          of: find.text('regravada — traduzam de novo'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.foregroundDecoration is DashedEdge,
          ),
        )
        .first;

    expect(
      (tester.widget<Container>(cartao).foregroundDecoration as DashedEdge?)
          ?.color,
      ShemaBrand.azul,
      reason:
          'a nuance sem tipo na frente do trecho deixava a frase regravada '
          'sem a cor do achado que veio depois',
    );
    expect(
      (tester
                  .widget<Container>(
                    find.descendant(
                      of: find.descendant(
                        of: cartao,
                        matching: find.byType(FractionallySizedBox),
                      ),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      ShemaBrand.azul,
    );
    closeTheRoom(container);
  });

  testWidgets('a frase the check found missing or unclear wears her blue on '
      'its bar, its border and its word, and an addition stays terracotta', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(tester, harness, const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
      BtFinding(kind: BtFindingKind.missing, frase: 3, segmentId: 'trecho-3'),
      BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
    ]);

    for (final (n, palavra) in [
      (3, 'faltou depois desta'),
      (4, 'não ficou claro'),
    ]) {
      expect(
        _borda(tester, n),
        ShemaBrand.azul,
        reason: 'todo achado vinha em telha, onde o dela é azul',
      );
      expect(_corDaBarra(tester, n), ShemaBrand.azul);
      expect(_corDaPalavra(tester, n, palavra), ShemaBrand.azul);
    }
    expect(_borda(tester, 2), ShemaBrand.telha);
    expect(_corDaBarra(tester, 2), ShemaBrand.telha);
    expect(_corDaPalavra(tester, 2, 'acrescentado'), ShemaBrand.telha);
    closeTheRoom(container);
  });

  testWidgets('a finding of a kind this tablet does not know still wears her '
      'blue mark with her fallback word, and one with no kind wears none', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(
      tester,
      harness,
      BtFinding.listFrom({
        'findings': [
          {'kind': 'repetition', 'frase': 2, 'segment_id': 'trecho-2'},
          {'frase': 3, 'segment_id': 'trecho-3'},
        ],
      }),
    );

    expect(
      _borda(tester, 2),
      ShemaBrand.azul,
      reason:
          'um achado de tipo desconhecido vinha sem marca, como se a frase '
          'estivesse limpa',
    );
    expect(_corDaBarra(tester, 2), ShemaBrand.azul);
    expect(_corDaPalavra(tester, 2, 'acrescentado'), ShemaBrand.azul);
    expect(_borda(tester, 3), isNot(ShemaBrand.azul));
    expect(
      find.descendant(
        of: _aFrase(3).first,
        matching: find.text('acrescentado'),
      ),
      findsNothing,
    );
    closeTheRoom(container);
  });

  testWidgets('a frase whose nuance comes before its missing finding still '
      'reads «faltou depois desta», as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(
      tester,
      harness,
      BtFinding.listFrom({
        'findings': [
          {'kind': 'nuance', 'frase': 2, 'segment_id': 'trecho-2'},
          {'kind': 'missing', 'frase': 2, 'segment_id': 'trecho-2'},
        ],
      }),
    );

    expect(
      find.descendant(
        of: _aFrase(2).first,
        matching: find.text('faltou depois desta'),
      ),
      findsOneWidget,
      reason:
          'uma nuance sem tipo na frente escondia o «faltou» da mesma frase, '
          'que a dela marca',
    );
    expect(_borda(tester, 2), ShemaBrand.azul);
    expect(_corDaBarra(tester, 2), ShemaBrand.azul);
    expect(_corDaPalavra(tester, 2, 'faltou depois desta'), ShemaBrand.azul);
    closeTheRoom(container);
  });

  testWidgets('a silence finding wears terracotta with «acrescentado», as her '
      'addition does, not the blue of a kind nobody knows', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(
      tester,
      harness,
      BtFinding.listFrom({
        'findings': [
          {'kind': 'silence', 'frase': 2, 'segment_id': 'trecho-2'},
        ],
      }),
    );

    expect(
      _borda(tester, 2),
      ShemaBrand.telha,
      reason: 'o silêncio preenchido vinha azul, e o dela é telha',
    );
    expect(_corDaBarra(tester, 2), ShemaBrand.telha);
    expect(_corDaPalavra(tester, 2, 'acrescentado'), ShemaBrand.telha);
    closeTheRoom(container);
  });

  testWidgets('the frase being translated again wears terracotta on its bar '
      'and its border, so the team sees which one the circle will tell', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(tester, harness, const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
    ]);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 1');

    expect(
      _borda(tester, 1),
      ShemaBrand.telha,
      reason:
          'a frase sendo traduzida de novo era igual às outras na lista, só o '
          'aviso dizia qual era',
    );
    expect(_corDaBarra(tester, 1), ShemaBrand.telha);
    expect(_borda(tester, 3), isNot(ShemaBrand.telha));
    closeTheRoom(container);
  });

  testWidgets('a frase found unclear and being translated again draws a '
      'terracotta bar inside the finding\'s blue border', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(tester, harness, const [
      BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
    ]);

    await tocar(tester, 'Ouvir esta frase de novo e traduzir de novo — 4');

    expect(_corDaBarra(tester, 4), ShemaBrand.telha);
    expect(
      _borda(tester, 4),
      ShemaBrand.azul,
      reason:
          'a frase do achado perdia o azul da borda ao ser traduzida de novo, '
          'e o achado ainda vale até a tradução nova pousar',
    );
    closeTheRoom(container);
  });

  testWidgets('the frase being recorded again wears a terracotta border and '
      'keeps its bar', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);

    await tocar(tester, 'regravar a frase 3');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      _borda(tester, 3),
      ShemaBrand.telha,
      reason:
          'a frase sendo regravada era igual às outras na lista, só o botão '
          'dizia qual era',
    );
    expect(_corDaBarra(tester, 3), _corDaBarra(tester, 1));
    expect(_corDaBarra(tester, 3), isNot(ShemaBrand.telha));
    closeTheRoom(container);
  });

  testWidgets('a frase found unclear and being recorded again keeps its blue '
      'bar inside a terracotta border', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComAchados(tester, harness, const [
      BtFinding(kind: BtFindingKind.unclear, frase: 4, segmentId: 'trecho-4'),
    ]);

    await tocar(tester, 'regravar a frase 4');
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      _borda(tester, 4),
      ShemaBrand.telha,
      reason:
          'a borda azul do achado escondia que era essa a frase sendo '
          'regravada',
    );
    expect(_corDaBarra(tester, 4), ShemaBrand.azul);
    closeTheRoom(container);
  });

  testWidgets('a frase that awaits its translation stays terracotta even when '
      'the room still names it unclear', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
            frase: 1,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 5000,
            frase: 2,
          ),
        ],
        findings: [
          BtFinding(
            kind: BtFindingKind.unclear,
            frase: 2,
            segmentId: 'trecho-2',
          ),
        ],
        awaitingSegmentId: 'trecho-2',
      ),
    );

    expect(
      _borda(tester, 2),
      ShemaBrand.telha,
      reason:
          'a frase que aguarda a tradução ficava azul pelo achado de antes, e o '
          'telha que diz «traduzam esta frase» sumia',
    );
    expect(_corDaBarra(tester, 2), ShemaBrand.telha);
    expect(
      _corDaPalavra(tester, 2, 'regravada — traduzam esta frase'),
      ShemaBrand.telha,
    );
    closeTheRoom(container);
  });

  for (final (look, numero) in [
    (Brightness.light, const Color(0xFFF6F5EB)),
    (Brightness.dark, const Color(0xFF1E1B15)),
  ]) {
    testWidgets('in the ${look.name} look the frase awaiting its translation '
        'numbers itself on a terracotta disc, not the sand one', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = look;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await voltaATraducao(
        tester,
        harness,
        const BackTranslationProgress(
          segments: [
            SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-1',
              startsMs: 0,
              endsMs: 4000,
              frase: 1,
            ),
            SegmentView(
              segmentId: 'trecho-2',
              takeId: 'gravacao-2',
              startsMs: 0,
              endsMs: 5000,
              frase: 2,
            ),
          ],
          awaitingSegmentId: 'trecho-2',
        ),
      );
      final telha = look == Brightness.dark
          ? const Color(0xFFD6612A)
          : const Color(0xFFBE4A01);
      final disco = find
          .ancestor(
            of: find.descendant(of: _aFrase(2).first, matching: find.text('2')),
            matching: find.byType(DecoratedBox),
          )
          .first;

      expect(
        (tester.widget<DecoratedBox>(disco).decoration as BoxDecoration).color,
        telha,
        reason: 'a frase que aguarda tinha o disco de areia das outras',
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: _aFrase(2).first, matching: find.text('2')),
            )
            .style
            ?.color,
        numero,
        reason: 'no disco telha o número dela é o branco da página',
      );
      closeTheRoom(container);
    });
  }
}
