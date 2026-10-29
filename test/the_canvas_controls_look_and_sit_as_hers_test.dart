import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:internalization_room/features/sala/presentation/widgets/claquete.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';
import 'package:internalization_room/features/sala/presentation/widgets/shema_mark.dart';

import 'every_way_back_is_her_bare_chevron_test.dart' show expectHerChevron;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

const _se = Size(375, 667);

void _on(WidgetTester tester, Size screen, {double bar = 0, double inset = 0}) {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar, bottom: inset)
    ..viewPadding = FakeViewPadding(top: bar, bottom: inset);
  addTearDown(tester.view.reset);
}

void _inTheDark(WidgetTester tester) {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

double _seenOpacity(WidgetTester tester, Finder mark) {
  var seen = 1.0;
  mark.evaluate().first.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Opacity) seen *= widget.opacity;
    if (widget is FadeTransition) seen *= widget.opacity.value;
    return true;
  });
  return seen;
}

void _sits(Rect rect, Size size, {required Offset center, String? reason}) {
  expect(rect.width, closeTo(size.width, 0.01), reason: reason);
  expect(rect.height, closeTo(size.height, 0.01), reason: reason);
  expect(rect.center.dx, closeTo(center.dx, 0.01), reason: reason);
  expect(rect.center.dy, closeTo(center.dy, 0.01), reason: reason);
}

Finder _barsOf(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.rectangle,
  ),
);

Finder _paintedUnder(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate((widget) {
    final decoration = switch (widget) {
      Container(:final decoration?) => decoration,
      DecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    return decoration is BoxDecoration &&
        (decoration.color != null ||
            decoration.gradient != null ||
            decoration.boxShadow != null);
  }),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var beat = 0; beat < 100 && !done(); beat++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _atTheSendOff(WidgetTester tester) async {
  final harness = SalaHarness(lingua: 'en')
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = const Moment(at: MomentAt.ensaioFinal, parts: 3);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  expect(
    container.read(salaSessionProvider).orangeDotLook,
    OrangeDotLook.bright,
  );
}

Rect _inkOf(Element word) {
  final paragraph = _paragraphUnder(word);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  var ink = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    ink = ink.expandToInclude(box.toRect());
  }
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), ink);
}

RenderParagraph _paragraphUnder(Element word) {
  RenderParagraph? found;
  void look(Element element) {
    if (found != null) return;
    final render = element.renderObject;
    if (render is RenderParagraph) {
      found = render;
      return;
    }
    element.visitChildren(look);
  }

  look(word);
  return found!;
}

