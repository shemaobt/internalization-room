import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';

/// A finger held on a button is a tap the team meant to make.
///
/// Flutter gives the long press the arena over the tap, so a `GestureDetector` that wires
/// both fires only the long press — and when that long press is a no-op, the gesture is
/// swallowed whole. On the rehearsal circle it meant a held finger never opened the mic.
void main() {
  testWidgets('a held press still records when nobody can answer a long press', (
    tester,
  ) async {
    var taps = 0;
    var presses = 0;

    Widget circle({required VoidCallback? onLongPress}) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => taps++,
                onLongPress: onLongPress,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 160, height: 160),
              ),
            ),
          ),
        );

    await tester.pumpWidget(circle(onLongPress: () => presses++));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
    await tester.pump(const Duration(milliseconds: 900));
    await gesture.up();
    await tester.pump();

    expect(taps, 0, reason: 'com o toque longo ligado, segurar o dedo engole o toque');
    expect(presses, 1);

    taps = 0;
    await tester.pumpWidget(circle(onLongPress: null));
    final again = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
    await tester.pump(const Duration(milliseconds: 900));
    await again.up();
    await tester.pump();

    expect(taps, 1,
        reason: 'numa sala saudável o toque longo não tem o que fazer, então precisa '
            'sair da frente — senão gravar depende de soltar o dedo depressa');
  });
}
