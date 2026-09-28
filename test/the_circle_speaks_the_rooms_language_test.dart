import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

void main() {
  // Red until `languages` stops listing es, which #138 does.
  test('a label in any table missing a language the room offers fails the '
      'guard, not silently speaks portuguese', () {
    final offered = languages.toSet();
    final tables = {
      'circleLabels': circleLabels,
      'retroLabels': retroLabels,
      'rehearsalLabels': rehearsalLabels,
      'findingLabels': findingLabels,
      'conviteLabels': conviteLabels,
      'escolhaLabels': escolhaLabels,
      'handLabels': handLabels,
      'roomLabels': roomLabels,
      'warningNoticeLabel': {'notice': warningNoticeLabel},
      'recordEntryLabel': {'entry': recordEntryLabel},
      'panoramaEntryLabel': {'entry': panoramaEntryLabel},
    };
    for (final MapEntry(key: table, value: states) in tables.entries) {
      for (final MapEntry(key: state, value: labels) in states.entries) {
        expect(
          labels.keys.toSet(),
          offered,
          reason:
              '$table[$state] sem rótulo numa língua que a sala oferece '
              'vazaria essa língua em silêncio; o guard só olhava o círculo',
        );
      }
    }
  });

  testWidgets(
    'conversa speaks english to an english room, not the portuguese default',
    (tester) async {
      final container = await pumpSala(tester, SalaHarness(lingua: 'en'));
      container.read(salaSessionProvider.notifier).goConversa();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(byLabel('Tap to speak'), findsOneWidget);
      expect(
        byLabel('Tocar para falar'),
        findsNothing,
        reason:
            'o rótulo do círculo era sempre em português, mesmo com o '
            'aparelho em inglês',
      );
    },
  );
}
