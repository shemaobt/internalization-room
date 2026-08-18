import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

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
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 600));
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

    expect(alone.length, greaterThan(1));
    expect(
      withTeam.length,
      greaterThan(1),
      reason: 'a tela em que a sala espera a equipe era a única parada do app',
    );
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
}
