import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show atRestAfterATurn;

const _se = Size(375, 667);

void _on(WidgetTester tester, Size screen, {double bar = 0, double inset = 0}) {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar, bottom: inset)
    ..viewPadding = FakeViewPadding(top: bar, bottom: inset);
  addTearDown(tester.view.reset);
}

void _inTheDark(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

double _seenOpacity(WidgetTester tester, Finder mark) {
  var seen = 1.0;
  mark.evaluate().first.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) seen *= widget.opacity;
    if (widget is FadeTransition) seen *= widget.opacity.value;
    return true;
  });
  return seen;
}

void _sits(Rect rect, Size size, {required Offset center, String? reason}) {
  expect(rect.width, closeTo(size.width, 0.01), reason: reason);
  expect(rect.height, closeTo(size.height, 0.01), reason: reason);
  expect(rect.center.dx, closeTo(center.dx, 0.01), reason: reason);
  expect(rect.center.dy, closeTo(center.dy, 0.01), reason: reason);
}

Finder _barsOf(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.rectangle,
  ),
);

Finder _paintedUnder(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate((widget) {
    final decoration = switch (widget) {
      Container(:final decoration?) => decoration,
      DecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    return decoration is BoxDecoration &&
        (decoration.color != null ||
            decoration.gradient != null ||
            decoration.boxShadow != null);
  }),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var beat = 0; beat < 100 && !done(); beat++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final (look, verde) in [
    ('light', const Color(0xFF3F3E20)),
    ('dark', const Color(0xFFECEADC)),
  ]) {
    testWidgets(
      'in the $look look hearing again is her bare arrow at 8% and 16%, '
      'at .42, not a disc',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Hear that again';

        expect(byLabel(label), findsOneWidget);
        expect(
          _paintedUnder(label),
          findsNothing,
          reason: 'o ouvir de novo era um disco com sombra',
        );
        final arrow = find.descendant(
          of: byLabel(label),
          matching: find.byType(Icon),
        );
        final icon = tester.widget<Icon>(arrow);
        expect(icon.icon, LucideIcons.rotateCcw);
        expect(icon.size, 22);
        expect(icon.color, verde, reason: 'a seta dela é --verde');
        expect(
          _seenOpacity(tester, arrow),
          closeTo(0.42, 0.001),
          reason: 'a seta dela fica a .42 quando aparece',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(375 - 30 - 22, 667 - 106.72 - 22),
          reason: 'o ouvir de novo ficava a 14 e 18 do canto',
        );
      },
    );
  }

  for (final (look, verde) in [
    ('light', const Color(0xFF3F3E20)),
    ('dark', const Color(0xFFECEADC)),
  ]) {
    testWidgets(
      'in the $look look the hand is her bare glyph at 8% and 16%, at .35, '
      'not a card',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Leave a question for the facilitator';

        expect(byLabel(label), findsOneWidget);
        expect(
          _paintedUnder(label),
          findsNothing,
          reason: 'a mão era um cartão de 60 px com borda',
        );
        final glyph = find.descendant(
          of: byLabel(label),
          matching: find.byType(Icon),
        );
        final icon = tester.widget<Icon>(glyph);
        expect(icon.icon, LucideIcons.hand);
        expect(icon.size, 26);
        expect(icon.color, verde, reason: 'a mão dela é --verde');
        expect(
          _seenOpacity(tester, glyph),
          closeTo(0.35, 0.001),
          reason: 'a mão dela fica a .35 na vez da equipe',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(30 + 20, 667 - 106.72 - 20),
          reason: 'a mão ficava a 14 e 18 do canto',
        );
      },
    );
  }

  testWidgets(
    'in note mode the hand stands at her .8, green, with no blue glow',
    (tester) async {
      _on(tester, _se, bar: 20);
      final (_, container) = await atRestAfterATurn(tester, const []);
      const label = 'Leave a question for the facilitator';

      container.read(salaSessionProvider.notifier).handTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).noteMode,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));

      expect(container.read(salaSessionProvider).noteMode, isTrue);
      final glyph = find.descendant(
        of: byLabel(label),
        matching: find.byType(Icon),
      );
      expect(
        _paintedUnder(label),
        findsNothing,
        reason: 'a mão acendia um halo azul no modo de recado',
      );
      expect(tester.widget<Icon>(glyph).color, const Color(0xFF3F3E20));
      expect(
        _seenOpacity(tester, glyph),
        closeTo(0.8, 0.001),
        reason: 'no recado a mão dela sobe para .8',
      );
    },
  );

  testWidgets(
    'hearing again fades in over her 1.2 s once the line has played',
    (tester) async {
      _on(tester, _se, bar: 20);
      final (harness, container) = await atRestAfterATurn(tester, const []);
      const label = 'Hear that again';
      final arrow = find.descendant(
        of: byLabel(label),
        matching: find.byType(Icon),
      );

      harness.voice.holdNextLine();
      container.read(salaSessionProvider.notifier).hearAgain();
      await _pumpUntil(tester, () => byLabel(label).evaluate().isEmpty);
      expect(byLabel(label), findsNothing);
      harness.voice.finishHeldLine();
      await _pumpUntil(tester, () => byLabel(label).evaluate().isNotEmpty);
      expect(byLabel(label), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        _seenOpacity(tester, arrow),
        closeTo(0.21, 0.02),
        reason: 'a seta surgia em 700 ms subindo, não no 1,2 s dela',
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(_seenOpacity(tester, arrow), closeTo(0.42, 0.001));
    },
  );

  for (final (look, verdeClaro) in [
    ('light', const Color(0xFF777D45)),
    ('dark', const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the $look look the way out is her three faint bars at 5% and 6%, '
      'not a disc',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Choose another passage';

        expect(byLabel(label), findsOneWidget);
        final bars = _barsOf(label);
        expect(bars, findsNWidgets(3), reason: 'o canto era um disco opaco');
        for (var i = 0; i < 3; i++) {
          final rect = tester.getRect(bars.at(i));
          expect(rect.width, closeTo(24, 0.01));
          expect(rect.height, closeTo(2, 0.01));
          expect(rect.left, closeTo(22.5 + 3, 0.01));
          expect(rect.top, closeTo(20 + 33.35 + 3 + 7.0 * i, 0.01));
        }
        for (final bar in tester.widgetList<Container>(bars)) {
          final body = bar.decoration! as BoxDecoration;
          expect(body.color, verdeClaro);
          expect(body.borderRadius, BorderRadius.circular(2));
          expect(body.boxShadow, isNull);
        }
        expect(
          _seenOpacity(tester, bars.first),
          closeTo(0.22, 0.001),
          reason: 'o canto dela fica a .22 em repouso',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(22.5 + 15, 20 + 33.35 + 11),
          reason: 'o alvo do toque ficou menor que 44 ou fora do lugar dela',
        );
      },
    );
  }
}
