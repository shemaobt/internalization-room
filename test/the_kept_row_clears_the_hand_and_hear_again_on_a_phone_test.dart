import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hear_again_button.dart';

import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

void main() {
  for (final (width, height, inset) in [
    (390.0, 844.0, 34.0),
    (390.0, 780.0, 34.0),
    (390.0, 667.0, 0.0),
    (768.0, 1024.0, 20.0),
  ]) {
    testWidgets('six kept buttons never touch the hand or hear-again on a '
        '${width.toInt()} by ${height.toInt()} screen', (tester) async {
      tester.view
        ..physicalSize = Size(width, height)
        ..devicePixelRatio = 1
        ..padding = FakeViewPadding(bottom: inset)
        ..viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
      await atRestAfterATurn(tester, [
        for (var scene = 1; scene <= 6; scene++) aKept('S$scene', scene),
      ], parts: 6);

      final hand = tester.getRect(
        byLabel('Leave a question for the facilitator'),
      );
      final hearAgain = tester.getRect(
        find
            .descendant(
              of: find.byType(HearAgainButton),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      for (var part = 1; part <= 6; part++) {
        final button = tester.getRect(byLabel('Hear how you told part $part'));
        expect(
          button.overlaps(hand),
          isFalse,
          reason: 'o botão $part do colar encostava no botão da mão',
        );
        expect(
          button.overlaps(hearAgain),
          isFalse,
          reason: 'o botão $part do colar encostava no ouvir de novo',
        );
      }
    });
  }
}
