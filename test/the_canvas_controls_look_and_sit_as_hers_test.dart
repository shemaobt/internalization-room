import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
