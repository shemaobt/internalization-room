import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  double size = 158,
  ThemeData? theme,
  bool still = false,
  bool warning = false,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$size-${theme?.brightness}-$still-$warning'),
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: size,
            voice: voice,
            warning: warning,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ),
  ),
);

Color _telha(double alpha) =>
    Color.from(alpha: alpha, red: 190 / 255, green: 74 / 255, blue: 1 / 255);

Color _telhaNoEscuro(double alpha) =>
    Color.from(alpha: alpha, red: 227 / 255, green: 106 / 255, blue: 30 / 255);

ArcPainter _arcPainted(WidgetTester tester, Duration period) {
  final arc = tester
      .widgetList<Spin>(_arcs())
      .firstWhere((spin) => spin.period == period);
  return tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byWidget(arc),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((canvas) => canvas.painter)
      .whereType<ArcPainter>()
      .single;
}

Finder _arcs() => find.descendant(
  of: find.byType(FacilitatorCircle),
  matching: find.byType(Spin),
);

double _turnOf(WidgetTester tester, Duration period) {
  final arc = tester
      .widgetList<Spin>(_arcs())
      .firstWhere((spin) => spin.period == period);
  final turned = tester
      .widget<Transform>(
        find.descendant(
          of: find.byWidget(arc),
          matching: find.byType(Transform),
        ),
      )
      .transform;
  return math.atan2(turned.entry(1, 0), turned.entry(0, 0));
}

