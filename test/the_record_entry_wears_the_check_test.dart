import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _entryPt = 'Terminar a conversa e ir para o ensaio';
const _entryEn = 'Finish the conversation and go to the rehearsal';

Future<ProviderContainer> _pumpInConversa(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 2));
  return container;
}

void main() {
  testWidgets(
    'the entry draws the check glyph, never a microphone, and opens the rehearsal',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      await _pumpInConversa(tester, harness);

      final entry = byLabel(_entryPt);
      expect(entry, findsOneWidget);

      final icons = tester.widgetList<Icon>(
        find.descendant(of: entry, matching: find.byType(Icon)),
      );
      expect(icons, isNotEmpty);
      expect(icons.first.icon, LucideIcons.check);
      expect(
        find.descendant(of: entry, matching: find.byIcon(LucideIcons.mic)),
        findsNothing,
      );

      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EnsaioView), findsOneWidget);
    },
  );

  testWidgets('it speaks the room language when it is en', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    await _pumpInConversa(tester, harness);

    expect(byLabel(_entryEn), findsOneWidget);
    expect(byLabel(_entryPt), findsNothing);
  });

  testWidgets(
    'an unknown language falls back like circleLabelFor, to en, not to pt',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'xx');
      await _pumpInConversa(tester, harness);

      expect(byLabel(_entryEn), findsOneWidget);
      expect(byLabel(_entryPt), findsNothing);
    },
  );
}
