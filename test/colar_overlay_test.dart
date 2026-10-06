import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
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

  Coverage answer(Map<String, dynamic> json) => Coverage.fromJson(json);

  BoxDecoration decorationAt(WidgetTester tester, int index) =>
      tester
              .widget<AnimatedContainer>(
                find.byType(AnimatedContainer).at(index),
              )
              .decoration
          as BoxDecoration;

  int litBeads(WidgetTester tester) {
    var lit = 0;
    final drawn = find.byType(AnimatedContainer).evaluate().length;
    for (var i = 0; i < drawn; i++) {
      if (decorationAt(tester, i).gradient == BeadStyles.wood) lit++;
    }
    return lit;
  }

  testWidgets('a bead nobody has spoken into waits, whatever the guide surfaced', (
    tester,
  ) async {
    final session = SalaSessionState(
      coverage: answer({
        'engaged': 0,
        'surfaced': 10,
        'total': 29,
        'beads_total': 12,
        'beads_filled': 0,
      }),
    );
    await pumpColar(tester, session);

    expect(find.byType(AnimatedContainer), findsNWidgets(12));
    for (var i = 0; i < 12; i++) {
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

  testWidgets('exactly the beads the room names come back filled', (
    tester,
  ) async {
    final session = SalaSessionState(
      coverage: answer({
        'engaged': 3,
        'surfaced': 3,
        'total': 29,
        'beads_total': 12,
        'beads_filled': 5,
      }),
    );
    await pumpColar(tester, session);

    expect(
      litBeads(tester),
      5,
      reason: 'a conta enche com o que a sala diz, nunca mais nem menos',
    );
  });

  testWidgets(
    'a coverage answer of nine elements with three engaged draws twelve beads and lights four',
    (tester) async {
      final session = SalaSessionState(
        coverage: answer({
          'engaged': 3,
          'surfaced': 3,
          'total': 9,
          'beads_total': 12,
          'beads_filled': 4,
        }),
      );
      await pumpColar(tester, session);

      expect(find.byType(AnimatedContainer), findsNWidgets(12));
      expect(litBeads(tester), 4);
    },
  );

  testWidgets(
    'a coverage answer of fifteen elements all engaged draws twelve beads all lit',
    (tester) async {
      final session = SalaSessionState(
        coverage: answer({
          'engaged': 15,
          'surfaced': 15,
          'total': 15,
          'beads_total': 12,
          'beads_filled': 12,
        }),
      );
      await pumpColar(tester, session);

      expect(find.byType(AnimatedContainer), findsNWidgets(12));
      expect(litBeads(tester), 12);
    },
  );

  testWidgets(
    'a coverage answer of ten beads with three filled draws ten beads and lights three',
    (tester) async {
      final session = SalaSessionState(
        coverage: answer({
          'engaged': 3,
          'surfaced': 3,
          'total': 9,
          'beads_total': 10,
          'beads_filled': 3,
        }),
      );
      await pumpColar(tester, session);

      expect(find.byType(AnimatedContainer), findsNWidgets(10));
      expect(litBeads(tester), 3);
    },
  );

  testWidgets(
    'a coverage answer without the bead fields draws twelve beads with none lit',
    (tester) async {
      final session = SalaSessionState(
        coverage: answer({
          'engaged': 5,
          'surfaced': 5,
          'total': 9,
          'absence_index': -1,
        }),
      );
      await pumpColar(tester, session);

      expect(find.byType(AnimatedContainer), findsNWidgets(12));
      expect(litBeads(tester), 0);
    },
  );

  testWidgets(
    'the necklace lights the beads the room names, not the elements engaged',
    (tester) async {
      final session = SalaSessionState(
        coverage: answer({
          'engaged': 1,
          'surfaced': 1,
          'total': 29,
          'beads_total': 12,
          'beads_filled': 0,
        }),
      );
      await pumpColar(tester, session);

      expect(litBeads(tester), 0);
    },
  );

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
      coverage: answer({
        'engaged': 1,
        'surfaced': 0,
        'total': 1,
        'beads_total': 12,
        'beads_filled': 1,
      }),
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
    final session = SalaSessionState(
      machine: Machine(station: Station.stored(SalaStage.fim)),
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
    'a bead whose slot changes lands there on the first frame, reduced',
    (tester) async {
      const arriving = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1, absenceIndex: -1),
      );
      await pumpReducedColar(tester, arriving);

      await pumpReducedColar(
        tester,
        arriving.copyWith(
          machine: Machine(station: Station.stored(SalaStage.fim)),
        ),
      );
      final landedTopLeft = tester.getTopLeft(
        find.byType(AnimatedPositioned).first,
      );

      await tester.pumpWidget(Container());
      await pumpReducedColar(
        tester,
        arriving.copyWith(
          machine: Machine(station: Station.stored(SalaStage.fim)),
        ),
      );
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

      await pumpReducedColar(
        tester,
        arriving.copyWith(
          machine: Machine(station: Station.stored(SalaStage.fim)),
        ),
      );

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
        coverage: answer({
          'engaged': 1,
          'surfaced': 0,
          'total': 1,
          'beads_total': 12,
          'beads_filled': 1,
        }),
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