void main() {
  testWidgets('the arcs turn only while the Guide thinks, in no other voice', (
    tester,
  ) async {
    for (final voice in VoiceState.values) {
      await _pumpCircle(tester, voice);
      expect(
        _arcs(),
        voice == VoiceState.thinking ? findsNWidgets(2) : findsNothing,
        reason: voice == VoiceState.thinking
            ? 'nos ~50 s do turno o círculo só respirava devagar, e a espera '
                  'lia como "nada está acontecendo" (Marcia, 16/09)'
            : 'os arcos dizem que o Guia está trabalhando; em ${voice.name} '
                  'eles diriam uma coisa que não está acontecendo',
      );
    }
  });

  testWidgets(
    'a warning that arrives during a think keeps its green, and the arcs still turn around it',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, warning: true);

      final discs = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Container),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration?)?.gradient)
          .whereType<Gradient>();
      expect(
        discs,
        [BeadStyles.verde],
        reason:
            'o verde é o aviso de que alguém deve vir olhar, e dura turnos '
            'inteiros; ele não some a cada vez que o Guia pensa',
      );
      expect(
        _arcs(),
        findsNWidgets(2),
        reason:
            'com o aviso, o pensar de ~50 s era um disco verde parado — a '
            'mesma espera que lia como "nada está acontecendo"',
      );
    },
  );

  testWidgets(
    'the thick arc turns with the clock in 1.6 s and the thin one against it in 2.6 s',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _turnOf(tester, const Duration(milliseconds: 1600)),
        closeTo(math.pi / 2, 1e-6),
        reason:
            'o arco de 4 px dela dá uma volta em 1,6 s no sentido do relógio: '
            'em 400 ms, um quarto de volta',
      );

      await tester.pump(const Duration(milliseconds: 250));
      expect(
        _turnOf(tester, const Duration(milliseconds: 2600)),
        closeTo(-math.pi / 2, 1e-6),
        reason:
            'o de 2 px gira ao contrário (reverse) em 2,6 s: em 650 ms, um '
            'quarto de volta para o outro lado',
      );
    },
  );

  testWidgets(
    'the whole circle breathes fuller on her 2.4 s while it thinks, the arcs with it',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);
      final breath = find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Loop),
      );
      List<double> drawn() => [
        tester
            .widgetList<Transform>(
              find.descendant(of: breath, matching: find.byType(Transform)),
            )
            .first
            .transform
            .entry(0, 0),
        tester
            .widgetList<Opacity>(
              find.descendant(of: breath, matching: find.byType(Opacity)),
            )
            .first
            .opacity,
      ];

      expect(drawn(), [
        closeTo(0.97, 1e-6),
        closeTo(0.82, 1e-6),
      ], reason: 'thinkBreath dela abre em scale(.97) e opacity .82');

      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        drawn(),
        [closeTo(1.03, 1e-6), closeTo(1, 1e-6)],
        reason:
            'e chega a 1.03 e opacidade cheia na metade dos 2,4 s — a '
            'respiração de 4,6 s e 6% lia como uma sala parada',
      );

      expect(
        find.descendant(of: breath, matching: find.byType(Spin)),
        findsNWidgets(2),
        reason:
            'a respiração dela está no alvo inteiro, pai dos arcos: um disco '
            'que respira com os arcos parados no lugar os deixaria soltos',
      );
    },
  );

  testWidgets(
    'a terracotta glow warms the clay from inside and pulses on her 2.4 s',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);
      final glow = find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is GlowPainter,
        ),
      );
      double glowing() => tester
          .widget<Opacity>(
            find.ancestor(of: glow, matching: find.byType(Opacity)).first,
          )
          .opacity;

      expect(
        (tester.widget<CustomPaint>(glow).painter! as GlowPainter).color,
        _telha(0.16),
        reason: '.glow dela no pensar: radial-gradient de rgba(190,74,1,.16)',
      );
      expect(
        glowing(),
        closeTo(0.45, 1e-6),
        reason: 'thinkGlow dela abre em opacidade .45',
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        glowing(),
        closeTo(1, 1e-6),
        reason: 'e acende por inteiro na metade dos 2,4 s',
      );

      final drawn = find
          .descendant(
            of: find.byType(FacilitatorCircle),
            matching: find.byWidgetPredicate(
              (widget) =>
                  (widget is CustomPaint && widget.painter is GlowPainter) ||
                  (widget is Container &&
                      (widget.decoration as BoxDecoration?)?.gradient != null),
            ),
          )
          .evaluate()
          .map((element) => element.widget)
          .toList();
      expect(
        drawn.last,
        isA<CustomPaint>(),
        reason:
            'o disco dela é translúcido e o brilho aparece através dele; o '
            'nosso barro é opaco, e um brilho pintado por baixo sumiria inteiro',
      );
    },
  );

  testWidgets(
    'a tablet that asks for less motion still sees the arcs, standing, and a 2.4 s pulse of light',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, still: true);
      final angles = <double>{};
      final sizes = <double>{};
      double veil() => tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Opacity),
            ),
          )
          .first
          .opacity;
      void look() {
        angles
          ..add(_turnOf(tester, const Duration(milliseconds: 1600)))
          ..add(_turnOf(tester, const Duration(milliseconds: 2600)));
        for (final moved in tester.widgetList<Transform>(
          find.descendant(
            of: find.byType(FacilitatorCircle),
            matching: find.byType(Transform),
          ),
        )) {
          sizes.add(
            moved.transform.entry(0, 0).abs() +
                moved.transform.entry(1, 0).abs(),
          );
        }
      }

      look();
      expect(
        veil(),
        closeTo(0.72, 1e-6),
        reason: 'thinkPulse dela abre em opacidade .72',
      );
      await tester.pump(const Duration(milliseconds: 1200));
      look();
      expect(
        veil(),
        closeTo(0.96, 1e-6),
        reason:
            'e chega a .96 na metade dos 2,4 s — o pulso de 3,6 s ficou no '
            'andamento antigo quando ela acelerou o pensar',
      );
      await tester.pump(const Duration(milliseconds: 650));
      look();

      expect(angles, {
        0.0,
      }, reason: 'com movimento reduzido os arcos dela ficam, mas parados');
      expect(sizes, {1.0}, reason: 'e o círculo não cresce nem encolhe');
      for (final period in const [
        Duration(milliseconds: 1600),
        Duration(milliseconds: 2600),
      ]) {
        final arc = find.byWidgetPredicate(
          (widget) => widget is Spin && widget.period == period,
        );
        expect(
          tester
              .widget<Opacity>(
                find.ancestor(of: arc, matching: find.byType(Opacity)).first,
              )
              .opacity,
          closeTo(0.9, 1e-6),
          reason:
              'os arcos parados dela ficam em opacidade .9 (:205): quem pede '
              'menos movimento ainda precisa ver que a sala está trabalhando',
        );
      }
    },
  );

  testWidgets(
    'the tablet waiting for its code shows the arcs standing, and never spins them without end',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: CodigoView(language: 'pt')),
        ),
      );
      double breath() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Transform),
            ),
          )
          .first
          .transform
          .entry(0, 0);

      expect(breath(), closeTo(0.97, 1e-6));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        [
          _turnOf(tester, const Duration(milliseconds: 1600)),
          _turnOf(tester, const Duration(milliseconds: 2600)),
        ],
        [0.0, 0.0],
        reason:
            'sem sala, o pedido do código tenta de novo para sempre; arcos '
            'girando ali deixariam o relógio a sessenta sem fim, num aparelho '
            'que ninguém está olhando',
      );
      expect(
        breath(),
        closeTo(1.03, 1e-6),
        reason:
            'mas a tela ainda diz que está trabalhando: só os arcos param, a '
            'respiração e o brilho seguem',
      );
    },
  );

  testWidgets(
    'a tablet that turns on Reduce Motion in the middle of a think stops the arcs that were already turning',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      harness.room.holdNextTurn();
      harness.voice.holdNextLine();
      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.conversaTap();
      await letTheRehearsalReachTheRoom(tester);
      expect(container.read(salaSessionProvider).voice, VoiceState.thinking);

      const thick = Duration(milliseconds: 1600);
      final turning = _turnOf(tester, thick);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _turnOf(tester, thick),
        isNot(closeTo(turning, 1e-6)),
        reason: 'o caso precisa começar com os arcos girando',
      );

      final before = tester.platformDispatcher.accessibilityFeatures;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
            accessibleNavigation: before.accessibleNavigation,
            invertColors: before.invertColors,
            disableAnimations: before.disableAnimations,
            boldText: before.boldText,
            reduceMotion: true,
            highContrast: before.highContrast,
            onOffSwitchLabels: before.onOffSwitchLabels,
            supportsAnnounce: before.supportsAnnounce,
            autoPlayAnimatedImages: before.autoPlayAnimatedImages,
            autoPlayVideos: before.autoPlayVideos,
            deterministicCursor: before.deterministicCursor,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      final stopped = _turnOf(tester, thick);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        [stopped, _turnOf(tester, thick)],
        [0.0, 0.0],
        reason:
            'o iOS manda o Reduzir Movimento como reduceMotion, não como '
            'disableAnimations — a sala só lia o segundo, e no simulador do '
            'João os arcos seguiram girando com o ajuste ligado',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'on her 232 px circle the arcs sit at her insets, widths and alphas',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, size: 232);
      final thick = _arcPainted(tester, const Duration(milliseconds: 1600));
      final thin = _arcPainted(tester, const Duration(milliseconds: 2600));

      expect(
        [thick.side, thick.stroke],
        [closeTo(264.48, 1e-9), closeTo(4, 1e-9)],
        reason: '.r1 dela: inset -7% do alvo de 232 px, borda de 4 px',
      );
      expect(
        [thick.top, thick.right, thick.bottom],
        [_telha(1), _telha(0.35), null],
        reason:
            '.r1: topo em var(--telha), direita em rgba(190,74,1,.35), o '
            'resto transparente',
      );
      expect(
        [thin.side, thin.stroke],
        [closeTo(292.32, 1e-9), closeTo(2, 1e-9)],
        reason: '.r2 dela: inset -13%, borda de 2 px',
      );
      expect(
        [thin.top, thin.right, thin.bottom],
        [null, null, _telha(0.55)],
        reason: '.r2: só a base, em rgba(190,74,1,.55)',
      );
      expect(
        tester.renderObject(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Spin &&
                  widget.period == const Duration(milliseconds: 1600),
            ),
            matching: find.byType(CustomPaint),
          ),
        ),
        paints
          ..arc(
            startAngle: -0.75 * math.pi,
            sweepAngle: math.pi / 2,
            color: _telha(1),
            strokeWidth: 4,
          )
          ..arc(
            startAngle: -0.25 * math.pi,
            sweepAngle: math.pi / 2,
            color: _telha(0.35),
          ),
        reason:
            'a borda de cima de um círculo em CSS é o quarto entre as dez e '
            'meia e a uma e meia do relógio; a da direita vem logo depois',
      );
    },
  );

  testWidgets(
    'each arc is painted inside a box that holds the whole ring, not the disc\'s box',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, size: 232);

      for (final (period, ring) in const [
        (Duration(milliseconds: 1600), 264.48),
        (Duration(milliseconds: 2600), 292.32),
      ]) {
        final painted = tester.getSize(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => widget is Spin && widget.period == period,
            ),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(
          [painted.width, painted.height],
          everyElement(greaterThanOrEqualTo(ring - 1e-9)),
          reason:
              'o anel de ${ring.toStringAsFixed(2)} px era pintado numa caixa '
              'do tamanho do disco (232 px), dentro de uma RepaintBoundary: '
              'o que passa da caixa fica à mercê do motor não cortar',
        );
      }
      expect(
        tester.getSize(find.byType(FacilitatorCircle)),
        const Size(232, 232),
        reason: 'e o círculo continua ocupando só o disco na tela',
      );
    },
  );

  testWidgets(
    'the 54 px retro circle wears the same arcs at its own scale, not at 232 px strokes',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, size: 54);
      final thick = _arcPainted(tester, const Duration(milliseconds: 1600));
      final thin = _arcPainted(tester, const Duration(milliseconds: 2600));

      expect(
        [thick.side, thick.stroke, thin.side, thin.stroke],
        [
          closeTo(61.56, 1e-9),
          closeTo(0.931, 1e-3),
          closeTo(68.04, 1e-9),
          closeTo(0.466, 1e-3),
        ],
        reason:
            'com a borda de 4 px dela no círculo de 54 px, o arco teria '
            'quase um décimo do disco, e o traço ficaria pesado perto das contas',
      );
    },
  );

  testWidgets('the arcs take the dark paper\'s terracotta, not the light one', (
    tester,
  ) async {
    await _pumpCircle(tester, VoiceState.thinking, theme: AppTheme.dark);
    final thick = _arcPainted(tester, const Duration(milliseconds: 1600));
    final thin = _arcPainted(tester, const Duration(milliseconds: 2600));

    expect(
      [thick.top, thick.right, thin.bottom],
      [_telhaNoEscuro(1), _telhaNoEscuro(0.35), _telhaNoEscuro(0.55)],
      reason:
          'a telha do papel claro some no escuro; o círculo lê a telha do '
          'tema, como o anel da fala já faz',
    );
  });
}
