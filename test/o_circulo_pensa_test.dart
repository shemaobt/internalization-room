import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

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
            warningLabel: 'Alguém deve vir olhar',
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

Finder _spins() => find.descendant(
  of: find.byType(FacilitatorCircle),
  matching: find.byType(Spin),
);

Iterable<Gradient> _gradients(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .map((paint) => paint.gradient)
    .whereType<Gradient>();

void main() {
  testWidgets('no voice ever draws a turning arc any more', (tester) async {
    for (final voice in VoiceState.values) {
      await _pumpCircle(tester, voice);
      expect(
        _spins(),
        findsNothing,
        reason:
            'os arcos giravam sozinhos, sem dizer nada que a respiração e o '
            'brilho já não dissessem — e nos ~50 s do turno de pensar a sala '
            'lia como um relógio, não como alguém trabalhando (Henok, '
            'revertendo o PR #230)',
      );
    }
  });

  testWidgets(
    'a warning that arrives during a think leaves the clay disc as it was',
    (tester) async {
      await _pumpCircle(tester, VoiceState.thinking, warning: true);

      expect(
        _gradients(tester),
        contains(BeadStyles.clay(SalaColors.light)),
        reason:
            'o pensar já tem a sua própria cor de barro; o aviso não é mais '
            'uma cor do disco, em nenhuma voz',
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Alguém deve vir olhar',
        ),
        findsOneWidget,
        reason: 'o aviso ainda existe — só que ao lado, nunca por cima',
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
