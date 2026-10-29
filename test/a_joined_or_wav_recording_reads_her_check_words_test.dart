import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'support/temp.dart';

const _herSubVerdict =
    'Toquem numa frase para ouvir e traduzir de novo; toquem em regravar para '
    'gravar a frase inteira de novo; depois toquem em \'terminei\'.';

const _plainSubVerdict =
    'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar uma '
    'parte; ou toquem em terminei para conferir de novo.';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _voltaAUmaTraducao(
  WidgetTester tester,
  SalaHarness harness, {
  required String extension,
  required bool juntada,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = aTempDir('sala-1806');
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.$extension',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
          origin: juntada ? 'ensaio-da-cena-$n' : null,
        ),
    ],
  );
  harness.room.retroSoFar = const BackTranslationProgress(
    checked: true,
    segments: [
      SegmentView(
        segmentId: 'trecho-1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 5000,
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
    'a tradução voltar com as duas frases',
    () =>
        container.read(salaSessionProvider).btTrechos.length == 2 &&
        container.read(salaSessionProvider).btPhase == BtPhase.conferida,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _recomecar = 'recomeçar a tradução';

void main() {
  testWidgets('a verdict on a joined recording reads her sentence line, not '
      'the line about going back to re-record a part', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: true,
    );

    expect(
      find.text(_herSubVerdict),
      findsOneWidget,
      reason: 'numa gravação juntada a linha ainda mandava voltar a uma parte',
    );
    expect(find.text(_plainSubVerdict), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('on a phone as narrow as the iPhone SE her sentence line keeps '
      'the margin the frase rows keep, not the screen edge', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: true,
    );
    tester.view.physicalSize = const Size(375, 2400);
    await _passo(tester);

    final linha = tester.getRect(find.text(_herSubVerdict));
    expect(
      linha.left,
      16,
      reason: 'a linha encostava na borda esquerda do iPhone SE',
    );
    expect(
      linha.right,
      375 - 16,
      reason: 'a linha encostava na borda direita do iPhone SE',
    );
    closeTheRoom(container);
  });

  testWidgets('a verdict on a recording with a wav part reads her sentence '
      'line even when nothing was joined', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'wav',
      juntada: false,
    );

    expect(
      find.text(_herSubVerdict),
      findsOneWidget,
      reason:
          'a linha mandava voltar a uma parte onde a linha oferece regravar',
    );
    expect(find.text(_plainSubVerdict), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a verdict on a recording no join touched and no wav part is '
      'in keeps the line it had', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: false,
    );

    expect(
      find.text(_plainSubVerdict),
      findsOneWidget,
      reason: 'a linha dela passava a valer onde a linha não oferece regravar',
    );
    expect(find.text(_herSubVerdict), findsNothing);
    closeTheRoom(container);
  });

  test('her sentence line is worded the same in english, and the plain one '
      'keeps its english', () {
    expect(
      retroLabelFor('subVerdictSentence', 'en'),
      'Tap a sentence to hear it and translate it again; tap re-record to '
      'record the whole sentence again; then tap \'done\'.',
    );
    expect(
      retroLabelFor('subVerdict', 'en'),
      'Tap a sentence to hear it and translate it again; go back to re-record '
      'a part; or tap done to check again.',
    );
  });

  testWidgets('the first tap of a restart on a joined recording says the '
      'translations leave the screen, in her words', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: true,
    );

    await tester.tap(byLabel(_recomecar));
    await _passo(tester);

    expect(
      find.text(
        'toquem de novo: as 2 traduções saem da tela e vocês traduzem a '
        'passagem inteira de novo',
      ),
      findsOneWidget,
      reason: 'o toque armado falava em apagar frases de um ensaio',
    );
    expect(harness.room.restartsAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('a restart done on a joined recording says the recording of the '
      'passage stays, in her words', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: true,
    );

    await tester.tap(byLabel(_recomecar));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(
      byLabel(
        'toquem de novo: as 2 traduções saem da tela e vocês traduzem a '
        'passagem inteira de novo',
      ),
    );
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('tradução recomeçada — a gravação da passagem ficou'),
      findsOneWidget,
      reason: 'a nota falava do ensaio da passagem onde só ficou a gravação',
    );
    closeTheRoom(container);
  });

  testWidgets('on a phone as narrow as the iPhone SE the note that the '
      'recording stays keeps the margin the frase rows keep, not the screen '
      'edge', (tester) async {
    final harness = SalaHarness(
      filaEmMemoria: true,
      restartLapse: const Duration(minutes: 1),
    );
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'm4a',
      juntada: true,
    );
    tester.view.physicalSize = const Size(375, 2400);
    await _passo(tester);

    await tester.tap(byLabel(_recomecar));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(
      byLabel(
        'toquem de novo: as 2 traduções saem da tela e vocês traduzem a '
        'passagem inteira de novo',
      ),
    );
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    final nota = tester.getRect(
      find.text('tradução recomeçada — a gravação da passagem ficou'),
    );
    expect(
      nota.left,
      16,
      reason: 'a nota encostava na borda esquerda do iPhone SE',
    );
    expect(
      nota.right,
      375 - 16,
      reason: 'a nota encostava na borda direita do iPhone SE',
    );
    closeTheRoom(container);
  });

  testWidgets('a restart on a hand-recorded wav recording keeps the words it '
      'had, because only a join changes them', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      extension: 'wav',
      juntada: false,
    );

    await tester.tap(byLabel(_recomecar));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.text('toque de novo para apagar as 2 frases traduzidas'),
      findsOneWidget,
      reason: 'o wav gravado à mão passava a falar de uma gravação juntada',
    );
    await tester.tap(
      byLabel('toque de novo para apagar as 2 frases traduzidas'),
    );
    await waitFor(
      'a tradução recomeçar',
      () => container.read(salaSessionProvider).btTrechos.isEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('tradução recomeçada — o ensaio da passagem ficou'),
      findsOneWidget,
      reason: 'o wav gravado à mão passava a falar de uma gravação juntada',
    );
    closeTheRoom(container);
  });

  test('her restart lines are worded the same in english', () {
    expect(
      retroLabelFor('restartArmedJoined', 'en', n: 4),
      'tap again: the 4 translations leave the screen and you translate the '
      'whole passage again',
    );
    expect(
      retroLabelFor('restartedJoined', 'en'),
      'translation started over — the passage recording stays',
    );
  });
}
