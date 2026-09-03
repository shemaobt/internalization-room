import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart'
    show aHistoriaSemOFim, byLabel, irParaARetro, microfoneAzul;

const instrucaoPt =
    'Gravem o que ainda falta da história. Quando terminarem, toquem no verde.';
const instrucaoEn =
    'Record what is still missing from the story. When you finish, tap the green button.';
const instrucaoEs =
    'Graben lo que aún falta de la historia. Cuando terminen, toquen el verde.';

/// The team came back to the rehearsal through the blue microphone — the only route that
/// preserves what was already recorded and told, rather than starting the passage over.
Future<void> _voltaAoEnsaioPeloAzul(WidgetTester tester) async {
  await tester.tap(byLabel(microfoneAzul));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('ensaio retomado da retro mostra a instrução', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await aHistoriaSemOFim(tester, harness);

    await _voltaAoEnsaioPeloAzul(tester);

    expect(
      find.text(instrucaoPt),
      findsOneWidget,
      reason:
          'o narrador disse que dava para seguir gravando, mas a tela ficava muda; '
          'a instrução escrita é o que falta para a equipe entender os botões',
    );
  });

  testWidgets('a instrução aparece no idioma da sala: inglês', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    await aHistoriaSemOFim(tester, harness);

    await _voltaAoEnsaioPeloAzul(tester);

    expect(find.text(instrucaoEn), findsOneWidget);
  });

  testWidgets('a instrução aparece no idioma da sala: espanhol', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'es');
    await aHistoriaSemOFim(tester, harness);

    await _voltaAoEnsaioPeloAzul(tester);

    expect(find.text(instrucaoEs), findsOneWidget);
  });

  testWidgets('o ensaio inicial não mostra nenhuma instrução', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
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

    expect(find.text(instrucaoPt), findsNothing);
    expect(find.text(instrucaoEn), findsNothing);
    expect(find.text(instrucaoEs), findsNothing);
  });

  testWidgets('a instrução some quando a tela avança para a retrotradução', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await aHistoriaSemOFim(tester, harness);
    await _voltaAoEnsaioPeloAzul(tester);
    expect(find.text(instrucaoPt), findsOneWidget);

    await tester.tap(byLabel(irParaARetro));
    // Three short pumps, not one long one: the cross-fade between screens only starts
    // reversing on the frame after the tap's rebuild, so a single pump misses it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text(instrucaoPt),
      findsNothing,
      reason: 'a tela de ensaio inteira saiu da árvore ao avançar',
    );
  });

  testWidgets('a instrução é lida por quem usa leitor de tela, não só vista', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    await aHistoriaSemOFim(tester, harness);

    await _voltaAoEnsaioPeloAzul(tester);
    // The cross-fade between screens settles a few frames after the 400ms it takes to
    // reach the ensaio screen; the semantics tree only carries the label once it has.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final semantics = tester.getSemantics(find.text(instrucaoPt));
    expect(
      semantics.label,
      instrucaoPt,
      reason:
          'sem Text visível, a instrução seria só Semantics, e a marca '
          "d'água some do relatório de acessibilidade",
    );
    handle.dispose();
  });
}
