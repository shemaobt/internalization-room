import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/claquete.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/shema_mark.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

void main() {
  for (final (width, height, bar, bottom) in [
    (375.0, 667.0, 20.0, 608.77),
    (820.0, 1180.0, 24.0, 1075.96),
  ]) {
    testWidgets('the necklace sits low in one row, as hers, and never under '
        'the mark, on a ${width.toInt()} x ${height.toInt()} screen', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, height)
        ..devicePixelRatio = 1
        ..padding = FakeViewPadding(top: bar)
        ..viewPadding = FakeViewPadding(top: bar);
      addTearDown(tester.view.reset);
      final container = await pumpSala(tester, SalaHarness());
      await container
          .read(salaSessionProvider.notifier)
          .goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(seconds: 1));

      final beads = [
        for (final bead
            in find
                .descendant(
                  of: find.byType(ColarOverlay),
                  matching: find.byType(AnimatedContainer),
                )
                .evaluate())
          tester.getRect(find.byWidget(bead.widget)),
      ];
      final mark = tester.getRect(
        find.descendant(
          of: find.byType(ClaqueteLayer),
          matching: find.byType(ShemaMark),
        ),
      );

      expect(beads, hasLength(12));
      for (final (i, bead) in beads.indexed) {
        expect(
          bead.overlaps(mark),
          isFalse,
          reason: 'a marca da Shema cobria a conta $i do colar',
        );
      }
      for (final bead in beads) {
        expect(
          bead.bottom,
          moreOrLessEquals(bottom, epsilon: 0.01),
          reason:
              'o colar pendia no alto da tela, onde a marca fica, e não '
              'embaixo, a 9% do fim da tela como o dela',
        );
      }
      expect(
        (beads.first.left + beads.last.right) / 2,
        moreOrLessEquals(width / 2, epsilon: 0.01),
        reason: 'a fileira do colar não ficava no meio da tela',
      );
      closeTheRoom(container);
    });
  }
}
