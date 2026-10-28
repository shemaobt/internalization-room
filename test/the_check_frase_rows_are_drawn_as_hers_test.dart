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
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _voltaATraducao(
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
  harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
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
        container.read(salaSessionProvider).stage == SalaStage.retro &&
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

void main() {
  testWidgets('a frase the room serves with no span fills its whole bar, '
      'not the sliver of a frase too short to see', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
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
}
