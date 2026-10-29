import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const micParteLabel = 'voltar e regravar uma parte';
const continuarOEnsaio = 'Continuar o ensaio';

SalaSessionNotifier notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// A team that told two stretches back and got a finding on the first.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  String? trecho = 'trecho-1',
  Duration? takeLandsInRealTime,
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
    ..room.verdictFindingSegmentId = trecho
    ..room.takeLandsInRealTime = takeLandsInRealTime;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final n = container.read(salaSessionProvider.notifier);
  await n.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  n.goEnsaio();
  n.ensaioTap();
  n.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  n.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  n.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    n.retroTap();
    n.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await n.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets(
    'the retro opens on a part the room has named, not on one still in the air',
    (tester) async {
      final container = await pumpToPergunta(
        tester,
        takeLandsInRealTime: const Duration(milliseconds: 300),
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

  testWidgets('falta com endereço mostra a volta ao ensaio', (tester) async {
    await pumpToPergunta(tester);

    expect(byLabel(micParteLabel), findsOneWidget);
    expect(
      byLabel('Regravar esta parte e contá-la de novo'),
      findsNothing,
      reason:
          'a falta com endereço não passa mais por um caminho à parte '
          'que esconde a escolha entre as duas vozes',
    );
  });

  testWidgets('a madeira leva ao ensaio, a gravar a parte de novo', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester);

    await tester.ensureVisible(byLabel(micParteLabel));
    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason:
          'a voz de madeira que a equipe escolhe é a da parte inteira: o '
          'microfone por trecho saiu da tela, e o que fica é o ensaio',
    );
  });

  testWidgets('falta sem endereço não oferece gravar depois da última frase', (
    tester,
  ) async {
    final container = await pumpToPergunta(tester, trecho: null);

    expect(
      byLabel(continuarOEnsaio),
      findsNothing,
      reason:
          'a falta se conserta na frase onde cabe, nunca gravando mais '
          'depois da última',
    );
    expect(
      tester.widget<Semantics>(byLabel(micParteLabel)).properties.enabled,
      isTrue,
      reason: 'sem trecho, a volta à casa ficava apagada; a dela não',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(container.read(salaSessionProvider).btVeredito, isTrue);
  });
}
