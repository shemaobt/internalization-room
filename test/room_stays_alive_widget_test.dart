import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Widget _circleIn(VoiceState voice, {Halt halt = const NoHalt()}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(
      child: FacilitatorCircle(
        halt: halt,
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
    for (final transform in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Transform),
      ),
    )) {
      seen.add(transform.transform.entry(0, 0));
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

    double peak(Set<double> seen) => seen.reduce((a, b) => a > b ? a : b);

    // Counting distinct scales passes at an amplitude of 0.00002 — four thousandths of a
    // pixel on a 196 px disc. What the claim is: the same breath as every other invite,
    // so both reach the same peak, and that peak is visible.
    expect(peak(withTeam), greaterThan(1.04));
    expect(
      (peak(withTeam) - peak(alone)).abs(),
      lessThan(0.004),
      reason:
          'a afirmação não é que respira, é que respira igual a todo invite',
    );
  });

  testWidgets(
    'a room breathing below one is not mistaken for a room standing still',
    (tester) async {
      final seen = await _scalesOver(tester, _circleIn(VoiceState.thinking));

      expect(
        seen.any((scale) => scale < 1.0),
        isTrue,
        reason:
            'a espera desce a 0,97 a cada volta, e getMaxScaleOnAxis conta o '
            'eixo z parado em 1 como se fosse o maior — o encolhimento nunca '
            'aparecia',
      );
    },
  );

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

  testWidgets('the room speaking is a circle that moves, not a still orange disc', (
    tester,
  ) async {
    await tester.pumpWidget(_circleIn(VoiceState.speaking));
    final body = <double>{};
    for (var frame = 0; frame < 44; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
      final rings = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(Ripple),
              matching: find.byType(Transform),
            ),
          )
          .toSet();
      for (final transform in tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Transform),
        ),
      )) {
        if (!rings.contains(transform)) {
          body.add(transform.transform.entry(0, 0));
        }
      }
    }
    final swing =
        body.reduce((a, b) => a > b ? a : b) -
        body.reduce((a, b) => a < b ? a : b);

    expect(
      swing,
      greaterThan(0.015),
      reason:
          'falando é o único estado em que a sala está fazendo algo audível, e uma '
          'bola parada não se distingue de uma sala que travou no meio da fala',
    );
  });

  testWidgets('a halted room is still visibly running', (tester) async {
    for (final (name, voice, halt) in [
      ('needsPerson', VoiceState.invite, const Blocking(NothingKept())),
      ('offline', VoiceState.offline, const NoHalt()),
      ('blocked', VoiceState.blocked, const NoHalt()),
    ]) {
      final seen = await _scalesOver(tester, _circleIn(voice, halt: halt));
      final swing =
          seen.reduce((a, b) => a > b ? a : b) -
          seen.reduce((a, b) => a < b ? a : b);

      expect(
        swing,
        greaterThan(0.015),
        reason:
            '$name fala sua linha uma vez e depois nunca mais; sem movimento, '
            'olhar para essa tela não distingue uma sala esperando de um app morto',
      );
    }
  });

  testWidgets('a thing that arrives fades in, and never slides up into place', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: FadeUp(child: SizedBox(width: 120, height: 120))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.descendant(
        of: find.byType(FadeUp),
        matching: find.byType(Transform),
      ),
      findsNothing,
      reason:
          'tudo o que aparecia na sala subia dez pixels enquanto aparecia, '
          'e um deslize é a única coisa que o olho de quem está concentrado na '
          'conversa pega sem querer olhar',
    );

    final veu = tester.widget<Opacity>(
      find.descendant(of: find.byType(FadeUp), matching: find.byType(Opacity)),
    );
    expect(
      veu.opacity,
      greaterThan(0.0),
      reason: 'e ele continua sendo uma chegada, não um corte',
    );
    expect(
      veu.opacity,
      lessThan(1.0),
      reason:
          'no meio da chegada ela ainda está acontecendo — sem isto o '
          'caso passaria com o esmaecer arrancado junto com o deslize',
    );
  });

  testWidgets(
    'the small motions stop too when the tablet asks for less of them',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Column(
              children: const [
                Pulse(child: SizedBox(width: 10, height: 10)),
                PingIn(child: SizedBox(width: 10, height: 10)),
                FadeUp(child: SizedBox(width: 10, height: 10)),
                ThreadIn(
                  index: 0,
                  total: 3,
                  child: SizedBox(width: 10, height: 10),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(Loop),
        findsNothing,
        reason:
            'o pulsar de um botão continua sendo movimento para quem '
            'desligou o movimento',
      );
      expect(
        find.byType(TweenAnimationBuilder<double>),
        findsNothing,
        reason:
            'e o aparecer, o chegar e o enfiar da conta no cordão também — '
            'quatro portões escritos e nenhum caso: apagar os quatro deixava a '
            'suíte inteira verde',
      );
      expect(
        find.byType(Transform),
        findsNothing,
        reason: 'nada cresce, nada encolhe e nada anda de lugar',
      );
    },
  );
}
