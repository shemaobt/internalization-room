import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

void main() {
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
