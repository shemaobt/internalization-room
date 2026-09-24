import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  double size = 158,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$size-${theme?.brightness}'),
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          size: size,
          voice: voice,
          semanticLabel: 'circulo',
          onTap: () {},
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
