import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const retellStretchExit = 'Ouvir e traduzir esta parte de novo';
const wholeClipExit = 'Ouvir e traduzir a gravação de novo';
const continuarOEnsaio = 'Continuar o ensaio';

Future<ProviderContainer> pumpToFindings(
  WidgetTester tester,
  bool hasFinding, {
  String? trecho,
  SalaHarness? harness,
}) async {
  harness ??= SalaHarness(filaEmMemoria: true);
  harness
    ..room.verdictChecked = false
    ..room.verdictHasFinding = hasFinding
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
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets('a verdict that names no stretch leaves the rehearsal standing', (
    tester,
  ) async {
    final container = await pumpToFindings(tester, true);
    final rehearsed = container.read(salaSessionProvider).partes.length;
    expect(rehearsed, greaterThan(0));

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).partes.length, rehearsed);
  });

  testWidgets('a verdict that names a stretch still tells that stretch again', (
    tester,
  ) async {
    final container = await pumpToFindings(tester, true, trecho: 'trecho-1');

    await tester.tap(byLabel('Traduzir este trecho de novo'));
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect(
      (estado.btPhase, estado.btTrechoTraduzidoDeNovo?.segmentId),
      (BtPhase.playing, 'trecho-1'),
      reason:
          'contar o trecho de novo continua sendo uma saída da tela de '
          'achados; a equipe a escolhe pelo microfone azul, que leva à '
          'tradução com aquele trecho armado (ADR 0040)',
    );
  });

  testWidgets('re-recording stays on offer when no stretch was named', (
    tester,
  ) async {
    final container = await pumpToFindings(tester, true);

    await tester.tap(byLabel(continuarOEnsaio));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  });

  testWidgets('a finding only re-recording can settle, with no stretch named, '
      'still leaves a way out that works', (tester) async {
    final container = await pumpToFindings(tester, true);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    final offered = [
      retellStretchExit,
      wholeClipExit,
      continuarOEnsaio,
    ].where((label) => byLabel(label).evaluate().isNotEmpty).toList();
    expect(
      offered,
      [continuarOEnsaio],
      reason:
          'as duas regras valem juntas aqui. A adição pertence à '
          'gravação, e traduzir de novo não tira dela o que a equipe pôs — '
          'nem um trecho, nem a gravação inteira: as duas são a mesma '
          'família de saída, e o ponteiro do achado não muda qual família '
          'responde ao tipo dele. Sobra regravar, que é a mesma saída que a '
          'sala já oferece para uma adição COM trecho apontado',
    );

    for (final label in offered) {
      final room = await pumpToFindings(tester, true);
      final before = room.read(salaSessionProvider);
      await tester.tap(byLabel(label));
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
