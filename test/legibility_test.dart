import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

/// What the team can actually tell apart, on a tablet on the floor.
///
/// The necklace is the only record of progress they can perceive, and the hollow bead
/// elsewhere is the room saying a recording has not left the tablet. Both were carried in
/// dark mode by a ten-percent black shadow on a near-black ground, which renders as
/// nothing — so the cord read as finished from the first turn.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
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
    expect(
      _ratio(SalaColors.dark.oat, SalaColors.dark.paper),
      greaterThan(2),
      reason:
          'a conta que significa "esta parte ainda está à frente de vocês" sumia, '
          'e o cordão parecia completo desde o primeiro turno',
    );
  });

  test('a bead earned does not read as a bead still to come', () {
    for (final colors in [SalaColors.light, SalaColors.dark]) {
      expect(
        _ratio(colors.oat, ShemaBrand.wood),
        greaterThan(1.7),
        reason: 'é essa diferença que a equipe conta ao olhar o colar',
      );
    }
  });

  testWidgets('the claim code is read across a table, in either light', (
    tester,
  ) async {
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
      expect(
        drawn.width,
        greaterThan(surface.width * 0.8),
        reason:
            'o FittedBox encolhe o glifo até caber, então o tamanho declarado passava '
            'no teste enquanto a tela desenhava um código pequeno demais para a mesa',
      );
      expect(
        _ratio(painted.color!, theme.scaffoldBackgroundColor),
        greaterThan(7),
        reason:
            'o glifo desenhado com a cor de apoio some no papel claro, e um '
            'código que não se lê é uma instalação que não acontece',
      );
    }
  });

  testWidgets(
    'the room speaking does not look like the room waiting to be spoken to',
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

      Future<({double smallest, double faintest})> overABreath() async {
        var smallest = double.infinity;
        var faintest = double.infinity;
        for (var frame = 0; frame < 90; frame++) {
          await tester.pump(const Duration(milliseconds: 80));
          final ring = find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                (widget.decoration as BoxDecoration?)?.border != null,
          );
          for (final moved in tester.widgetList<Transform>(
            find.ancestor(of: ring, matching: find.byType(Transform)),
          )) {
            smallest = math.min(smallest, moved.transform.entry(0, 0));
          }
          for (final veil in tester.widgetList<Opacity>(
            find.ancestor(of: ring, matching: find.byType(Opacity)),
          )) {
            faintest = math.min(faintest, veil.opacity);
          }
        }
        return (smallest: smallest, faintest: faintest);
      }

      await pumpCircle(VoiceState.invite);
      final waiting = await overABreath();
      await pumpCircle(VoiceState.speaking);
      final speaking = await overABreath();

      expect(
        [waiting.smallest, waiting.faintest],
        [greaterThanOrEqualTo(1), 1],
        reason:
            'esperando, o anel dela só cresce até 1.035 e nunca esmaece '
            '(invite, globals.css:195, :379)',
      );
      expect(
        [speaking.smallest, speaking.faintest],
        [lessThan(.975), lessThan(.83)],
        reason:
            'os dois estados têm a mesma borda telha (globals.css:379, :383), '
            'então é a respiração que diz quem está falando: o thinkBreath '
            'desce a .97 e esmaece a .82; sem ela falar e esperar se '
            'confundiam',
      );
    },
  );
}
