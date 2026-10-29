import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

const _side = 150.0;

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  Tongue? tongue,
  bool answersATouch = true,
  String? notUnderstood,
  bool still = false,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$tongue-$answersATouch-$still-${theme?.brightness}'),
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: _side,
            voice: voice,
            tongue: tongue,
            answersATouch: answersATouch,
            notUnderstood: notUnderstood,
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

const _lightFill = RadialGradient(
  center: Alignment(0, -0.08),
  radius: 0.7359,
  colors: [
    Color.fromRGBO(199, 194, 159, .18),
    Color.fromRGBO(199, 194, 159, .06),
  ],
  stops: [0, .7],
);

const _darkFill = RadialGradient(
  center: Alignment(0, -0.08),
  radius: 0.7359,
  colors: [
    Color.fromRGBO(110, 106, 87, .18),
    Color.fromRGBO(110, 106, 87, .05),
  ],
  stops: [0, .7],
);

void _expectHollow(
  WidgetTester tester,
  Color edge,
  String hers, {
  RadialGradient fill = _lightFill,
}) {
  expect(_rings(tester), hasLength(1), reason: hers);
  final ring = _rings(tester).single;
  expect(ring.shape, BoxShape.circle);
  expect(ring.border, Border.all(color: edge, width: 1.5), reason: hers);
  expect(ring.gradient, fill, reason: hers);
  expect(ring.boxShadow, isNull, reason: 'o .cdot dela não tem sombra');
  expect(
    _painted(tester)
        .expand((paint) => paint.gradient?.colors ?? const <Color>[])
        .where((color) => color.a == 1),
    isEmpty,
    reason: 'por baixo do anel ainda havia a conta cheia, um disco opaco',
  );
}

(double, double) _breath(WidgetTester tester) {
  final ring = find.descendant(
    of: find.byType(FacilitatorCircle),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          (widget.decoration as BoxDecoration?)?.border != null,
    ),
  );
  return (
    find
        .ancestor(of: ring, matching: find.byType(Transform))
        .evaluate()
        .map((element) => (element.widget as Transform).transform)
        .fold(1.0, (scale, matrix) => scale * matrix.storage[0]),
    find
        .ancestor(of: ring, matching: find.byType(Opacity))
        .evaluate()
        .map((element) => (element.widget as Opacity).opacity)
        .fold(1.0, (seen, opacity) => seen * opacity),
  );
}

