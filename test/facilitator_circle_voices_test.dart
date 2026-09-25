import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Future<void> _pump(WidgetTester tester, VoiceState voice, {Tongue? tongue}) =>
    tester.pumpWidget(
      MaterialApp(
        key: ValueKey('$voice-$tongue'),
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: FacilitatorCircle(
              size: 158,
              voice: voice,
              tongue: tongue,
              semanticLabel: 'circulo',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

Gradient? _disc(WidgetTester tester) {
  final painted = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Container),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((paint) => paint.gradient)
      .whereType<Gradient>()
      .toList();
  return painted.isEmpty ? null : painted.first;
}

/// The listening ring only: a border with its own glow, unlike a ripple's bare border.
List<Border> _rings(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .where((paint) => paint.boxShadow != null && paint.border != null)
    .map((paint) => paint.border as Border)
    .toList();

List<Duration> _ripplePeriods(WidgetTester tester) => tester
    .widgetList<Ripple>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Ripple),
      ),
    )
    .map((ripple) => ripple.period)
    .toList();

Future<Set<double>> _scalesOverAWindow(WidgetTester tester) async {
  final scales = <double>{};
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
    for (final moved in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(Ripple),
        matching: find.byType(Transform),
      ),
    )) {
      scales.add(double.parse(moved.transform.entry(0, 0).toStringAsFixed(3)));
    }
  }
  return scales;
}

void main() {
  group('the circle wears the voice', () {
    testWidgets('the Guide sounding stays telha with outward ripples', (
      tester,
    ) async {
      await _pump(tester, VoiceState.speaking, tongue: Tongue.guide);

      expect(_disc(tester), BeadStyles.telha(SalaColors.light));
      expect(
        _ripplePeriods(tester),
        everyElement(const Duration(milliseconds: 3400)),
      );
      expect(_rings(tester), isEmpty);

      final scales = await _scalesOverAWindow(tester);
      expect(
        scales.any((s) => s > 1.3),
        isTrue,
        reason: 'ripples de fora crescem de 1 até 1.46',
      );
    });

    testWidgets(
      'the Mother tongue listening is wood, ring and ripples in woodLo',
      (tester) async {
        await _pump(tester, VoiceState.listening, tongue: Tongue.motherTongue);

        expect(_disc(tester), BeadStyles.wood);
        expect(
          _rings(tester).any((border) => border.top.color == ShemaBrand.woodLo),
          isTrue,
        );
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3200)),
        );

        final scales = await _scalesOverAWindow(tester);
        expect(
          scales.any((s) => s < 1.2),
          isTrue,
          reason: 'ripples de dentro encolhem de 1.46 até 1',
        );
      },
    );

    testWidgets(
      'the Mother tongue sounding is wood with outward ripples in woodLo',
      (tester) async {
        await _pump(tester, VoiceState.speaking, tongue: Tongue.motherTongue);

        expect(_disc(tester), BeadStyles.wood);
        expect(_rings(tester), isEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3400)),
        );

        final scales = await _scalesOverAWindow(tester);
        expect(scales.any((s) => s > 1.3), isTrue);
      },
    );

    testWidgets(
      'the Bridge language listening is azul, ring and ripples in azulInk',
      (tester) async {
        await _pump(tester, VoiceState.listening, tongue: Tongue.bridge);

        expect(_disc(tester), BeadStyles.azul);
        expect(
          _rings(
            tester,
          ).any((border) => border.top.color == ShemaBrand.azulInk),
          isTrue,
        );
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3200)),
        );
      },
    );

    testWidgets(
      'the Bridge language sounding is azul with outward ripples in azulInk',
      (tester) async {
        await _pump(tester, VoiceState.speaking, tongue: Tongue.bridge);

        expect(_disc(tester), BeadStyles.azul);
        expect(_rings(tester), isEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3400)),
        );

        final scales = await _scalesOverAWindow(tester);
        expect(scales.any((s) => s > 1.3), isTrue);
      },
    );

    testWidgets('idle draws neither ring nor ripples', (tester) async {
      await _pump(tester, VoiceState.invite);

      expect(_disc(tester), BeadStyles.telha(SalaColors.light));
      expect(_rings(tester), isEmpty);
      expect(_ripplePeriods(tester), isEmpty);
    });
  });
}
