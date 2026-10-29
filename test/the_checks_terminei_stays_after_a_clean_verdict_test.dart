import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tocar,
        tocarNoCirculo;

void main() {
  testWidgets('after a clean verdict the terminei stays on the check instead '
      'of leaving it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await contarAteOFimDaParte(tester, harness);
    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(
      byLabel(conferir),
      findsOneWidget,
      reason: 'o veredito limpo tirava o terminei da tela; o dela fica',
    );
    closeTheRoom(container);
  });
}