void main() {
  testWidgets('at rest the check circle is her hollow telha ring, not a '
      'filled bead', (tester) async {
    for (final voice in [VoiceState.invite, VoiceState.done]) {
      await _pumpCircle(tester, voice);
      await tester.pump(const Duration(milliseconds: 80));

      _expectHollow(
        tester,
        const Color(0xFFBE4A01),
        'em repouso o .cdot dela é um anel de 1,5 px telha sobre o areia '
        'translúcido (globals.css:376-379); em ${voice.name} o nosso era a '
        'conta telha cheia',
      );
    }
  });

  testWidgets('while it speaks the check circle is her telha ring on a 3.4 s '
      'thinkBreath, with no ripples, in every tongue', (tester) async {
    for (final tongue in [null, ...Tongue.values]) {
      await _pumpCircle(tester, VoiceState.speaking, tongue: tongue);

      _expectHollow(
        tester,
        const Color(0xFFBE4A01),
        'falando, o .cdot dela tem a borda telha (globals.css:383) e não '
        'olha a língua; em $tongue o nosso era uma conta cheia',
      );
      expect(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Ripple),
        ),
        findsNothing,
        reason: 'falando o círculo de checagem dela não tem anéis (:383)',
      );

      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _breath(tester).$1,
        closeTo(.97, 1e-3),
        reason: 'thinkBreath abre em .97',
      );
      expect(
        _breath(tester).$2,
        closeTo(.82, 1e-3),
        reason: 'e em opacidade .82',
      );
      await tester.pump(const Duration(milliseconds: 1700));
      expect(
        _breath(tester).$1,
        closeTo(1.03, 1e-3),
        reason: 'no meio dos 3,4 s dela o anel chega a 1.03 (globals.css:209)',
      );
      expect(_breath(tester).$2, closeTo(1, 1e-3));
    }
  });

  testWidgets('while the team speaks her two blue-green ripples grow out of '
      'the check ring every 3 s, half a turn apart, in every tongue', (
    tester,
  ) async {
    List<(double, BorderSide)> ripples() => [
      for (final ripple
          in find
              .descendant(
                of: find.byType(FacilitatorCircle),
                matching: find.byType(Ripple),
              )
              .evaluate())
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
    List<double> scales() => [for (final (scale, _) in ripples()) scale];

    for (final tongue in [null, ...Tongue.values]) {
      await _pumpCircle(tester, VoiceState.listening, tongue: tongue);

      _expectHollow(
        tester,
        const Color(0xFF89AAA3),
        'ouvindo, o .cdot dela tem a borda azul (globals.css:380) em qualquer '
        'língua; em $tongue o nosso era uma conta cheia com um aro de 3 px',
      );
      expect(
        ripples(),
        hasLength(2),
        reason: 'ela tem dois .ring, r1 e r2 (globals.css:381-382)',
      );
      final (born, side) = ripples().first;
      expect(born, closeTo(.62, 1e-3), reason: 'o ripple dela nasce em .62');
      expect(side.width, 1.2, reason: '.ring tem 1,2 px (globals.css:378)');
      expect(side.color.toARGB32() & 0xFFFFFF, 0x89AAA3);
      expect(side.color.a, closeTo(.5, 1e-3), reason: 'e nasce em .5');

      final before = scales();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        scales().first,
        greaterThan(before.first),
        reason:
            'os anéis dela crescem para fora (.62 → 1.5, :202); em $tongue '
            'os nossos se fechavam para dentro',
      );

      final now = scales();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(scales(), [
        closeTo(now[0], 2e-3),
        closeTo(now[1], 2e-3),
      ], reason: 'o r2 dela começa 1,5 s depois do r1, meia volta de 3 s');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(scales(), [
        closeTo(now[0], 2e-3),
        closeTo(now[1], 2e-3),
      ], reason: 'o ripple dela dura 3 s (globals.css:381), não 3,2 s');
    }

    await _pumpCircle(tester, VoiceState.listening, still: true);
    expect(
      ripples(),
      isEmpty,
      reason:
          'com menos movimento a animação dela some (globals.css:237) e o '
          '.ring fica em opacidade 0',
    );
  });

  testWidgets('while the room thinks the check circle is her ring with the '
      'areia edge on a 4.5 s breath, not a clay bead', (tester) async {
    await _pumpCircle(tester, VoiceState.thinking);

    _expectHollow(
      tester,
      const Color(0xFFC5C29F),
      'pensando, o .cdot dela fica na borda areia de base (globals.css:376, '
      ':384); o nosso era a conta de barro cheia',
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(_breath(tester).$1, closeTo(.97, 1e-3));
    await tester.pump(const Duration(milliseconds: 2250));
    expect(
      [_breath(tester).$1, _breath(tester).$2],
      [closeTo(1.03, 1e-3), closeTo(1, 1e-3)],
      reason: 'thinkBreath de 4,5 s: o topo vem na metade (globals.css:384)',
    );

    await _pumpCircle(tester, VoiceState.thinking, still: true);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(
      _breath(tester),
      (1.0, 1.0),
      reason: 'com menos movimento a animação dela some (globals.css:237)',
    );
  });

  testWidgets('a check circle that answers no touch still draws the ring of '
      'its voice, never a clay circle', (tester) async {
    for (final (voice, edge) in [
      (VoiceState.done, const Color(0xFFBE4A01)),
      (VoiceState.invite, const Color(0xFFBE4A01)),
      (VoiceState.speaking, const Color(0xFFBE4A01)),
    ]) {
      await _pumpCircle(tester, voice, answersATouch: false);

      _expectHollow(
        tester,
        edge,
        'desabilitado, o .check-circle dela só troca o cursor '
        '(globals.css:385) e segue com o anel do estado; em ${voice.name} o '
        'nosso era o círculo de barro com borda cord',
      );
    }
  });

  testWidgets('a change of voice keeps the check ring and fades only its edge '
      'over a second, never swapping it in one frame', (tester) async {
    Future<void> turn(VoiceState voice) => tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('a mesma sala'),
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: FacilitatorCircle(
              size: _side,
              voice: voice,
              semanticLabel: 'circulo',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    Color edge() => _rings(tester).single.border!.top.color;

    await turn(VoiceState.invite);
    await tester.pump(const Duration(milliseconds: 1100));
    for (final (voice, from, to) in [
      (VoiceState.listening, const Color(0xFFBE4A01), const Color(0xFF89AAA3)),
      (VoiceState.thinking, const Color(0xFF89AAA3), const Color(0xFFC5C29F)),
      (VoiceState.speaking, const Color(0xFFC5C29F), const Color(0xFFBE4A01)),
    ]) {
      await turn(voice);
      expect(
        edge(),
        from,
        reason:
            'a troca de voz dela não troca o .cdot, só faz a borda andar '
            '(transition:border-color 1s, globals.css:377); o nosso trocava o '
            'corpo inteiro num quadro, rumo a ${voice.name}',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(edge(), isNot(anyOf(from, to)), reason: 'no meio do segundo');
      await tester.pump(const Duration(milliseconds: 380));
      expect(edge(), isNot(to), reason: 'ainda antes de 1 s');
      await tester.pump(const Duration(milliseconds: 220));
      expect(edge(), to, reason: 'passado 1 s a borda é a do novo estado');
    }
  });

  testWidgets('on the dark ground the check ring takes her dark fill and dark '
      'azul, and no light azul is left anywhere in the circle', (tester) async {
    const lightAzuis = {0x89AAA3, 0xA6C0BA, 0x5E7A74, 0x3F6862};
    for (final voice in VoiceState.values) {
      for (final tongue in [null, ...Tongue.values]) {
        await _pumpCircle(
          tester,
          voice,
          tongue: tongue,
          notUnderstood: 'não entendi',
          theme: AppTheme.dark,
        );
        await tester.pump(const Duration(milliseconds: 700));

        expect(
          _rings(tester).single.gradient,
          _darkFill,
          reason:
              'no escuro o .cdot dela é rgba(110,106,87,.18) → .05 '
              '(globals.css:30); em ${voice.name} o nosso era outro',
        );
        final painted = [
          for (final paint in _painted(tester)) ...[
            ?paint.color,
            ...?paint.gradient?.colors,
            ...?paint.boxShadow?.map((shadow) => shadow.color),
            if (paint.border case final Border border) border.top.color,
          ],
        ];
        expect(
          painted
              .map((color) => color.toARGB32() & 0xFFFFFF)
              .where(lightAzuis.contains),
          isEmpty,
          reason:
              'o azul dela no escuro é 8FB1A9 (globals.css:20) e ela não tem '
              'conta nem tons de azul; em ${voice.name}/$tongue sobrava o '
              'azul claro do material de conta',
        );
        if (voice == VoiceState.listening) {
          expect(
            painted
                .where((color) => color.a > 0)
                .map((color) => color.toARGB32() & 0xFFFFFF),
            contains(0x8FB1A9),
            reason: 'ouvindo, a borda e os anéis são var(--azul) do escuro',
          );
        }
      }
    }
  });
}
