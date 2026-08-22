import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/presentation/widgets/eq_bars.dart';

/// What the team can actually tell apart, on a tablet on the floor.
///
/// The necklace is the only record of progress they can perceive, and the hollow bead
/// elsewhere is the room saying a recording has not left the tablet. Both were carried in
/// dark mode by a ten-percent black shadow on a near-black ground, which renders as
/// nothing — so the cord read as finished from the first turn.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel((c.r * 255).roundToDouble()) +
      0.7152 * channel((c.g * 255).roundToDouble()) +
      0.0722 * channel((c.b * 255).roundToDouble());
}

double _ratio(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('the bead still to come stands out of the dark paper by itself', () {
    // In light mode a ten-percent black shadow carries the shape against cream, and 1.17:1
    // of fill is enough. On near-black that shadow renders as nothing, so the fill has to
    // do the whole job — and at #2C2620 it did not: 1.21:1, invisible.
    expect(_ratio(SalaColors.dark.oat, SalaColors.dark.paper), greaterThan(2),
        reason: 'a conta que significa "esta parte ainda está à frente de vocês" sumia, '
            'e o cordão parecia completo desde o primeiro turno');
  });

  test('a bead earned does not read as a bead still to come', () {
    for (final colors in [SalaColors.light, SalaColors.dark]) {
      expect(_ratio(colors.oat, ShemaBrand.wood), greaterThan(1.7),
          reason: 'é essa diferença que a equipe conta ao olhar o colar');
    }
  });

  testWidgets('the microphone meter paints in the room\'s own colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: EqBars(active: true))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final painted = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((bar) => (bar.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .toSet();

    expect(painted, contains(SalaColors.light.telha),
        reason: 'o medidor usava um laranja fixo afinado no fundo escuro — 2,5:1 no papel '
            'claro, contra 4,6:1 do telha da sala, e é o sinal mais forte de "o microfone '
            'está ligado" numa tela vista ao sol');
    expect(_ratio(SalaColors.light.telha, SalaColors.light.paper), greaterThan(4));
  });
}
