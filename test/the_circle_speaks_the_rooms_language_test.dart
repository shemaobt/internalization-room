import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

void main() {
  // Red until `languages` stops listing es, which #138 does.
  test('a circle state missing a language the room offers fails the guard, '
      'not silently speaks portuguese', () {
    final offered = languages.toSet();
    for (final state in circleLabels.keys) {
      expect(
        circleLabels[state]!.keys.toSet(),
        offered,
        reason:
            'um estado sem rótulo numa língua que a sala oferece '
            'vazaria essa língua em silêncio, sem teste nenhum pegando',
      );
    }
  });

  testWidgets(
    'conversa speaks english to an english room, not the portuguese default',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
      container.read(salaSessionProvider.notifier).goConversa();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(bySemanticsLabelWidget('Tap to speak'), findsOneWidget);
      expect(
        bySemanticsLabelWidget('Tocar para falar'),
        findsNothing,
        reason:
            'o rótulo do círculo era sempre em português, mesmo com o '
            'aparelho em inglês',
      );
    },
  );
}
