import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const retellStretchExit = 'Ouvir e contar esta parte de novo';
const wholeClipExit = 'Ouvir e contar a gravação de novo';
const reRecordExit = 'Gravar esta parte de novo';

Finder bySemanticsLabelWidget(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

Future<ProviderContainer> pumpToFindings(
  WidgetTester tester,
  BtFindingKind? finding, {
  String? trecho,
  SalaHarness? harness,
}) async {
  harness ??= SalaHarness(filaEmMemoria: true);
  harness
    ..room.verdictChecked = false
    ..room.verdictFinding = finding
    ..room.verdictFindingSegmentId = trecho;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets('a verdict that names no stretch leaves the rehearsal standing',
      (tester) async {
    final container = await pumpToFindings(
      tester,
      BtFindingKind.unclear,
    );
    final rehearsed = container.read(salaSessionProvider).partes.length;
    expect(rehearsed, greaterThan(0));

    await tester.tap(bySemanticsLabelWidget(wholeClipExit));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).partes.length, rehearsed);
  });

  testWidgets('a verdict that names no stretch offers a path that works',
      (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await pumpToFindings(
      tester,
      BtFindingKind.unclear,
      harness: harness,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    await tester.tap(bySemanticsLabelWidget(wholeClipExit));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);

    // The cut is made past the ten seconds already told back, not at nought. Cutting at
    // nought used to work because this exit forgot every stretch and started the clip
    // over — and the room had not forgotten them, so the analyst received the passage
    // twice, the old stretches concatenated with the new. The stretches stay now, and
    // the exit only takes a cut over ground nobody has told back yet.
    harness.playback.at = const Duration(seconds: 20);
    notifier.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
  });

  testWidgets('a verdict that names a stretch still tells that stretch again',
      (tester) async {
    final container = await pumpToFindings(
      tester,
      BtFindingKind.addition,
      trecho: 'trecho-1',
    );

    await tester.tap(bySemanticsLabelWidget('Recontar só em português'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'contar o trecho de novo continua sendo uma saída da tela de '
            'achados; deixou de ser a sala escolhendo-a pela equipe e passou a '
            'ser a voz azul da grade, que a equipe toca — e ela abre o '
            'microfone direto, sem passo intermediário');
  });

  testWidgets('re-recording stays on offer when no stretch was named',
      (tester) async {
    final container = await pumpToFindings(
      tester,
      BtFindingKind.unclear,
    );

    await tester.tap(bySemanticsLabelWidget(reRecordExit));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  });

  testWidgets('a finding only re-recording can settle, with no stretch named, '
      'still leaves a way out that works', (tester) async {
    final container = await pumpToFindings(tester, BtFindingKind.addition);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    final offered = [retellStretchExit, wholeClipExit, reRecordExit]
        .where((label) => bySemanticsLabelWidget(label).evaluate().isNotEmpty)
        .toList();
    expect(offered, [reRecordExit],
        reason: 'as duas regras valem juntas aqui. A adição pertence à '
            'gravação, e contar de novo não tira dela o que a equipe pôs — '
            'nem um trecho, nem a gravação inteira: as duas são a mesma '
            'família de saída, e o ponteiro do achado não muda qual família '
            'responde ao tipo dele. Sobra regravar, que é a mesma saída que a '
            'sala já oferece para uma adição COM trecho apontado');

    for (final label in offered) {
      final room = await pumpToFindings(tester, BtFindingKind.addition);
      final before = room.read(salaSessionProvider);
      await tester.tap(bySemanticsLabelWidget(label));
      await tester.pump(const Duration(milliseconds: 300));
      final after = room.read(salaSessionProvider);
      expect(
        after.btPhase != before.btPhase || after.stage != before.stage,
        isTrue,
        reason: '"$label" was offered and did nothing',
      );
    }
  });
}
