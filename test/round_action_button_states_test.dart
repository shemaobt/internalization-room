import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

double _opacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byType(RoundActionButton),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .first
    .opacity;

Future<double> _haloSpreadAfter(WidgetTester tester, Duration wait) async {
  await tester.pump(wait);
  final box = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(RoundActionButton),
          matching: find.byType(Container),
        ),
      )
      .firstWhere((box) => (box.decoration as BoxDecoration).boxShadow != null);
  return (box.decoration as BoxDecoration).boxShadow!
      .map((s) => s.spreadRadius)
      .reduce((a, b) => a > b ? a : b);
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    ButtonMood mood, {
    required VoidCallback onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: RoundActionButton(
            size: 64,
            mood: mood,
            gradient: BeadStyles.verde,
            semanticLabel: 'botão',
            onTap: onTap,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );

  testWidgets('lit: full opacity, taps land, no halo animating', (
    tester,
  ) async {
    var tapped = false;
    await pump(tester, ButtonMood.lit, onTap: () => tapped = true);

    expect(_opacity(tester), 1);
    await tester.tap(find.byType(RoundActionButton));
    expect(tapped, isTrue);

    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(RoundActionButton),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.enabled, isNot(false));

    expect(
      find.descendant(
        of: find.byType(RoundActionButton),
        matching: find.byType(Loop),
      ),
      findsNothing,
      reason: 'lit não desenha halo nenhum, então não há laço para animar',
    );
  });

  testWidgets('dimmed: 0.35 opacity, no tap, semantics disabled', (
    tester,
  ) async {
    var tapped = false;
    await pump(tester, ButtonMood.dimmed, onTap: () => tapped = true);

    expect(_opacity(tester), 0.35);
    await tester.tap(find.byType(RoundActionButton));
    expect(tapped, isFalse);

    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(RoundActionButton),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.enabled, false);
  });

  testWidgets('beckoning: full opacity, taps land, halo loop animates', (
    tester,
  ) async {
    var tapped = false;
    await pump(tester, ButtonMood.beckoning, onTap: () => tapped = true);

    expect(_opacity(tester), 1);
    await tester.tap(find.byType(RoundActionButton));
    expect(tapped, isTrue);

    final before = await _haloSpreadAfter(tester, Duration.zero);
    final after = await _haloSpreadAfter(
      tester,
      const Duration(milliseconds: 1200),
    );
    expect(before, isNot(after), reason: 'o halo do beckoning pulsa');
  });
}