Finder _dotIn(String label) => find.descendant(
  of: byLabel(label),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

void main() {
  for (final (look, telha) in [
    ('light', const Color(0xFFBE4A01)),
    ('dark', const Color(0xFFD6612A)),
  ]) {
    testWidgets(
      'in the $look look the orange dot is her 12 px at 5% and 6%, not 15 px '
      'under the corner',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Record your rehearsal';

        expect(byLabel(label), findsOneWidget);
        final dot = _dotIn(label);
        expect(dot, findsOneWidget);
        expect(
          (tester.widget<DecoratedBox>(dot).decoration as BoxDecoration).color,
          telha,
        );
        _sits(
          tester.getRect(dot),
          const Size(13 / 24 * 22, 13 / 24 * 22),
          center: const Offset(375 - 22.5 - 17, 20 + 33.35 + 17),
          reason: 'o ponto tinha 15 px, a 14 e 118 do canto',
        );
        expect(_seenOpacity(tester, dot), closeTo(0.22, 0.001));
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(375 - 22.5 - 17, 20 + 33.35 + 17),
          reason: 'o alvo do ponto era de 34 px',
        );
      },
    );
  }

  for (final (look, red) in [
    ('light', const Color(0xFFC8321E)),
    ('dark', const Color(0xFFE9503A)),
  ]) {
    testWidgets(
      'in the $look look the red microphone draws her filled 26 px microphone, '
      'not an outline',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'scene rehearsal';
        const unit = 26 / 24;
        final stroke = Float32List.fromList([2.2 * unit]).single;

        expect(byLabel(label), findsOneWidget);
        expect(
          find.descendant(of: byLabel(label), matching: find.byType(Icon)),
          findsNothing,
          reason: 'o microfone era o contorno do lucide, sem a cápsula cheia',
        );
        final glyph = find.descendant(
          of: byLabel(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        );
        expect(tester.getSize(glyph), const Size(26, 26));
        expect(
          glyph,
          paints
            ..rrect(
              rrect: RRect.fromLTRBR(
                9 * unit,
                2.5 * unit,
                15 * unit,
                13.5 * unit,
                const Radius.circular(3 * unit),
              ),
              color: red,
              style: PaintingStyle.fill,
            )
            ..arc(
              rect: Rect.fromCircle(
                center: const Offset(12 * unit, 11 * unit),
                radius: 6 * unit,
              ),
              color: red,
              strokeWidth: stroke,
              strokeCap: StrokeCap.round,
            )
            ..line(
              p1: const Offset(12 * unit, 17 * unit),
              p2: const Offset(12 * unit, 21 * unit),
              color: red,
              strokeWidth: stroke,
            )
            ..line(
              p1: const Offset(9 * unit, 21 * unit),
              p2: const Offset(15 * unit, 21 * unit),
              color: red,
              strokeWidth: stroke,
            ),
        );
        expect(
          glyph,
          paints..something((method, arguments) {
            if (method != #drawArc) return false;
            final sweep = arguments[2] as double;
            final middle = (arguments[1] as double) + sweep / 2;
            return (sweep.abs() - pi).abs() < 1e-9 &&
                (sin(middle) - 1).abs() < 1e-9;
          }),
          reason: 'o berço do microfone dela é o arco de baixo',
        );
      },
    );
  }

  for (final (screen, bar, center) in [
    (_se, 20.0, const Offset(375 - 22.5 - 24, 20 + 33.35 + 40 + 24)),
    (
      const Size(820, 1180),
      24.0,
      const Offset(820 - 49.2 - 50 - 24, 24 + 59 - 6 + 24),
    ),
  ]) {
    testWidgets(
      'on a ${screen.width.toInt()} px screen the red microphone sits where '
      'hers does',
      (tester) async {
        _on(tester, screen, bar: bar);
        await atRestAfterATurn(tester, const []);

        _sits(
          tester.getRect(byLabel('scene rehearsal')),
          const Size(48, 48),
          center: center,
          reason: 'o microfone contava a partir do ponto velho, a 118',
        );
      },
    );
  }

  for (final (look, verdeClaro) in [
    ('light', const Color(0xFF777D45)),
    ('dark', const Color(0xFFAAB07E)),
  ]) {
    for (final (where, opens, seen) in [
      ('the Choice', 'Choose another passage', 0.5),
      ('the scene rehearsal', 'scene rehearsal', 0.6),
    ]) {
      testWidgets(
        'in the $look look the way back on $where is her bare chevron at 5% '
        'and 6%, at $seen',
        (tester) async {
          _on(tester, _se, bar: 20);
          if (look == 'dark') _inTheDark(tester);
          final (_, container) = await atRestAfterATurn(tester, const []);
          const label = 'Back to the current passage';

          await tester.tap(byLabel(opens), warnIfMissed: false);
          await _pumpUntil(tester, () => byLabel(label).evaluate().isNotEmpty);
          await tester.pump(const Duration(milliseconds: 1500));

          expect(container.read(salaSessionProvider).theWayBackIsLive, isTrue);
          expect(byLabel(label), findsOneWidget);
          expect(
            _paintedUnder(label),
            findsNothing,
            reason: 'a volta era um disco de 44 px com sombra',
          );
          final chevron = find.descendant(
            of: byLabel(label),
            matching: find.byType(CustomPaint),
          );
          expectHerChevron(tester, chevron, verdeClaro);
          expect(
            _seenOpacity(tester, chevron),
            closeTo(seen, 0.001),
            reason: 'a volta dela é discreta, não desenhada por inteiro',
          );
          _sits(
            tester.getRect(byLabel(label)),
            const Size(44, 44),
            center: const Offset(22.5 + 20, 20 + 33.35 + 20),
            reason: 'a volta flutuava a 14 e 118, sobre o conteúdo',
          );

          await tester.tap(byLabel(label));
          await tester.pump(const Duration(seconds: 3));
          expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
        },
      );
    }
  }

  testWidgets('a lit orange dot grows by her quarter, to .85', (tester) async {
    _on(tester, _se, bar: 20);
    await _atTheSendOff(tester);
    final dot = _dotIn('Record your rehearsal');

    expect(_seenOpacity(tester, dot), closeTo(0.85, 0.001));
    final rect = tester.getRect(dot);
    expect(
      rect.width,
      closeTo(13 / 24 * 22 * 1.25, 0.01),
      reason: 'o ponto aceso ficava do tamanho do apagado',
    );
    expect(rect.center.dx, closeTo(375 - 22.5 - 17, 0.01));
    expect(rect.center.dy, closeTo(20 + 33.35 + 17, 0.01));
  });

  for (final (look, verde) in [
    ('light', const Color(0xFF3F3E20)),
    ('dark', const Color(0xFFECEADC)),
  ]) {
    testWidgets(
      'in the $look look hearing again is her bare arrow at 8% and 16%, '
      'at .42, not a disc',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Hear that again';

        expect(byLabel(label), findsOneWidget);
        expect(
          _paintedUnder(label),
          findsNothing,
          reason: 'o ouvir de novo era um disco com sombra',
        );
        final arrow = find.descendant(
          of: byLabel(label),
          matching: find.byType(Icon),
        );
        final icon = tester.widget<Icon>(arrow);
        expect(icon.icon, LucideIcons.rotateCcw);
        expect(icon.size, 22);
        expect(icon.color, verde, reason: 'a seta dela é --verde');
        expect(
          _seenOpacity(tester, arrow),
          closeTo(0.42, 0.001),
          reason: 'a seta dela fica a .42 quando aparece',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(375 - 30 - 22, 667 - 106.72 - 22),
          reason: 'o ouvir de novo ficava a 14 e 18 do canto',
        );
      },
    );
  }

  for (final (look, verde) in [
    ('light', const Color(0xFF3F3E20)),
    ('dark', const Color(0xFFECEADC)),
  ]) {
    testWidgets(
      'in the $look look the hand is her bare glyph at 8% and 16%, at .35, '
      'not a card',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Leave a question for your facilitator';

        expect(byLabel(label), findsOneWidget);
        expect(
          _paintedUnder(label),
          findsNothing,
          reason: 'a mão era um cartão de 60 px com borda',
        );
        final glyph = find.descendant(
          of: byLabel(label),
          matching: find.byType(Icon),
        );
        final icon = tester.widget<Icon>(glyph);
        expect(icon.icon, LucideIcons.hand);
        expect(icon.size, 26);
        expect(icon.color, verde, reason: 'a mão dela é --verde');
        expect(
          _seenOpacity(tester, glyph),
          closeTo(0.35, 0.001),
          reason: 'a mão dela fica a .35 na vez da equipe',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(30 + 20, 667 - 106.72 - 20),
          reason: 'a mão ficava a 14 e 18 do canto',
        );
      },
    );
  }

  testWidgets(
    'in note mode the hand stands at her .8, green, with no blue glow',
    (tester) async {
      _on(tester, _se, bar: 20);
      final (_, container) = await atRestAfterATurn(tester, const []);
      const label = 'Leave a question for your facilitator';

      container.read(salaSessionProvider.notifier).handTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).noteMode,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));

      expect(container.read(salaSessionProvider).noteMode, isTrue);
      final glyph = find.descendant(
        of: byLabel(label),
        matching: find.byType(Icon),
      );
      expect(
        _paintedUnder(label),
        findsNothing,
        reason: 'a mão acendia um halo azul no modo de recado',
      );
      expect(tester.widget<Icon>(glyph).color, const Color(0xFF3F3E20));
      expect(
        _seenOpacity(tester, glyph),
        closeTo(0.8, 0.001),
        reason: 'no recado a mão dela sobe para .8',
      );
    },
  );

  testWidgets(
    'hearing again fades in over her 1.2 s once the line has played',
    (tester) async {
      _on(tester, _se, bar: 20);
      final (harness, container) = await atRestAfterATurn(tester, const []);
      const label = 'Hear that again';
      final arrow = find.descendant(
        of: byLabel(label),
        matching: find.byType(Icon),
      );

      harness.voice.holdNextLine();
      container.read(salaSessionProvider.notifier).hearAgain();
      await _pumpUntil(tester, () => byLabel(label).evaluate().isEmpty);
      expect(byLabel(label), findsNothing);
      harness.voice.finishHeldLine();
      await _pumpUntil(tester, () => byLabel(label).evaluate().isNotEmpty);
      expect(byLabel(label), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        _seenOpacity(tester, arrow),
        closeTo(0.21, 0.02),
        reason: 'a seta surgia em 700 ms subindo, não no 1,2 s dela',
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(_seenOpacity(tester, arrow), closeTo(0.42, 0.001));
    },
  );

  for (final (look, verdeClaro) in [
    ('light', const Color(0xFF777D45)),
    ('dark', const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the $look look the way out is her three faint bars at 5% and 6%, '
      'not a disc',
      (tester) async {
        _on(tester, _se, bar: 20);
        if (look == 'dark') _inTheDark(tester);
        await atRestAfterATurn(tester, const []);
        const label = 'Choose another passage';

        expect(byLabel(label), findsOneWidget);
        final bars = _barsOf(label);
        expect(bars, findsNWidgets(3), reason: 'o canto era um disco opaco');
        for (var i = 0; i < 3; i++) {
          final rect = tester.getRect(bars.at(i));
          expect(rect.width, closeTo(24, 0.01));
          expect(rect.height, closeTo(2, 0.01));
          expect(rect.left, closeTo(22.5 + 3, 0.01));
          expect(rect.top, closeTo(20 + 33.35 + 3 + 7.0 * i, 0.01));
        }
        for (final bar in tester.widgetList<Container>(bars)) {
          final body = bar.decoration! as BoxDecoration;
          expect(body.color, verdeClaro);
          expect(body.borderRadius, BorderRadius.circular(2));
          expect(body.boxShadow, isNull);
        }
        expect(
          _seenOpacity(tester, bars.first),
          closeTo(0.22, 0.001),
          reason: 'o canto dela fica a .22 em repouso',
        );
        _sits(
          tester.getRect(byLabel(label)),
          const Size(44, 44),
          center: const Offset(22.5 + 15, 20 + 33.35 + 11),
          reason: 'o alvo do toque ficou menor que 44 ou fora do lugar dela',
        );
      },
    );
  }

  for (final (name, screen, inset) in [
    ('an SE', _se, 0.0),
    ('an iPad', const Size(820, 1180), 20.0),
  ]) {
    testWidgets(
      'on $name the hand and the replay each stand their own box on her 8% '
      'and 16%, the finger\'s square centred on it',
      (tester) async {
        _on(tester, screen, bar: 20, inset: inset);
        await atRestAfterATurn(tester, const []);
        final side = screen.width * 0.08;
        final floor = screen.height - inset - screen.height * 0.16;

        final handTarget = tester.getRect(
          byLabel('Leave a question for your facilitator'),
        );
        final handBox = tester.getRect(
          find.descendant(
            of: byLabel('Leave a question for your facilitator'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == 40 &&
                  widget.height == 40,
            ),
          ),
        );
        final replayBox = tester.getRect(byLabel('Hear that again'));

        expect(
          handBox.left,
          closeTo(side, 0.01),
          reason: 'a .hand dela é 40 px a 8%',
        );
        expect(handBox.bottom, closeTo(floor, 0.01));
        expect(
          replayBox.right,
          closeTo(screen.width - side, 0.01),
          reason: 'a .replay dela é 44 px a 8%',
        );
        expect(replayBox.bottom, closeTo(floor, 0.01));
        expect(replayBox.size, const Size(44, 44));
        expect(handTarget.width, greaterThanOrEqualTo(44));
        expect(handTarget.height, greaterThanOrEqualTo(44));
        expect(handTarget.center.dx, closeTo(handBox.center.dx, 0.01));
        expect(handTarget.center.dy, closeTo(handBox.center.dy, 0.01));
      },
    );
  }

  testWidgets(
    'under a status bar the moment label still sits below the red microphone '
    'on a phone, both counted from the bar',
    (tester) async {
      _on(tester, const Size(390, 844), bar: 59);
      await atRestAfterATurn(tester, const []);

      final label = tester.getRect(find.byType(MomentLabel));
      expect(
        label.top,
        closeTo(59 + 136.2, 0.01),
        reason: 'a etiqueta contava do topo da tela e o microfone da barra',
      );
      expect(
        label.top,
        greaterThanOrEqualTo(tester.getRect(byLabel('scene rehearsal')).bottom),
        reason: 'no celular a etiqueta dela fica sempre abaixo do microfone',
      );
    },
  );

  for (final (name, screen, bar, inset) in [
    ('an SE', _se, 20.0, 0.0),
    ('an iPad', const Size(820, 1180), 24.0, 20.0),
  ]) {
    testWidgets('on $name nothing on her canvas sits on anything else', (
      tester,
    ) async {
      _on(tester, screen, bar: bar, inset: inset);
      await atRestAfterATurn(tester, [
        aKept('S1', 2),
        aKept('S2', 4),
        aKept('S3', 6),
      ]);

      final pieces = <String, Rect>{
        for (final label in [
          'Choose another passage',
          'Record your rehearsal',
          'scene rehearsal',
          'Leave a question for your facilitator',
          'Hear that again',
          'Hear how you told part 1',
          'Hear how you told part 2',
          'Hear how you told part 3',
        ])
          label: tester.getRect(byLabel(label)),
        'the circle': tester.getRect(find.byType(FacilitatorCircle)),
        'the moment': tester.getRect(find.byType(MomentLabel)),
        'the claquete': tester.getRect(find.byType(Claquete)),
        'the mark': tester.getRect(
          find.descendant(
            of: find.byType(ClaqueteLayer),
            matching: find.byType(ShemaMark),
          ),
        ),
      };
      final names = pieces.keys.toList();
      for (var i = 0; i < names.length; i++) {
        expect(
          screen.contains(pieces[names[i]]!.topLeft) &&
              screen.contains(
                pieces[names[i]]!.bottomRight - const Offset(1, 1),
              ),
          isTrue,
          reason: '${names[i]} saía da tela',
        );
        for (var j = i + 1; j < names.length; j++) {
          expect(
            pieces[names[i]]!.overlaps(pieces[names[j]]!),
            isFalse,
            reason: '${names[i]} encostava em ${names[j]}',
          );
        }
      }
    });
  }

  for (final (name, screen, bar, inset) in [
    ('an SE', _se, 20.0, 0.0),
    ('an iPad', const Size(820, 1180), 24.0, 20.0),
  ]) {
    for (final (where, opens) in [
      ('the Choice', 'Choose another passage'),
      ('the scene rehearsal', 'scene rehearsal'),
    ]) {
      testWidgets('on $name the way back on $where sits on no written word', (
        tester,
      ) async {
        _on(tester, screen, bar: bar, inset: inset);
        await atRestAfterATurn(tester, const []);
        const label = 'Back to the current passage';

        await tester.tap(byLabel(opens), warnIfMissed: false);
        await _pumpUntil(tester, () => byLabel(label).evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 1500));

        final back = tester.getRect(byLabel(label));
        final words = find.byType(Text).hitTestable();
        expect(words, findsWidgets);
        for (final word in words.evaluate()) {
          final text = (word.widget as Text).data ?? '';
          expect(
            back.overlaps(_inkOf(word)),
            isFalse,
            reason: 'a volta encostava em «$text»',
          );
        }

        await tester.tap(byLabel(label));
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
