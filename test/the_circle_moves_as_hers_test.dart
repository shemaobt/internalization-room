import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

const _side = 217.5;

Widget _circle(
  VoiceState voice, {
  required bool canvas,
  bool peerCue = false,
  bool noteMode = false,
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
          noteMode: noteMode,
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

final _rippleRings = find.descendant(
  of: find.byType(Ripple),
  matching: find.byType(Container),
);

int _paintedRipples(WidgetTester tester) => _rippleRings
    .evaluate()
    .where(
      (ring) =>
          ((ring.widget as Container).decoration! as BoxDecoration)
                  .border!
                  .top
                  .color
                  .a *
              _seen(tester, find.byWidget(ring.widget)) >
          0,
    )
    .length;

List<double> _rippleScales(WidgetTester tester) => [
  for (final ring in _rippleRings.evaluate())
    _scaleAbove(tester, find.byWidget(ring.widget)),
];

final _glyph = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CircleGlyphPainter,
);

void main() {
  testWidgets('the mark inside her canvas circle breathes with the ring, '
      'at invite, at done, while the team talks and with a note at done', (
    tester,
  ) async {
    for (final (name, voice, peerCue, noteMode) in [
      ('invite', VoiceState.invite, false, false),
      ('done', VoiceState.done, false, false),
      ('team talk', VoiceState.invite, true, false),
      ('note at done', VoiceState.done, false, true),
    ]) {
      await tester.pumpWidget(
        _circle(
          voice,
          canvas: true,
          peerCue: peerCue,
          noteMode: noteMode,
          key: ValueKey('glifo $name'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 3250));
      expect(
        [_scaleAbove(tester, _glyph), _scaleAbove(tester, _ring.first)],
        [closeTo(1.035, 1e-6), closeTo(1.035, 1e-6)],
        reason:
            'o glifo dela mora dentro do .target (page.tsx:1026-1036) e '
            'respira com ele até 1.035 (globals.css:192,195,230); em $name '
            'o nosso alto-falante ficava parado enquanto o anel respirava',
      );
    }
  });

  testWidgets('a note left at invite holds the hand and the ring still', (
    tester,
  ) async {
    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, noteMode: true),
    );
    await tester.pump(const Duration(milliseconds: 3250));
    expect(
      [_scaleAbove(tester, _glyph), _scaleAbove(tester, _ring.first)],
      [closeTo(1, 1e-6), closeTo(1, 1e-6)],
      reason:
          'com um recado no convite o .target dela tem animation:none '
          '(globals.css:168): a mão e o anel ficam parados',
    );
  });

  testWidgets('from invite to done the circle keeps the breath it was on, '
      'it does not start a new one from rest', (tester) async {
    const same = ValueKey('o mesmo canvas do convite ao fim');
    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 3250));
    await tester.pumpWidget(_circle(VoiceState.done, canvas: true, key: same));
    await tester.pump(const Duration(milliseconds: 17));
    expect(
      [
        for (final ring in _ring.evaluate())
          _scaleAbove(tester, find.byWidget(ring.widget)),
        _scaleAbove(tester, _glyph),
      ],
      everyElement(closeTo(1.035, 1e-3)),
      reason:
          'o done dela usa a mesma animação invite (globals.css:192,230) e o '
          'navegador segue no mesmo ponto; o nosso anel do fim renascia em 1 '
          'enquanto o do convite ainda respirava ao lado',
    );
  });

  testWidgets('leaving the breath the fading invite ring and the mark stand '
      'at rest together, from the switch', (tester) async {
    const same = ValueKey('o mesmo canvas do convite à escuta');
    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 3250));
    await tester.pumpWidget(
      _circle(VoiceState.listening, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 17));
    expect(
      [_scaleAbove(tester, _edged(_telha)), _scaleAbove(tester, _glyph)],
      [closeTo(1, 1e-6), closeTo(1, 1e-6)],
      reason:
          'fora do invite e do done o .target dela não tem animação e o '
          'transform volta a none sem transição; o nosso anel do convite '
          'seguia respirando enquanto se apagava, longe do glifo',
    );
  });

  testWidgets('a tablet that asks for less motion sees no listening rings and '
      'no breath on the mark or the ring', (tester) async {
    await tester.pumpWidget(
      _circle(VoiceState.listening, canvas: true, still: true),
    );
    await tester.pump(const Duration(milliseconds: 2500));
    expect(
      _rippleRings,
      findsNothing,
      reason:
          'com menos movimento os .ripple dela ficam em 0 (globals.css:237)',
    );

    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, still: true),
    );
    await tester.pump(const Duration(milliseconds: 3250));
    expect(
      [_scaleAbove(tester, _glyph), _scaleAbove(tester, _ring.first)],
      [closeTo(1, 1e-6), closeTo(1, 1e-6)],
      reason: 'e o convite dela fica parado, glifo e anel',
    );
  });

  testWidgets('her canvas rings start one at a time, 1.07 s apart, and then '
      'keep the rhythm they had, also while a note is left', (tester) async {
    for (final noteMode in [false, true]) {
      final same = ValueKey('o mesmo canvas ouvindo $noteMode');
      await tester.pumpWidget(
        _circle(VoiceState.invite, canvas: true, noteMode: noteMode, key: same),
      );
      await tester.pumpWidget(
        _circle(
          VoiceState.listening,
          canvas: true,
          noteMode: noteMode,
          key: same,
        ),
      );

      for (final (step, rings) in [(500, 1), (1000, 2), (1000, 3)]) {
        await tester.pump(Duration(milliseconds: step));
        expect(
          _paintedRipples(tester),
          rings,
          reason:
              'os .ripple r2 e r3 dela esperam 1,07 s e 2,14 s em opacidade 0 '
              '(globals.css:119,200-201,172-173); os nossos três já nasciam '
              'juntos, dois deles no meio do caminho',
        );
      }

      for (final step in [700, 1070, 1070]) {
        await tester.pump(Duration(milliseconds: step));
        expect(
          _rippleScales(tester),
          contains(closeTo(.62, 1e-6)),
          reason:
              'depois da espera cada anel renasce em .62 (globals.css:202) a '
              'cada 3,2 s: r1 aos 3,2 s, r2 aos 4,27 s, r3 aos 5,34 s',
        );
      }
    }
  });

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

  testWidgets('a tablet that asks for less motion sees a thinking check '
      'circle hold still, whole and lit', (tester) async {
    await tester.pumpWidget(
      _circle(VoiceState.thinking, canvas: false, still: true),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        [_scaleAbove(tester, _ring.first), _seen(tester, _ring.first)],
        [closeTo(1, 1e-6), closeTo(1, 1e-6)],
        reason:
            'sem movimento todo animation dela vira none e só o .target do '
            'canvas guarda o pulso de luz (globals.css:238,241); o '
            'check-circle fica parado no seu tamanho e cor',
      );
    }
  });

  testWidgets('her thinking arcs come and go at once while the ring under '
      'them fades', (tester) async {
    final arcs = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ArcPainter,
    );
    double fades(Element arc) {
      var seen = 1.0;
      arc.visitAncestorElements((above) {
        final widget = above.widget;
        if (widget is FadeTransition) seen *= widget.opacity.value;
        return true;
      });
      return seen;
    }

    const same = ValueKey('o mesmo canvas pensando');

    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, key: same),
    );
    await tester.pumpWidget(
      _circle(VoiceState.thinking, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      [for (final arc in arcs.evaluate()) fades(arc)],
      [1.0, 1.0],
      reason:
          'os .ripple r1 e r2 dela não têm transition: no pensar ficam '
          'inteiros de uma vez (globals.css:119,210-213); só o anel troca '
          'em 1,4 s',
    );
    expect(_seen(tester, _edged(const Color(0xFFC5C29F))), lessThan(0.9));

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpWidget(
      _circle(VoiceState.invite, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      arcs,
      findsNothing,
      reason: 'e somem no mesmo quadro em que o pensar acaba',
    );
    expect(_edged(const Color(0xFFC5C29F)), findsOneWidget);
  });

  testWidgets('arcs that follow her speaking breathe with the ring from its '
      'first breath, not from where the speaking glow had got to', (
    tester,
  ) async {
    final arc = find
        .byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is ArcPainter,
        )
        .first;
    final ring = _edged(const Color(0xFFC5C29F));
    double veil(Finder what) => tester
        .widgetList<Opacity>(
          find.ancestor(of: what, matching: find.byType(Opacity)),
        )
        .fold(1.0, (seen, veil) => seen * veil.opacity);
    const same = ValueKey('o mesmo canvas falando e pensando');

    await tester.pumpWidget(
      _circle(VoiceState.speaking, canvas: true, key: same),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpWidget(
      _circle(VoiceState.thinking, canvas: true, key: same),
    );

    expect(
      [veil(arc), veil(ring)],
      [closeTo(0.82, 1e-6), closeTo(0.82, 1e-6)],
      reason:
          'o thinkBreath dela abre em opacidade .82 para o .target inteiro, '
          'arcos e anel juntos (globals.css:208-209); os arcos herdavam a '
          'fase do brilho da fala',
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(veil(arc), closeTo(veil(ring), 1e-6));
    }
  });
}
