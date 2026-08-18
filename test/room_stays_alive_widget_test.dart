import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Widget _circleIn(VoiceState voice) => MaterialApp(
      theme: AppTheme.light,
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
    );

Widget _circle({required bool peerCue}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: 196,
            voice: VoiceState.invite,
            peerCue: peerCue,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    );

Future<Set<double>> _scalesOver(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  final seen = <double>{};
  // A full breath is 4600 ms, eased at both ends: coarse steps never land on the peak,
  // and sampling less than half a period never approaches it at all.
  for (var frame = 0; frame < 44; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
    for (final transform in tester.widgetList<Transform>(find.byType(Transform))) {
      seen.add(transform.transform.getMaxScaleOnAxis());
    }
  }
  return seen;
}

void main() {
  testWidgets('the room keeps breathing when it hands the floor to the team', (
    tester,
  ) async {
    final alone = await _scalesOver(tester, _circle(peerCue: false));
    final withTeam = await _scalesOver(tester, _circle(peerCue: true));

    // Counting distinct scales passes on an amplitude of 0.00002 — four thousandths of a
    // pixel on a 196 px disc. What the claim actually is: the same breath as every other
    // invite, so the two sets have to be equal.
    double peak(Set<double> seen) => seen.reduce((a, b) => a > b ? a : b);

    // Counting distinct scales passes at an amplitude of 0.00002 — four thousandths of a
    // pixel on a 196 px disc. What the claim is: the same breath as every other invite,
    // so both reach the same peak, and that peak is visible.
    expect(peak(withTeam), greaterThan(1.04));
    expect((peak(withTeam) - peak(alone)).abs(), lessThan(0.004),
        reason: 'a afirmação não é que respira, é que respira igual a todo invite');
  });

  testWidgets('a button that just appeared accepts the first touch', (
    tester,
  ) async {
    var touched = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FadeUp(
            child: GestureDetector(
              onTap: () => touched++,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 120, height: 120),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(SizedBox).first, warnIfMissed: false);

    expect(touched, 1);
  });

  testWidgets('the looping circle keeps moving between frames', (tester) async {
    final seen = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Loop(
          period: const Duration(milliseconds: 4600),
          animate: true,
          builder: (context, t) {
            seen.add(t);
            return const SizedBox(width: 10, height: 10);
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(seen.toSet().length, greaterThan(1));
  });

  testWidgets('a halted room is still visibly running', (tester) async {
    for (final voice in [
      VoiceState.needsPerson,
      VoiceState.offline,
      VoiceState.blocked,
    ]) {
      final seen = await _scalesOver(tester, _circleIn(voice));
      final swing = seen.reduce((a, b) => a > b ? a : b) -
          seen.reduce((a, b) => a < b ? a : b);

      expect(swing, greaterThan(0.015),
          reason: '$voice fala sua linha uma vez e depois nunca mais; sem movimento, '
              'olhar para essa tela não distingue uma sala esperando de um app morto');
    }
  });
}
