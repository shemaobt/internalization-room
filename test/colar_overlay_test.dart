import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';

void main() {
  Future<void> pumpColar(WidgetTester tester, SalaSessionState session) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ColarOverlay(session: session),
        ),
      ),
    );
  }

  BoxDecoration decorationAt(WidgetTester tester, int index) =>
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).at(index)).decoration
          as BoxDecoration;

  testWidgets('a bead nobody has spoken into waits, whatever the guide surfaced', (
    tester,
  ) async {
    const session = SalaSessionState(
      coverage: Coverage(engaged: 0, surfaced: 10, total: 29, absenceIndex: -1),
    );
    await pumpColar(tester, session);

    expect(find.byType(AnimatedContainer), findsNWidgets(29));
    for (var i = 0; i < 29; i++) {
      expect(decorationAt(tester, i).gradient, isNot(isA<LinearGradient>()),
          reason: 'a conta $i não pode desenhar o gradiente dividido do surfacedOnly');
      expect(decorationAt(tester, i).gradient, BeadStyles.oat(SalaColors.light),
          reason: 'uma conta que o time não falou é uma conta vazia, mesmo surfaced');
    }
  });
}
