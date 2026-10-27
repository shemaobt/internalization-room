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
  bool still = false,
  bool canvas = false,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$size-${theme?.brightness}-$still-$canvas'),
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: size,
            voice: voice,
            canvas: canvas,
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

bool _rotates(Transform transform) =>
    transform.transform.entry(0, 1) != 0 ||
    transform.transform.entry(1, 0) != 0;

Iterable<Transform> _transformsInCircle(WidgetTester tester) =>
    tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Transform),
      ),
    );

Finder _arcs() => find.descendant(
  of: find.byType(FacilitatorCircle),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ArcPainter,
  ),
);

List<ArcPainter> _arcPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(_arcs())
    .map((paint) => paint.painter! as ArcPainter)
    .toList();

List<double> _arcTurns(WidgetTester tester) => [
  for (final element in _arcs().evaluate())
    () {
      final matrix = tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.byWidget(element.widget),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform;
      return math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));
    }(),
];

void main() {
  testWidgets(
    'while the voice thinks on the conversation, her two terracotta arcs turn '
    'round the circle, not the clay breath alone',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, size: 232, canvas: true);

      final arcs = _arcPainters(tester);
      expect(
        arcs,
        hasLength(2),
        reason:
            'o pensar só respirava o barro, e no dia 16/09 a Marcia mediu com '
            'o Jonas o que isso lê: nada está acontecendo (globals.css:206-212)',
      );
      expect(
        [
          arcs[0].side,
          arcs[0].stroke,
          arcs[0].top,
          arcs[0].right,
          arcs[0].bottom,
        ],
        [closeTo(264.48, 1e-9), 4, _telha(1), _telha(0.35), null],
        reason: '.r1 dela: inset -7%, 4px, topo telha e direita a .35',
      );
      expect(
        [
          arcs[1].side,
          arcs[1].stroke,
          arcs[1].top,
          arcs[1].right,
          arcs[1].bottom,
        ],
        [closeTo(292.32, 1e-9), 2, null, null, _telha(0.55)],
        reason: '.r2 dela: inset -13%, 2px, só a base a .55',
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _arcTurns(tester),
        [closeTo(math.pi / 2, 1e-6), closeTo(-2 * math.pi * 400 / 2600, 1e-6)],
        reason:
            'thinkSpin dela: o grosso dá a volta com o relógio em 1,6 s e o '
            'fino contra o relógio em 2,6 s',
      );
    },
  );

  testWidgets('no voice ever draws a turning transform', (tester) async {
    for (final still in [false, true]) {
      for (final voice in VoiceState.values) {
        await _pumpCircle(tester, voice, still: still);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          _transformsInCircle(tester),
          isNot(anyElement(predicate(_rotates))),
          reason:
              'os arcos giravam sozinhos, sem dizer nada que a respiração e o '
              'brilho já não dissessem — e nos ~50 s do turno de pensar a sala '
              'lia como um relógio, não como alguém trabalhando (Henok, '
              'revertendo o PR #230); em ${voice.name} (still=$still) não pode '
              'haver nem essa volta',
        );
      }
    }
  });

  testWidgets(
    'the thinking circle paints only the clay disc and its glow, nothing else',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking);

      final painters = find
          .descendant(
            of: find.byType(FacilitatorCircle),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .map((element) => (element.widget as CustomPaint).painter)
          .whereType<Object>()
          .map((painter) => painter.runtimeType)
          .toSet();

      expect(
        painters,
        {GlowPainter},
        reason:
            'ArcPainter pintava dois arcos por cima do disco; sem eles não '
            'sobra nenhum outro CustomPaint além do brilho',
      );
    },
  );

  testWidgets('the whole circle breathes fuller on her 2.4 s while it thinks', (
    tester,
  ) async {
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
  });

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
    'a tablet that asks for less motion still sees a 2.4 s pulse of light',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, still: true);
      double veil() => tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Opacity),
            ),
          )
          .first
          .opacity;

      expect(
        veil(),
        closeTo(0.72, 1e-6),
        reason: 'thinkPulse dela abre em opacidade .72',
      );
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        veil(),
        closeTo(0.96, 1e-6),
        reason:
            'e chega a .96 na metade dos 2,4 s — o pulso de 3,6 s ficou no '
            'andamento antigo quando ela acelerou o pensar',
      );
    },
  );
}
