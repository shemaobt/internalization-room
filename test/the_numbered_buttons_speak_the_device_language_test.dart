import 'package:flutter_test/flutter_test.dart';

import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

final _everyScene = [aKept('S1', 2), aKept('S2', 4), aKept('S3', 6)];

void main() {
  testWidgets(
    'a screen reader hears each English button as her «Hear how you told part N»',
    (tester) async {
      await atRestAfterATurn(tester, _everyScene);

      for (final part in [1, 2, 3]) {
        expect(
          byLabel('Hear how you told part $part'),
          findsOneWidget,
          reason: 'o botão $part não tinha o nome dela em inglês',
        );
      }
    },
  );

  testWidgets(
    'a screen reader hears each Portuguese button as her «Ouvir como vocês contaram a parte N»',
    (tester) async {
      await atRestAfterATurn(tester, _everyScene, lingua: 'pt');

      for (final part in [1, 2, 3]) {
        expect(
          byLabel('Ouvir como vocês contaram a parte $part'),
          findsOneWidget,
          reason: 'o botão $part não tinha o nome dela em português',
        );
      }
    },
  );

  testWidgets(
    'what a screen reader reads for a button is her name and not the numeral after it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await atRestAfterATurn(tester, _everyScene);

      for (final part in [1, 2, 3]) {
        expect(
          tester.getSemantics(byLabel('Hear how you told part $part')).label,
          'Hear how you told part $part',
          reason:
              'o leitor de tela lia o nome dela e o algarismo do botão em seguida',
        );
        expect(
          tester.getSemantics(byLabel('Hear how you told part $part')),
          isSemantics(hasTapAction: true),
          reason: 'o leitor de tela não conseguia tocar o botão $part',
        );
      }
      semantics.dispose();
    },
  );
}
