import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

void main() {
  test(
    'a frame that lands while the voice speaks lights no bead until the line ends',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
        ..room.turnIdInResponse = 'turno-1';
      harness.voice.holdNextLine();
      final container = harness.container();
      addTearDown(container.dispose);
      int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

      final opening = container.read(salaSessionProvider.notifier).goConversa();
      await waitFor(
        'a fala do Guia começar',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      harness.room.pushCoverage(
        CoverageEvent(
          turnId: 'turno-1',
          status: CoverageStatus.settled,
          coverage: coverage(engaged: 3, surfaced: 3),
        ),
      );
      await waitFor(
        'o aviso chegar e pedir o estado',
        () =>
            harness.room.calls.where((call) => call == 'fetchState').length ==
            1,
      );
      await settle();

      expect(
        lit(),
        0,
        reason:
            'o aviso acendia as contas no meio da fala — o time via o colar '
            'se mexer enquanto ainda ouvia a voz',
      );

      harness.voice.finishHeldLine();
      await opening;

      expect(
        lit(),
        3,
        reason:
            'terminada a fala, as contas que o aviso trouxe assentam na pausa',
      );
    },
  );
}
