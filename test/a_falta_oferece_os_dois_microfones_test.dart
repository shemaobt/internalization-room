import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

const ouvirMaterna = 'Ouvir a voz de vocês, na língua materna';
const ouvirRetro = 'Ouvir a tradução em português';
const microfoneAzul = 'Continuar o ensaio';

Finder byLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

SalaSessionNotifier notifier(ProviderContainer c) =>
    c.read(salaSessionProvider.notifier);

/// A team that told two stretches back and got a finding on the first.
Future<ProviderContainer> pumpToPergunta(
  WidgetTester tester, {
  required BtFindingKind finding,
  String? trecho = 'trecho-1',
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictFinding = finding
    ..room.verdictFindingSegmentId = trecho;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final n = container.read(salaSessionProvider.notifier);
  await n.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  n.goEnsaio();
  n.ensaioTap();
  n.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  n.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  n.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    n.cortarTrecho();
    await tester.pump(const Duration(milliseconds: 200));
    n.retroTap();
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await n.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  testWidgets('falta com endereço mostra os dois microfones', (tester) async {
    await pumpToPergunta(tester, finding: BtFindingKind.missing);

    expect(byLabel(micRetroLabel), findsOneWidget,
        reason: 'a materna pode já ter a parte; só a ponte pulou a frase, e a '
            'equipe sabe se é o caso — não a tela por ela');
    expect(byLabel(micParteLabel), findsOneWidget);
    expect(byLabel('Regravar esta parte e contá-la de novo'), findsNothing,
        reason: 'a falta com endereço não passa mais por um caminho à parte '
            'que esconde a escolha entre as duas vozes');
  });

  testWidgets('só a ponte funciona', (tester) async {
    final container = await pumpToPergunta(tester, finding: BtFindingKind.missing);

    await tester.tap(byLabel(micRetroLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing,
        reason: 'tocar o microfone só-ponte abre a captura do traduzir de novo, sem '
            'tocar a voz materna');
  });

  testWidgets('a madeira leva ao ensaio, a gravar a parte de novo', (tester) async {
    final container = await pumpToPergunta(tester, finding: BtFindingKind.missing);

    await tester.tap(byLabel(micParteLabel));
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio,
        reason: 'a voz de madeira que a equipe escolhe é a da parte inteira: o '
            'microfone por trecho saiu da tela, e o que fica é o ensaio');
  });

  testWidgets('falta sem endereço continua indo ao ensaio', (tester) async {
    final container = await pumpToPergunta(
      tester,
      finding: BtFindingKind.missing,
      trecho: null,
    );

    expect(byLabel(microfoneAzul), findsOneWidget,
        reason: 'sem trecho apontado não há o que regravar — a saída continua '
            'sendo o ensaio inteiro, como hoje');
    expect(byLabel(micRetroLabel), findsNothing);
    expect(byLabel(micParteLabel), findsNothing);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
  });

  testWidgets('os outros achados não mudam', (tester) async {
    await pumpToPergunta(tester, finding: BtFindingKind.unclear);

    expect(byLabel(micParteLabel), findsOneWidget);
    expect(byLabel(micRetroLabel), findsOneWidget);
    expect(byLabel(ouvirMaterna), findsOneWidget);
    expect(byLabel(ouvirRetro), findsOneWidget);
  });
}
