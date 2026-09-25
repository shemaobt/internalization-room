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

List<Border> _rippleBorders(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(Ripple),
        matching: find.byType(Container),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .where((paint) => paint.boxShadow == null && paint.border != null)
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

bool _sameHue(Color a, Color b) =>
    (a.r - b.r).abs() < 0.01 &&
    (a.g - b.g).abs() < 0.01 &&
    (a.b - b.b).abs() < 0.01;

double _firstRippleScale(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byType(Ripple),
        matching: find.byType(Transform),
      ),
    )
    .first
    .transform
    .getMaxScaleOnAxis();

Future<void> _expectRippleDirection(
  WidgetTester tester, {
  required bool outward,
}) async {
  final before = _firstRippleScale(tester);
  await tester.pump(const Duration(milliseconds: 120));
  final after = _firstRippleScale(tester);
  if (outward) {
    expect(after, greaterThan(before), reason: 'ripples de fora crescem');
  } else {
    expect(after, lessThan(before), reason: 'ripples de dentro encolhem');
  }
}

void main() {
  group('the circle wears the voice', () {
    testWidgets('the Guide sounding stays telha with outward ripples', (
      tester,
    ) async {
      await _pump(tester, VoiceState.speaking, tongue: Tongue.guide);

      expect(_disc(tester), BeadStyles.telha(SalaColors.light));
      expect(_rings(tester), isEmpty);
      expect(_ripplePeriods(tester), isNotEmpty);
      expect(
        _ripplePeriods(tester),
        everyElement(const Duration(milliseconds: 3400)),
      );
      expect(_rippleBorders(tester), isNotEmpty);
      expect(
        _rippleBorders(
          tester,
        ).every((b) => _sameHue(b.top.color, SalaColors.light.telha)),
        isTrue,
      );

      await _expectRippleDirection(tester, outward: true);
    });

    testWidgets(
      'the Mother tongue listening is wood, ring and ripples in woodLo',
      (tester) async {
        await _pump(tester, VoiceState.listening, tongue: Tongue.motherTongue);

        expect(_disc(tester), BeadStyles.wood);
        expect(_rings(tester), isNotEmpty);
        expect(
          _rings(tester).every((b) => b.top.color == ShemaBrand.woodLo),
          isTrue,
        );
        expect(_ripplePeriods(tester), isNotEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3200)),
        );
        expect(_rippleBorders(tester), isNotEmpty);
        expect(
          _rippleBorders(
            tester,
          ).every((b) => _sameHue(b.top.color, ShemaBrand.woodLo)),
          isTrue,
        );

        await _expectRippleDirection(tester, outward: false);
      },
    );

    testWidgets(
      'the Mother tongue sounding is wood with outward ripples in woodLo',
      (tester) async {
        await _pump(tester, VoiceState.speaking, tongue: Tongue.motherTongue);

        expect(_disc(tester), BeadStyles.wood);
        expect(_rings(tester), isEmpty);
        expect(_ripplePeriods(tester), isNotEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3400)),
        );
        expect(_rippleBorders(tester), isNotEmpty);
        expect(
          _rippleBorders(
            tester,
          ).every((b) => _sameHue(b.top.color, ShemaBrand.woodLo)),
          isTrue,
        );

        await _expectRippleDirection(tester, outward: true);
      },
    );

    testWidgets(
      'the Bridge language listening is azul, ring and ripples in azulInk',
      (tester) async {
        await _pump(tester, VoiceState.listening, tongue: Tongue.bridge);

        expect(_disc(tester), BeadStyles.azul);
        expect(_rings(tester), isNotEmpty);
        expect(
          _rings(tester).every((b) => b.top.color == ShemaBrand.azulInk),
          isTrue,
        );
        expect(_ripplePeriods(tester), isNotEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3200)),
        );
        expect(_rippleBorders(tester), isNotEmpty);
        expect(
          _rippleBorders(
            tester,
          ).every((b) => _sameHue(b.top.color, ShemaBrand.azulInk)),
          isTrue,
        );

        await _expectRippleDirection(tester, outward: false);
      },
    );

    testWidgets(
      'the Bridge language sounding is azul with outward ripples in azulInk',
      (tester) async {
        await _pump(tester, VoiceState.speaking, tongue: Tongue.bridge);

        expect(_disc(tester), BeadStyles.azul);
        expect(_rings(tester), isEmpty);
        expect(_ripplePeriods(tester), isNotEmpty);
        expect(
          _ripplePeriods(tester),
          everyElement(const Duration(milliseconds: 3400)),
        );
        expect(_rippleBorders(tester), isNotEmpty);
        expect(
          _rippleBorders(
            tester,
          ).every((b) => _sameHue(b.top.color, ShemaBrand.azulInk)),
          isTrue,
        );

        await _expectRippleDirection(tester, outward: true);
      },
    );

    testWidgets('idle draws neither ring nor ripples', (tester) async {
      await _pump(tester, VoiceState.invite);

      expect(_disc(tester), BeadStyles.telha(SalaColors.light));
      expect(_rings(tester), isEmpty);
      expect(_ripplePeriods(tester), isEmpty);
    });

    testWidgets('idle stays telha whatever tongue is set', (tester) async {
      for (final tongue in Tongue.values) {
        await _pump(tester, VoiceState.invite, tongue: tongue);

        expect(
          _disc(tester),
          BeadStyles.telha(SalaColors.light),
          reason:
              'a voz só se lê enquanto a sala escuta ou soa; $tongue parado é telha',
        );
      }
    });
  });
}
