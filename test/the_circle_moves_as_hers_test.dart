import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

const _side = 217.5;

Widget _circle(
  VoiceState voice, {
  required bool canvas,
  bool peerCue = false,
  bool still = false,
  Halt halt = const NoHalt(),
  Key? key,
}) => MaterialApp(
  key: key ?? ValueKey('$voice-$canvas-$peerCue-$still'),
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          size: _side,
          voice: voice,
          peerCue: peerCue,
          canvas: canvas,
          halt: halt,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

final _ring = find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
      (widget.decoration! as BoxDecoration).gradient != null &&
      ((widget.decoration! as BoxDecoration).border != null ||
          (widget.decoration! as BoxDecoration).boxShadow != null),
);

Finder _edged(Color edge) => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).border?.top.color == edge,
);

double _seen(WidgetTester tester, Finder what) =>
    tester
        .widgetList<FadeTransition>(
          find.ancestor(of: what, matching: find.byType(FadeTransition)),
        )
        .fold(1.0, (seen, fade) => seen * fade.opacity.value) *
    tester
        .widgetList<Opacity>(
          find.ancestor(of: what, matching: find.byType(Opacity)),
        )
        .fold(1.0, (seen, veil) => seen * veil.opacity);

const _telha = Color(0xFFBE4A01);
const _azul = Color(0xFF89AAA3);

double _scaleAbove(WidgetTester tester, Finder what) => tester
    .widgetList<Transform>(
      find.ancestor(of: what, matching: find.byType(Transform)),
    )
    .fold(1.0, (scale, move) => scale * move.transform.storage[0]);

