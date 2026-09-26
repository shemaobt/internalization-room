import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

void main() {
  testWidgets('the record entry speaks english to an english room', (
    tester,
  ) async {
    final harness = SalaHarness(lingua: 'en');
    final container = await pumpSala(tester, harness);
    await container
        .read(salaSessionProvider.notifier)
        .goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      bySemanticsLabelWidget('Finish the conversation and go to the rehearsal'),
      findsOneWidget,
      reason:
          'a equipe inglesa precisa ouvir o próprio idioma no botão que abre o '
          'ensaio, não a fala fixa em português',
    );
  });
}
