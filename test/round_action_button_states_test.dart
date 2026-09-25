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

List<BoxShadow> _boxShadow(WidgetTester tester) {
  final box = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(RoundActionButton),
          matching: find.byType(Container),
        ),
      )
      .first;
  return (box.decoration as BoxDecoration).boxShadow ?? const [];
}

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
    List<BoxShadow>? shadows,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: RoundActionButton(
            key: const ValueKey('o mesmo botão'),
            size: 64,
            mood: mood,
            gradient: BeadStyles.verde,
            shadows: shadows,
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
    const given = [
      BoxShadow(color: Color(0x330A0703), offset: Offset(0, 4), blurRadius: 12),
    ];
    await pump(
      tester,
      ButtonMood.lit,
      onTap: () => tapped = true,
      shadows: given,
    );

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
      _boxShadow(tester),
      given,
      reason: 'lit não soma halo nenhum ao que a estação já pediu',
    );

    expect(
      find.descendant(
        of: find.byType(RoundActionButton),
        matching: find.byType(Loop),
      ),
      findsWidgets,
      reason: 'lit é o mesmo Loop parado, não uma árvore sem laço nenhum',
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

  testWidgets('a mood change updates the same button, it does not remount it', (
    tester,
  ) async {
    const given = [
      BoxShadow(color: Color(0x330A0703), offset: Offset(0, 4), blurRadius: 12),
    ];
    await pump(tester, ButtonMood.lit, onTap: () {}, shadows: given);
    final beforeOpacity = tester.state(find.byType(AnimatedOpacity).first);
    final beforeLoop = tester.state(find.byType(Loop).first);
    final beforeShadow = _boxShadow(tester);

    await pump(tester, ButtonMood.dimmed, onTap: () {}, shadows: given);
    final afterOpacity = tester.state(find.byType(AnimatedOpacity).first);
    final afterLoop = tester.state(find.byType(Loop).first);

    expect(
      identical(beforeLoop, afterLoop),
      isTrue,
      reason: 'trocar de humor não pode derrubar e reerguer o Loop do halo',
    );
    expect(
      identical(beforeOpacity, afterOpacity),
      isTrue,
      reason:
          'nem o AnimatedOpacity, que carrega a transição de 300ms em curso',
    );
    expect(
      _boxShadow(tester),
      beforeShadow,
      reason: 'dimmed não soma sombra nenhuma que lit não tinha',
    );
  });
}
