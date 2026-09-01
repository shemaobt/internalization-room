import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
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

  testWidgets('the claim code is read across a table, in either light', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: const Scaffold(
            body: CodigoView(
              code: ClaimCode(deviceId: 'aparelho-1', code: 'QHF-3M7K'),
              language: 'pt',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      final painted = tester.widget<Text>(find.byType(Text)).style!;
      final drawn = tester.getRect(find.byType(Text));
      final surface = tester.getSize(find.byType(Scaffold));
      expect(drawn.width, greaterThan(surface.width * 0.8),
          reason: 'o FittedBox encolhe o glifo até caber, então o tamanho declarado passava '
              'no teste enquanto a tela desenhava um código pequeno demais para a mesa');
      expect(_ratio(painted.color!, theme.scaffoldBackgroundColor), greaterThan(7),
          reason: 'o glifo desenhado com a cor de apoio some no papel claro, e um '
              'código que não se lê é uma instalação que não acontece');
    }
  });

  testWidgets('the room speaking does not look like the room waiting to be spoken to',
      (tester) async {
    Future<void> pumpCircle(VoiceState voice) => tester.pumpWidget(
          MaterialApp(
            key: ValueKey(voice),
            theme: AppTheme.dark,
            home: Scaffold(
              body: Center(
                child: FacilitatorCircle(
                  size: 196,
                  voice: voice,
                  semanticLabel: 'circulo',
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

    List<BoxDecoration> painted() => tester
        .widgetList<Container>(find.byType(Container))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();

    await pumpCircle(VoiceState.invite);
    await tester.pump(const Duration(milliseconds: 80));
    expect(painted().where((d) => d.border != null), isEmpty,
        reason: 'esperando, o círculo é só o disco — nada em volta dele');

    await pumpCircle(VoiceState.speaking);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 80));
      final decorations = painted();
      final disc = decorations.indexWhere((d) => d.gradient != null);
      final ring = decorations.indexWhere((d) => d.border != null);

      expect(ring, greaterThan(disc),
          reason: 'os dois estados desenham exatamente o mesmo disco, então o anel é a '
              'única coisa que diz quem está falando — e ele passava por baixo, onde o '
              'halo do próprio disco, telha a 0,32 com 34 de blur, o cobria');
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
