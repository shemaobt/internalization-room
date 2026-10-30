import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, traduzirOApontadoDeNovo;

const retellStretchExit = 'Ouvir e traduzir esta parte de novo';
const wholeClipExit = 'Ouvir e traduzir a gravação de novo';
const continuarOEnsaio = 'Continuar o ensaio';
const regravarAFrase1 = 'regravar a frase 1';

Future<ProviderContainer> pumpToFindings(
  WidgetTester tester,
  bool hasFinding, {
  String? trecho,
  SalaHarness? harness,
}) async {
  harness ??= SalaHarness(filaEmMemoria: true);
  harness
    ..recorder.rehearsalSpeaks = aSpokenWav()
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
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  notifier.retroTap();
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
  testWidgets(
    'the retro opens on a part the room has named, not on one still in the air',
    (tester) async {
      final container = await pumpToFindings(
        tester,
        true,
        harness: SalaHarness(filaEmMemoria: true)
          ..room.takeLandsInRealTime = const Duration(milliseconds: 300),
      );

      expect(
        container.read(salaSessionProvider).partes.single.takeId,
        'gravacao-1',
        reason:
            'a parte entrava no retro antes de a sala dar o nome, e o '
            'trecho contado de volta não tinha de quem ser',
      );
    },
  );

  testWidgets('a verdict that names no stretch draws no disc to record more, '
      'and offers the frase\'s whole sentence instead', (tester) async {
    final container = await pumpToFindings(tester, true);

    expect(
      byLabel(continuarOEnsaio),
      findsNothing,
      reason:
          'o disco mandava a equipe gravar mais depois da última frase, o '
          'caminho que ela tirou',
    );
    expect(byLabel(regravarAFrase1), findsOneWidget);
    expect(
      tester.widget<Semantics>(byLabel(regravarAFrase1)).properties.enabled,
      isTrue,
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
  });

  testWidgets('a verdict that names a stretch still tells that stretch again', (
    tester,
  ) async {
    final container = await pumpToFindings(tester, true, trecho: 'trecho-1');

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect(
      (estado.btPhase, estado.btTrechoTraduzidoDeNovo?.segmentId),
      (BtPhase.playing, 'trecho-1'),
      reason:
          'contar o trecho de novo continua sendo uma saída depois do '
          'veredito; a equipe a escolhe pela frase, que leva à tradução '
          'com aquele trecho armado (ADR 0040)',
    );
  });

  testWidgets('re-recording stays on offer when no stretch was named, as the '
      'whole sentence of a frase and never as more after the last', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await pumpToFindings(tester, true, harness: harness);

    await tester.ensureVisible(byLabel(regravarAFrase1));
    await tester.tap(byLabel(regravarAFrase1));
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect(estado.btRegravacao?.segmentId, 'trecho-1');
    expect(estado.stage, SalaStage.retro);
  });

  testWidgets('a finding only re-recording can settle, with no stretch named, '
      'still leaves a way out that works', (tester) async {
    final container = await pumpToFindings(tester, true);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);

    expect(container.read(salaSessionProvider).btVeredito, isTrue);
    final offered = [
      retellStretchExit,
      wholeClipExit,
      continuarOEnsaio,
      regravarAFrase1,
    ].where((label) => byLabel(label).evaluate().isNotEmpty).toList();
    expect(
      offered,
      [regravarAFrase1],
      reason:
          'as duas regras valem juntas aqui. A adição pertence à '
          'gravação, e traduzir de novo não tira dela o que a equipe pôs — '
          'nem um trecho, nem a gravação inteira: as duas são a mesma '
          'família de saída, e o ponteiro do achado não muda qual família '
          'responde ao tipo dele. Sobra regravar, que é a mesma saída que a '
          'sala já oferece para uma adição COM trecho apontado — a frase '
          'inteira, nunca um disco para gravar mais',
    );

    for (final label in offered) {
      final harness = SalaHarness(filaEmMemoria: true);
      final room = await pumpToFindings(tester, true, harness: harness);
      final before = room.read(salaSessionProvider);
      await tester.ensureVisible(byLabel(label));
      await tester.tap(byLabel(label));
      await tester.pump(const Duration(milliseconds: 300));
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      final after = room.read(salaSessionProvider);
      expect(
        after.btPhase != before.btPhase ||
            after.stage != before.stage ||
            after.btRegravacao != before.btRegravacao,
        isTrue,
        reason: '"$label" was offered and did nothing',
      );
    }
  });
}
