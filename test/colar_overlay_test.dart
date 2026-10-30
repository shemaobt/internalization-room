import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
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

  bool isFilled(BoxDecoration d) =>
      d.color == SalaColors.light.verdeClaro.withValues(alpha: 0.92);

  int litBeads(WidgetTester tester) {
    var lit = 0;
    final drawn = find.byType(AnimatedContainer).evaluate().length;
    for (var i = 0; i < drawn; i++) {
      if (isFilled(decorationAt(tester, i))) lit++;
    }
    return lit;
  }

  testWidgets(
    'a bead nobody has spoken into waits, whatever the guide surfaced',
    (tester) async {
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
          decorationAt(tester, i).color,
          SalaColors.light.areia.withValues(alpha: 0.55),
          reason:
              'uma conta que o time não falou é uma conta vazia, mesmo surfaced',
        );
      }
    },
  );

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
        coverage: answer({'engaged': 5, 'surfaced': 5, 'total': 9}),
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
      coverage: Coverage(engaged: 0, surfaced: 0, total: 1),
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

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      isFilled(renderedDecorationAt(tester, 0)),
      isFalse,
      reason:
          'em 700ms a conta já teria assentado — o settle é de 1,3s, não 700ms',
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(
      isFilled(renderedDecorationAt(tester, 0)),
      isTrue,
      reason: 'em 1,3s a conta acabou de assentar no cheio, sem pulo de escala',
    );
  });

  testWidgets('the necklace closes in stillness, not a loop', (tester) async {
    final session = SalaSessionState(
      machine: Machine(station: Station.stored(SalaStage.conversa)),
      coverage: Coverage(engaged: 5, surfaced: 5, total: 5),
    );
    await pumpColar(tester, session);

    expect(
      find.byType(Loop),
      findsNothing,
      reason:
          'o fecho da passagem é quietude, a tela de celebração o design proíbe',
    );
  });

  testWidgets('the beads stay where they sat when the passage closes', (
    tester,
  ) async {
    const conversing = SalaSessionState(
      coverage: Coverage(engaged: 0, surfaced: 0, total: 1),
    );
    await pumpColar(tester, conversing);
    final hung = [
      for (var i = 0; i < 12; i++)
        tester.getCenter(find.byType(ThreadIn).at(i)),
    ];

    await pumpColar(
      tester,
      conversing.copyWith(
        machine: Machine(station: Station.stored(SalaStage.conversa)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    for (var i = 0; i < 12; i++) {
      expect(
        tester.getCenter(find.byType(ThreadIn).at(i)),
        hung[i],
        reason:
            'no fecho a conta $i deslizava do arco para um círculo em volta do '
            'facilitador — o time via o colar se mexer quando nada tinha mudado',
      );
    }
  });

  testWidgets(
    'the beads sit in one row with nothing drawn under them, at the Closing '
    'and in the conversation',
    (tester) async {
      final closing = SalaSessionState(
        machine: Machine(station: Station.stored(SalaStage.conversa)),
        coverage: const Coverage(engaged: 0, surfaced: 0, total: 1),
      );
      const conversing = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1),
      );

      for (final session in [closing, conversing]) {
        await pumpColar(tester, session);
        await tester.pump(const Duration(seconds: 2));

        expect(
          find.descendant(
            of: find.byType(ColarOverlay),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
          reason:
              'um cordão em arco atravessava a tela por baixo das contas, e o '
              'colar dela é só a fileira de contas',
        );
      }
    },
  );

  testWidgets('the beads are 9 px and 11 px apart, as hers, in the '
      'conversation and at the Closing', (tester) async {
    const conversing = SalaSessionState(
      coverage: Coverage(engaged: 0, surfaced: 0, total: 1),
    );
    for (final session in [
      conversing,
      conversing.copyWith(
        machine: Machine(station: Station.stored(SalaStage.conversa)),
      ),
    ]) {
      await pumpColar(tester, session);
      await tester.pump(const Duration(seconds: 2));

      for (var i = 0; i < 12; i++) {
        expect(
          tester.getSize(find.byType(ThreadIn).at(i)),
          const Size(9, 9),
          reason: 'as contas tinham 16 px, quase o dobro das dela',
        );
      }
      for (var i = 1; i < 12; i++) {
        expect(
          tester.getTopLeft(find.byType(ThreadIn).at(i)).dx -
              tester.getTopRight(find.byType(ThreadIn).at(i - 1)).dx,
          moreOrLessEquals(11, epsilon: 0.01),
          reason: 'o espaço entre as contas não era o dela',
        );
      }
    }
  });

  SalaSessionState fiveOfTwelve({bool closing = false}) {
    final coverage = answer({
      'engaged': 5,
      'surfaced': 5,
      'total': 29,
      'beads_total': 12,
      'beads_filled': 5,
    });
    return closing
        ? SalaSessionState(
            machine: Machine(station: Station.stored(SalaStage.conversa)),
            coverage: coverage,
          )
        : SalaSessionState(coverage: coverage);
  }

  void expectFiveFilledAndSevenAtRest(
    WidgetTester tester, {
    SalaColors colors = SalaColors.light,
  }) {
    for (var i = 0; i < 12; i++) {
      final color = decorationAt(tester, i).color!;
      if (i < 5) {
        expect(color.a, closeTo(0.92, 0.005), reason: 'a conta $i está cheia');
        expect(
          color.toARGB32() & 0x00FFFFFF,
          colors.verdeClaro.toARGB32() & 0x00FFFFFF,
        );
      } else {
        expect(
          color.a,
          closeTo(0.55, 0.005),
          reason: 'a conta $i está em repouso',
        );
        expect(
          color.toARGB32() & 0x00FFFFFF,
          colors.areia.toARGB32() & 0x00FFFFFF,
        );
      }
    }
  }

  testWidgets(
    'a filled bead is verde-claro at .92, a resting one areia at .55',
    (tester) async {
      await pumpReducedColar(tester, fiveOfTwelve());

      expectFiveFilledAndSevenAtRest(tester);
    },
  );

  testWidgets('the filled beads keep their colour at the Closing', (
    tester,
  ) async {
    await pumpReducedColar(tester, fiveOfTwelve(closing: true));

    expectFiveFilledAndSevenAtRest(tester);
  });

  testWidgets('the dark necklace reads her dark areia and verde-claro', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ColarOverlay(session: fiveOfTwelve())),
        ),
      ),
    );

    expectFiveFilledAndSevenAtRest(tester, colors: SalaColors.dark);
  });

  testWidgets('the growing edge scales 1.1 and a just-filled bead 1.2', (
    tester,
  ) async {
    double scaleOf(int i) =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).at(i)).scale;

    await pumpReducedColar(tester, fiveOfTwelve());
    expect([for (var i = 0; i < 7; i++) scaleOf(i)], [1, 1, 1, 1, 1.1, 1, 1]);

    await pumpReducedColar(
      tester,
      fiveOfTwelve().copyWith(
        coverage: answer({
          'engaged': 6,
          'surfaced': 6,
          'total': 29,
          'beads_total': 12,
          'beads_filled': 6,
        }),
      ),
    );
    expect(scaleOf(5), 1.2);
    expect(scaleOf(4), 1);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(scaleOf(5), 1.1);
  });

  testWidgets('the row sits 9% of the canvas box above its bottom edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 1000),
            disableAnimations: true,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 500,
              child: ColarOverlay(session: fiveOfTwelve()),
            ),
          ),
        ),
      ),
    );

    expect(tester.getBottomLeft(find.byType(ThreadIn).first).dy, 500 * 0.91);
  });

  testWidgets(
    'a bead just spoken into lands filled on the first frame, reduced',
    (tester) async {
      const waiting = SalaSessionState(
        coverage: Coverage(engaged: 0, surfaced: 0, total: 1),
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
        isFilled(renderedDecorationAt(tester, 0)),
        isTrue,
        reason:
            'com o movimento reduzido o preenchimento ainda levava 1,3s para assentar — '
            'o primeiro frame mostrava a conta a meio caminho do cheio',
      );
    },
  );
}
