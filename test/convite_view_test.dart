import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

void main() {
  testWidgets(
      'the circle at the entrada never says the facilitator already finished',
      (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await tester.pump(const Duration(milliseconds: 200));

    expect(bySemanticsLabelWidget('O facilitador já contou do livro'),
        findsNothing,
        reason: 'o panorama não tem fim previsto — dizer que o facilitador já '
            'terminou é o próprio convite fingindo que não há mais turno');
    expect(bySemanticsLabelWidget('Falar com o facilitador'), findsOneWidget);
  });
}
