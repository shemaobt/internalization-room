import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

const _side = 217.5;

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool peerCue = false,
  bool noteMode = false,
  bool still = false,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$peerCue-$noteMode-$still-${theme?.brightness}'),
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: _side,
            voice: voice,
            peerCue: peerCue,
            noteMode: noteMode,
            canvas: true,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ),
  ),
);

List<BoxDecoration> _painted(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .toList();

List<BoxDecoration> _rings(WidgetTester tester) => _painted(
  tester,
).where((paint) => paint.border != null && paint.gradient != null).toList();

RadialGradient _fill(List<Color> colors, List<double> stops) => RadialGradient(
  center: const Alignment(0, -0.08),
  radius: 0.7359,
  colors: colors,
  stops: stops,
);

final _inviteFill = _fill(
  [
    Color.fromRGBO(190, 74, 1, .14),
    Color.fromRGBO(199, 194, 159, .18),
    Color.fromRGBO(199, 194, 159, .04),
  ],
  [0, .6, 1],
);

final _coreFill = _fill(
  [
    Color.fromRGBO(190, 74, 1, .10),
    Color.fromRGBO(199, 194, 159, .16),
    Color.fromRGBO(199, 194, 159, .05),
  ],
  [0, .62, 1],
);

final _listeningFill = _fill(
  [
    Color.fromRGBO(137, 170, 163, .14),
    Color.fromRGBO(199, 194, 159, .12),
    Color.fromRGBO(199, 194, 159, 0),
  ],
  [0, .64, 1],
);

final _speakingFill = _fill(
  [Color.fromRGBO(190, 74, 1, .06), Color.fromRGBO(190, 74, 1, 0)],
  [0, .6],
);

void main() {
  testWidgets('the canvas circle is her hollow ring in every voice, a 1.5 '
      'edge over a faint fill, never the filled disc', (tester) async {
    for (final (voice, peerCue, edge, fill, hers) in [
      (
        VoiceState.invite,
        false,
        const Color(0xFFBE4A01),
        _inviteFill,
        'globals.css:193-194',
      ),
      (
        VoiceState.invite,
        true,
        const Color(0xFFBE4A01),
        _inviteFill,
        'globals.css:193-194',
      ),
      (
        VoiceState.done,
        false,
        const Color(0xFFBE4A01),
        _coreFill,
        'globals.css:113-114, :231',
      ),
      (
        VoiceState.listening,
        false,
        const Color(0xFF89AAA3),
        _listeningFill,
        'globals.css:197-198',
      ),
      (
        VoiceState.thinking,
        false,
        const Color(0xFFC5C29F),
        _coreFill,
        'globals.css:113-114, :204',
      ),
      (
        VoiceState.speaking,
        false,
        Color.fromRGBO(199, 194, 159, .5),
        _speakingFill,
        'globals.css:221-222',
      ),
    ]) {
      await _pumpCircle(tester, voice, peerCue: peerCue);
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        _rings(tester),
        hasLength(1),
        reason: 'em ${voice.name} o círculo era um disco cheio ($hers)',
      );
      final ring = _rings(tester).single;
      expect(ring.border, Border.all(color: edge, width: 1.5), reason: hers);
      expect(ring.gradient, fill, reason: 'o preenchimento dela ($hers)');
      expect(
        ring.boxShadow,
        isNull,
        reason: 'o disco telha jogava uma sombra; o anel dela não tem',
      );
      expect(
        _painted(tester).where((paint) => paint.gradient != null),
        [ring],
        reason: 'por baixo do anel ainda havia o disco cheio, em ${voice.name}',
      );
    }
  });

  testWidgets('a note being left draws her blue-green ring, held still, '
      'not a telha breath', (tester) async {
    final noteFill = _fill(
      [
        Color.fromRGBO(137, 170, 163, .16),
        Color.fromRGBO(199, 194, 159, .12),
        Color.fromRGBO(199, 194, 159, .04),
      ],
      [0, .62, 1],
    );
    for (final voice in [VoiceState.invite, VoiceState.listening]) {
      await _pumpCircle(tester, voice, noteMode: true);
      final scales = <double>{};
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(_rings(tester), hasLength(1));
        final ring = _rings(tester).single;
        expect(
          ring.border,
          Border.all(color: const Color(0xFF89AAA3), width: 1.5),
          reason:
              'o recado em ${voice.name} vestia o anel da voz '
              '(globals.css:169)',
        );
        expect(ring.gradient, noteFill, reason: 'globals.css:169-170');
        scales.addAll(
          tester
              .widgetList<Transform>(
                find.ancestor(
                  of: find.byWidgetPredicate(
                    (widget) =>
                        widget is Container && widget.decoration == ring,
                  ),
                  matching: find.byType(Transform),
                ),
              )
              .map((move) => move.transform.getMaxScaleOnAxis()),
        );
      }
      expect(
        scales.every((scale) => scale == 1),
        isTrue,
        reason:
            'o recado respirava como o convite; o dela fica parado '
            '(globals.css:168): $scales',
      );
    }
  });

  testWidgets('while the team speaks her three blue-green rings grow out of '
      'the circle, not two rings closing in', (tester) async {
    await _pumpCircle(tester, VoiceState.listening);
    await tester.pump(const Duration(milliseconds: 2400));

    final rings = [
      for (final ripple in find.byType(Ripple).evaluate())
        (
          tester
              .widget<Transform>(
                find.descendant(
                  of: find.byWidget(ripple.widget),
                  matching: find.byType(Transform),
                ),
              )
              .transform
              .storage[0],
          (tester
                      .widget<Container>(
                        find.descendant(
                          of: find.byWidget(ripple.widget),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .border!
              .top,
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    expect(
      rings.length,
      3,
      reason: 'ouvindo, o dela desenha três ondas (globals.css:199-201)',
    );
    for (final ((scale, edge), (herScale, herOpacity)) in [
      for (final (index, ring) in rings.indexed)
        (
          ring,
          const [(0.7358, 0.4283), (1.1387, 0.1896), (1.4178, 0.063)][index],
        ),
    ]) {
      expect(
        scale,
        closeTo(herScale, 0.002),
        reason:
            'as ondas iam de 1,46 para 1, para dentro; as dela crescem '
            'de .62 a 1.5 em 3,2 s, 1,07 s uma da outra (globals.css:202)',
      );
      expect(edge.width, 1.2);
      expect(edge.color.toARGB32() & 0xFFFFFF, 0x89AAA3);
      expect(
        edge.color.a,
        closeTo(herOpacity, 0.002),
        reason:
            'a onda some de .5 a .06 aos 80% e a 0 no fim (globals.css:202)',
      );
    }
    expect(
      _painted(tester).where((paint) => paint.boxShadow != null),
      isEmpty,
      reason: 'o anel de 3 px com brilho que ouvia não é dela',
    );
  });
}