void main() {
  testWidgets('her canvas circle rests on a 6.5 s breath that reaches 1.035, '
      'at invite, at done and while the team talks', (tester) async {
    for (final (name, voice, peerCue) in [
      ('invite', VoiceState.invite, false),
      ('done', VoiceState.done, false),
      ('team talk', VoiceState.invite, true),
    ]) {
      await tester.pumpWidget(_circle(voice, canvas: true, peerCue: peerCue));
      expect(_scaleAbove(tester, _ring.first), closeTo(1, 1e-6));

      await tester.pump(const Duration(milliseconds: 3250));
      expect(
        _scaleAbove(tester, _ring.first),
        closeTo(1.035, 1e-6),
        reason:
            '$name respirava em 4,6 s até 1.045; o invite dela é 6,5 s até '
            '1.035 (globals.css:192,195,230)',
      );

      await tester.pump(const Duration(milliseconds: 3250));
      expect(
        _scaleAbove(tester, _ring.first),
        closeTo(1, 1e-6),
        reason: '$name volta ao repouso em 6,5 s, não antes',
      );
    }
  });

  testWidgets('a check circle waiting for a tap breathes on her 6 s up to '
      '1.035, not on 4.6 s up to 1.045', (tester) async {
    for (final voice in [VoiceState.invite, VoiceState.done]) {
      await tester.pumpWidget(_circle(voice, canvas: false));
      expect(_scaleAbove(tester, _ring.first), closeTo(1, 1e-6));

      await tester.pump(const Duration(milliseconds: 3000));
      expect(
        _scaleAbove(tester, _ring.first),
        closeTo(1.035, 1e-6),
        reason:
            'o check-circle dela em idle usa o invite em 6 s '
            '(globals.css:379); o nosso ia a 1.045 em 4,6 s',
      );

      await tester.pump(const Duration(milliseconds: 3000));
      expect(_scaleAbove(tester, _ring.first), closeTo(1, 1e-6));
    }
  });

  testWidgets('on her canvas the invite ring fades into the listening ring '
      'over 1.4 s, even for a tablet that asks for less motion', (
    tester,
  ) async {
    for (final still in [false, true]) {
      final same = ValueKey('o mesmo canvas $still');
      await tester.pumpWidget(
        _circle(VoiceState.invite, canvas: true, still: still, key: same),
      );
      await tester.pumpWidget(
        _circle(VoiceState.listening, canvas: true, still: still, key: same),
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        _edged(_telha),
        findsOneWidget,
        reason: 'na metade da troca o anel do convite ainda se apaga',
      );
      expect(
        [_seen(tester, _edged(_telha)), _seen(tester, _edged(_azul))],
        [closeTo(0.198, 0.01), closeTo(0.802, 0.01)],
        reason:
            'o dela troca borda e fundo em 1,4 s com ease '
            '(globals.css:112,116), que passa de 80% na metade; o nosso '
            'trocava o anel inteiro de um quadro para o outro',
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        [_seen(tester, _edged(_telha)), _seen(tester, _edged(_azul))],
        [closeTo(0, 1e-6), closeTo(1, 1e-6)],
        reason: 'em 1,4 s a troca dela está completa',
      );
    }
  });

  testWidgets('when she starts to speak her canvas circle draws back to .9 '
      'over 1.4 s, not in one frame', (tester) async {
    final speakingEdge = _edged(const Color.fromRGBO(199, 194, 159, .5));
    for (final still in [false, true]) {
      final same = ValueKey('o mesmo canvas falando $still');
      await tester.pumpWidget(
        _circle(VoiceState.invite, canvas: true, still: still, key: same),
      );
      await tester.pumpWidget(
        _circle(VoiceState.speaking, canvas: true, still: still, key: same),
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        _scaleAbove(tester, speakingEdge),
        closeTo(0.920, 0.002),
        reason:
            'o transform dela anda em 1,4 s com ease (globals.css:112,220): '
            'na metade já percorreu 80% do caminho até .9; o nosso pulava '
            'para .9 no mesmo quadro',
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(_scaleAbove(tester, speakingEdge), closeTo(0.9, 1e-6));
    }
  });

  testWidgets('when the person sign comes up her canvas circle fades out over '
      '1.4 s, not over half a second', (tester) async {
    const same = ValueKey('o mesmo canvas parado');
    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, still: true, key: same),
    );
    await tester.pumpWidget(
      _circle(
        VoiceState.invite,
        canvas: true,
        still: true,
        halt: const Blocking(),
        key: same,
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      _seen(tester, _ring.first),
      closeTo(0.198, 0.01),
      reason:
          'a opacidade do .target dela anda em 1,4 s com ease '
          '(globals.css:112,233); o nosso sumia em meio segundo',
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(_seen(tester, _ring.first), closeTo(0, 1e-6));
  });

  testWidgets('while the voice thinks her terracotta glow lies under the '
      'canvas ring and reaches 6% past it', (tester) async {
    final glow = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).gradient ==
              const RadialGradient(
                radius: 0.7071,
                colors: [
                  Color.fromRGBO(190, 74, 1, .16),
                  Color.fromRGBO(190, 74, 1, 0),
                ],
                stops: [0, .62],
              ),
    );
    final ring = _edged(const Color(0xFFC5C29F));
    await tester.pumpWidget(_circle(VoiceState.thinking, canvas: true));

    expect(
      glow,
      findsOneWidget,
      reason:
          'o .glow dela no pensar é radial-gradient(circle, '
          'rgba(190,74,1,.16), transparent 62%) (globals.css:214)',
    );
    expect(
      tester.getSize(glow),
      const Size.square(_side * 1.12),
      reason: 'inset:-6% (globals.css:117); o nosso tinha o tamanho do anel',
    );
    final drawn = find
        .byWidgetPredicate((widget) => widget is Container)
        .evaluate()
        .map((element) => element.widget)
        .toList();
    expect(
      drawn.indexOf(tester.widget(glow)),
      lessThan(drawn.indexOf(tester.widget(ring))),
      reason:
          'o span .glow vem antes do .core (page.tsx:1030-1031) e o anel '
          'translúcido deixa o brilho aparecer; o nosso pintava por cima',
    );

    double glowing() => tester
        .widget<Opacity>(
          find.ancestor(of: glow, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(glowing(), closeTo(0.45, 1e-6));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(
      glowing(),
      closeTo(1, 1e-6),
      reason: 'e continua a acender de .45 a 1 em 2,4 s (globals.css:216)',
    );
  });

  testWidgets('a check circle that thinks breathes her thinkBreath on 4.5 s '
      'and lights no glow', (tester) async {
    await tester.pumpWidget(_circle(VoiceState.thinking, canvas: false));

    final painted = find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byWidgetPredicate(
        (widget) =>
            (widget is CustomPaint && widget.painter != null) ||
            (widget is Container &&
                (widget.decoration as BoxDecoration?)?.gradient != null),
      ),
    );
    expect(
      painted,
      findsOneWidget,
      reason:
          'o check-circle dela não tem span .glow (Drafting.tsx:2406); '
          'só o disco de barro é pintado',
    );

    List<double> drawn() => [
      _scaleAbove(tester, _ring.first),
      _seen(tester, _ring.first),
    ];
    for (final (at, scale, opacity) in [
      (0, .97, .82),
      (2250, 1.03, 1.0),
      (2250, .97, .82),
    ]) {
      await tester.pump(Duration(milliseconds: at));
      expect(
        drawn(),
        [closeTo(scale, 1e-6), closeTo(opacity, 1e-6)],
        reason:
            'o check-circle dela pensa com thinkBreath em 4,5 s '
            '(globals.css:384); o nosso usava os 2,4 s do canvas',
      );
    }
  });
}
