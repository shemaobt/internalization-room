import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aprovar,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tocar,
        tocarNoCirculo;

Future<ProviderContainer> _conferidaPelaSala(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await contarAteOFimDaParte(tester, harness);
  harness.room.readsChecked = true;
  await tocar(tester, conferir);
  await tester.pump(const Duration(milliseconds: 600));
  expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
  expect(container.read(salaSessionProvider).btChecked, isTrue);
  return container;
}

SalaSessionNotifier _sala(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

void main() {
  testWidgets('a telling the room calls checked keeps the approve button while '
      'a frase is armed to be told again, not only at the verdict', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);

    _sala(container).traduzirAFraseDeNovo(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(
      byLabel(aprovar),
      findsOneWidget,
      reason:
          'o botão só existia na fase conferida; o dela fica em toda a vista '
          'de contar enquanto a sala diz conferida',
    );
    closeTheRoom(container);
  });

  testWidgets('the first listen of a checked passage offers no approval, as '
      'her listen step does not', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _conferidaPelaSala(tester, harness);
    harness.room.listeningUnheardTakeIds = [
      container.read(salaSessionProvider).partes.single.takeId!,
    ];

    _sala(container).leaveTheBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    _sala(container).startRetro();
    await waitFor(
      'a primeira escuta abrir',
      () => container.read(salaSessionProvider).btSoOuvir,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(container.read(salaSessionProvider).btSoOuvir, isTrue);
    expect(container.read(salaSessionProvider).btChecked, isTrue);
    expect(
      byLabel(aprovar),
      findsNothing,
      reason:
          'a sala conferida punha o botão de aprovar em cima da primeira '
          'escuta, que no dela é o passo de ouvir, sem aprovar',
    );
    closeTheRoom(container);
  });
}
