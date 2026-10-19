import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle;
import 'session_notifier_test.dart'
    show inConversaWithoutPausing, tellTwoStretches;

const _recomecar = 'recomeçar a tradução';
const _armado = 'toque de novo para apagar as 4 frases traduzidas';

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

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  List<SegmentView> frases,
) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1223');
  addTearDown(() => pasta.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
        ),
    ],
  );
  harness.room.retroSoFar = BackTranslationProgress(segments: frases);
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
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length == frases.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

void main() {
  testWidgets(
    'the screen offers «recomeçar a tradução» under the frases, and not before there is one',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      expect(
        byLabel(_recomecar),
        findsOneWidget,
        reason: 'não havia como recomeçar a tradução sem gravar de novo',
      );
      expect(
        find.text(_recomecar),
        findsOneWidget,
        reason: 'a palavra dela fica escrita no botão',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the first tap only arms it, and the button says what the second one costs',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);

      expect(
        find.text(_armado),
        findsOneWidget,
        reason: 'um toque só apagava as frases sem dizer o custo',
      );
      expect(byLabel(_armado), findsOneWidget);
      expect(harness.room.restartsAsked, isEmpty);
      expect(container.read(salaSessionProvider).btTrechos, hasLength(4));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a second tap before 0.6 s is the same touch, and starts nothing over',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byLabel(_armado));
      await _passo(tester);

      expect(
        harness.room.restartsAsked,
        isEmpty,
        reason: 'um toque duplo apagava as frases sem a equipe decidir',
      );
      expect(find.text(_armado), findsOneWidget);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'one tap and then seven seconds of nothing leave it disarmed, with nothing changed',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);
      await tester.pump(const Duration(seconds: 7));

      expect(
        find.text(_recomecar),
        findsOneWidget,
        reason: 'o botão ficava armado para sempre, e um toque tardio apagava',
      );
      expect(find.text(_armado), findsNothing);
      expect(harness.room.restartsAsked, isEmpty);
      expect(container.read(salaSessionProvider).btTrechos, hasLength(4));
      closeTheRoom(container);
    },
  );

  testWidgets('with no frase told there is nothing to start over', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await _voltaATraducao(tester, harness, const []);

    expect(byLabel(_recomecar), findsNothing);
    closeTheRoom(container);
  });

  test(
    'a second tap starts the translation over: the frases go, P1 is said, and the next frase is the first of part 1',
    () async {
      final harness = SalaHarness();
      final container = await inConversaWithoutPausing(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await tellTwoStretches(harness, container);

      notifier.recomecarATraducao();
      await settle(const Duration(milliseconds: 700));
      notifier.recomecarATraducao();
      await waitFor(
        'a tradução recomeçar',
        () =>
            harness.room.restartsAsked.isNotEmpty &&
            container.read(salaSessionProvider).btTrechos.isEmpty,
      );

      expect(harness.room.restartsAsked, hasLength(1));
      expect(
        container.read(salaSessionProvider).btTrechos,
        isEmpty,
        reason: 'as frases de antes continuavam na tela depois do recomeço',
      );
      await waitFor(
        'a voz dizer P1',
        () => harness.voice.fixedLines.any((line) => line.$1 == 'P1'),
      );
      expect(
        [for (final line in harness.voice.fixedLines) line.$1],
        contains('P1'),
        reason: 'o recomeço não dizia a instrução de traduzir',
      );

      await waitFor(
        'o clipe voltar a rodar',
        () => container.read(salaSessionProvider).canCut,
      );
      final enviados = harness.room.chunkSpans.length;
      harness.playback.at = const Duration(seconds: 5);
      notifier.cortarTrecho();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await waitFor(
        'a primeira frase do recomeço chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 1,
      );

      expect(
        harness.room.chunkSpans.sublist(enviados).first,
        startsWith('0-'),
        reason: 'a frase nova começava onde a antiga terminava',
      );
      expect(
        container.read(salaSessionProvider).btTrechos.single.frase,
        1,
        reason: 'a numeração continuava de onde parou',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    },
  );
}
