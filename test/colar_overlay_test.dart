import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

void main() {
  Future<void> pumpColar(WidgetTester tester, SalaSessionState session) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ColarOverlay(session: session)),
      ),
    );
  }

  Future<void> pumpReducedColar(
    WidgetTester tester,
    SalaSessionState session,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ColarOverlay(session: session)),
        ),
      ),
    );
  }

  BoxDecoration decorationAt(WidgetTester tester, int index) =>
      tester
              .widget<AnimatedContainer>(
                find.byType(AnimatedContainer).at(index),
              )
              .decoration
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
      expect(
        decorationAt(tester, i).gradient,
        isNot(isA<LinearGradient>()),
        reason:
            'a conta $i não pode desenhar o gradiente dividido do surfacedOnly',
      );
      expect(
        decorationAt(tester, i).gradient,
        BeadStyles.oat(SalaColors.light),
        reason:
            'uma conta que o time não falou é uma conta vazia, mesmo surfaced',
      );
    }
  });

  testWidgets('exactly the beads the team spoke into come back filled', (
    tester,
  ) async {
    const session = SalaSessionState(
      coverage: Coverage(engaged: 3, surfaced: 3, total: 29, absenceIndex: -1),
    );
    await pumpColar(tester, session);

    var filled = 0;
    for (var i = 0; i < 29; i++) {
      if (decorationAt(tester, i).gradient == BeadStyles.wood) filled++;
    }
    expect(
      filled,
      3,
      reason:
          'a conta enche uma a uma com o que o time falou, nunca mais nem menos',
    );
  });

  BoxDecoration renderedDecorationAt(WidgetTester tester, int index) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byType(AnimatedContainer).at(index),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  testWidgets('a bead the team just spoke into settles over 1.3 s, not a pop', (
    tester,
  ) async {
    const waiting = SalaSessionState(
      coverage: Coverage(engaged: 0, surfaced: 0, total: 1, absenceIndex: -1),
    );
    await pumpColar(tester, waiting);

    final filled = waiting.copyWith(
      coverage: const Coverage(
        engaged: 1,
        surfaced: 0,
        total: 1,
        absenceIndex: -1,
      ),
    );
    await pumpColar(tester, filled);

    expect(
      find.byType(PingIn),
      findsNothing,
      reason:
          'a conta assenta pela transição do próprio AnimatedContainer, sem o pulo de escala do PingIn',
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      renderedDecorationAt(tester, 0).gradient,
      isNot(BeadStyles.wood),
      reason:
          'em 700ms a conta já teria assentado — o settle é de 1,3s, não 700ms',
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(
      renderedDecorationAt(tester, 0).gradient,
      BeadStyles.wood,
      reason: 'em 1,3s a conta acabou de assentar no cheio, sem pulo de escala',
    );
  });

  testWidgets('the necklace closes in stillness, not a loop', (tester) async {
    const session = SalaSessionState(
      stage: SalaStage.fim,
      coverage: Coverage(engaged: 5, surfaced: 5, total: 5, absenceIndex: -1),
    );
    await pumpColar(tester, session);

    expect(
      find.byType(Loop),
      findsNothing,
      reason:
          'o fecho da passagem é quietude, a tela de celebração o design proíbe',
    );
  });

  testWidgets(
    'the absence bead rings only once the team worked that silence, not before',
    (tester) async {
      const waiting = SalaSessionState(
        coverage: Coverage(engaged: 2, surfaced: 2, total: 10, absenceIndex: 5),
      );
      await pumpColar(tester, waiting);
      expect(
        decorationAt(tester, 5).gradient,
        BeadStyles.oat(SalaColors.light),
        reason: 'a ausência fora de engaged ainda é uma conta vazia comum',
      );

      const ringed = SalaSessionState(
        coverage: Coverage(engaged: 6, surfaced: 6, total: 10, absenceIndex: 5),
      );
      await pumpColar(tester, ringed);
      expect(
        decorationAt(tester, 5).gradient,
        isNull,
        reason:
            'a conta de ausência só ganha o anel quando cai dentro de engaged, e o anel não tem gradiente',
      );
      expect(
        (decorationAt(tester, 5).border as Border).top.width,
        3,
        reason:
            'o anel é a versão cheia da conta de ausência, não um terceiro estado',
      );
    },
  );

  testWidgets(
    'a bead whose slot changes lands there on the first frame, reduced',
    (tester) async {
      const arriving = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1, absenceIndex: -1),
      );
      await pumpReducedColar(tester, arriving);

      await pumpReducedColar(tester, arriving.copyWith(stage: SalaStage.fim));
      final landedTopLeft = tester.getTopLeft(
        find.byType(AnimatedPositioned).first,
      );

      await tester.pumpWidget(Container());
      await pumpReducedColar(tester, arriving.copyWith(stage: SalaStage.fim));
      final steadyTopLeft = tester.getTopLeft(
        find.byType(AnimatedPositioned).first,
      );

      expect(
        landedTopLeft,
        steadyTopLeft,
        reason:
            'com o movimento reduzido a conta ainda esperava os 900ms do slide — o primeiro frame '
            'a mostrava no lugar antigo, entre o arco e o novo lugar no círculo',
      );
    },
  );

  testWidgets(
    'a bead growing at the close lands at full size on the first frame, reduced',
    (tester) async {
      const arriving = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1, absenceIndex: -1),
      );
      await pumpReducedColar(tester, arriving);

      await pumpReducedColar(tester, arriving.copyWith(stage: SalaStage.fim));

      expect(
        tester.getSize(find.byType(ThreadIn).first),
        const Size(26, 26),
        reason:
            'com o movimento reduzido a conta ainda crescia 18 para 26px em 700ms — '
            'o primeiro frame a mostrava num tamanho intermediário',
      );
    },
  );

  testWidgets(
    'a bead just spoken into lands filled on the first frame, reduced',
    (tester) async {
      const waiting = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1, absenceIndex: -1),
      );
      await pumpReducedColar(tester, waiting);

      final filled = waiting.copyWith(
        coverage: const Coverage(
          engaged: 1,
          surfaced: 0,
          total: 1,
          absenceIndex: -1,
        ),
      );
      await pumpReducedColar(tester, filled);

      expect(
        renderedDecorationAt(tester, 0).gradient,
        BeadStyles.wood,
        reason:
            'com o movimento reduzido o preenchimento ainda levava 1,3s para assentar — '
            'o primeiro frame mostrava a conta a meio caminho do cheio',
      );
    },
  );
}
