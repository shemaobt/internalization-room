import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  ThemeData? theme,
  bool canvas = true,
  bool noteMode = false,
  bool peerCue = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('$voice-$canvas-$noteMode-$peerCue-${theme?.brightness}'),
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: 200,
            voice: voice,
            canvas: canvas,
            noteMode: noteMode,
            peerCue: peerCue,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1200));
}

final _glyph = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CircleGlyphPainter,
);

Finder paintedGlyph(CircleGlyph glyph) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is CircleGlyphPainter &&
      (widget.painter! as CircleGlyphPainter).glyph == glyph,
);

CircleGlyphPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_glyph).painter! as CircleGlyphPainter;

double _veil(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: _glyph, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  testWidgets(
    'her loudspeaker sits in the canvas circle in voice time, in telha at '
    'sixty percent, not a lucide icon at thirty',
    (tester) async {
      for (final voice in const [
        VoiceState.invite,
        VoiceState.listening,
        VoiceState.speaking,
        VoiceState.done,
      ]) {
        await _pumpCircle(tester, voice);
        expect(
          _painter(tester).glyph,
          CircleGlyph.sound,
          reason:
              '${voice.name}: o círculo dela desenha o alto-falante dela; o '
              'nosso desenhava o volume2 do Lucide',
        );
      }

      for (final (theme, telha) in [
        (AppTheme.light, const Color(0xFFBE4A01)),
        (AppTheme.dark, const Color(0xFFD6612A)),
      ]) {
        await _pumpCircle(tester, VoiceState.invite, theme: theme);
        expect(
          tester.getSize(_glyph),
          const Size(120, 120),
          reason:
              'o ícone dela ocupa 60% do círculo (globals.css:121); o nosso '
              'ocupava 30%',
        );
        expect(
          _veil(tester),
          0.92,
          reason: 'o glifo aceso dela tem opacidade .92 (globals.css:125)',
        );
        expect(
          _glyph,
          paints
            ..path(
              style: PaintingStyle.fill,
              color: telha,
              includes: const [
                Offset(-40, 0),
                Offset(-55, -12),
                Offset(-20, 25),
              ],
              excludes: const [Offset(-58, 0), Offset(-30, -28), Offset(0, 0)],
            )
            ..path(
              style: PaintingStyle.stroke,
              strokeWidth: 5.5,
              color: telha,
              includes: const [Offset(0, 0), Offset(15, 0), Offset(35, 0)],
              excludes: const [Offset(4, 0), Offset(20, 30), Offset(45, 0)],
            ),
          reason:
              '${theme.brightness.name}: o corpo do alto-falante dela é '
              '«M -56 -13 H -38 L -18 -30 V 30 L -38 13 H -56 Z» cheio, e as '
              'três ondas são arcos de raio 20, 34 e 48 traçados a 5.5 '
              '(page.tsx:60-65), em telha',
        );
        expect(
          _glyph,
          paints..something(
            (method, arguments) =>
                method == #drawPath &&
                (arguments[1] as Paint).style == PaintingStyle.stroke &&
                (arguments[1] as Paint).strokeCap == StrokeCap.round,
          ),
          reason: 'as ondas dela terminam redondas (page.tsx:61)',
        );
      }
    },
  );

  testWidgets(
    'a note being left shows her raised hand in azul at a third of the '
    'circle, not the loudspeaker box',
    (tester) async {
      for (final (theme, azul) in [
        (AppTheme.light, const Color(0xFF89AAA3)),
        (AppTheme.dark, const Color(0xFF8FB1A9)),
      ]) {
        await _pumpCircle(
          tester,
          VoiceState.invite,
          noteMode: true,
          theme: theme,
        );
        expect(_painter(tester).glyph, CircleGlyph.hand);
        expect(
          tester.getSize(_glyph),
          const Size(72, 72),
          reason:
              'a mão dela ocupa 60% do ícone, que ocupa 60% do círculo '
              '(globals.css:121, :175): 36%, não a caixa inteira do som',
        );
        expect(_veil(tester), 0.92);
        expect(
          _glyph,
          paints..path(
            style: PaintingStyle.stroke,
            strokeWidth: 1.5,
            color: azul,
            includes: const [Offset(14, 15), Offset(9, 8)],
            excludes: const [Offset(12, 21), Offset(3, 3), Offset(20, 10)],
          ),
          reason:
              '${theme.brightness.name}: a mão dela é um traço de 1.5 na caixa '
              'de 24 (page.tsx:84-94) — a palma e o primeiro dedo onde ela '
              'os desenhou — em azul (globals.css:174)',
        );
        expect(
          _glyph,
          paints..something(
            (method, arguments) =>
                method == #drawPath &&
                (arguments[1] as Paint).strokeCap == StrokeCap.round &&
                (arguments[1] as Paint).strokeJoin == StrokeJoin.round,
          ),
          reason: 'a mão dela tem pontas e quinas redondas (page.tsx:89)',
        );
      }
    },
  );

  testWidgets(
    'a peer cue shows her team glyph in its two greens, not one flat colour '
    'handed down by the circle',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await _pumpCircle(
          tester,
          VoiceState.invite,
          peerCue: true,
          theme: theme,
        );
        expect(_painter(tester).glyph, CircleGlyph.team);
        expect(tester.getSize(_glyph), const Size(120, 120));
        expect(_veil(tester), 0.92);
        expect(
          _glyph,
          paints
            ..path(
              style: PaintingStyle.fill,
              color: const Color(0xFF3F7F76),
              includes: const [
                Offset(-40, -22),
                Offset(40, -22),
                Offset(-40, 20),
                Offset(40, 20),
              ],
              excludes: const [Offset(0, -6)],
            )
            ..path(
              style: PaintingStyle.fill,
              color: const Color(0xFF2F6B62),
              includes: const [Offset(0, -6), Offset(0, 40)],
              excludes: const [Offset(-40, -22), Offset(40, -22)],
            ),
          reason:
              '${theme.brightness.name}: as duas figuras dos lados são '
              '#3F7F76 e a do meio, à frente, #2F6B62 (page.tsx:72-79); o '
              'nosso era o users do Lucide numa cor só',
        );
      }
    },
  );

  testWidgets(
    'a circle off her canvas draws no glyph in any voice, even when a note '
    'or a peer cue reaches it',
    (tester) async {
      for (final voice in VoiceState.values) {
        for (final (noteMode, peerCue) in const [
          (true, false),
          (false, true),
        ]) {
          await _pumpCircle(
            tester,
            voice,
            canvas: false,
            noteMode: noteMode,
            peerCue: peerCue,
          );
          expect(
            _glyph,
            findsNothing,
            reason:
                '${voice.name}, nota $noteMode, deixa $peerCue: os círculos de '
                'checagem dela não têm glifo (Drafting.tsx:2405, '
                'Rehearsal.tsx:903, ExternalCheck.tsx:426); o nosso desenhava '
                'a mão e as pessoas se alguém passasse a bandeira',
          );
        }
      }
    },
  );

  testWidgets(
    'each glyph cross-fades on its own 1 s ease: half way the old one still '
    'shows and the new one has come in',
    (tester) async {
      await _pumpCircle(tester, VoiceState.invite);
      expect(paintedGlyph(CircleGlyph.sound), findsOneWidget);
      const key = ValueKey('o mesmo canvas');
      Widget circle({required bool noteMode, bool still = false}) =>
          MaterialApp(
            key: key,
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: still),
              child: Scaffold(
                body: Center(
                  child: FacilitatorCircle(
                    size: 200,
                    voice: VoiceState.invite,
                    canvas: true,
                    noteMode: noteMode,
                    semanticLabel: 'circulo',
                  ),
                ),
              ),
            ),
          );
      double veil(CircleGlyph glyph) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: paintedGlyph(glyph),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;

      await tester.pumpWidget(circle(noteMode: false));
      await tester.pumpWidget(circle(noteMode: true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(veil(CircleGlyph.sound), closeTo(0.92 * (1 - 0.8024), 0.01));
      expect(veil(CircleGlyph.hand), closeTo(0.92 * 0.8024, 0.01));
      Color ink(CircleGlyph glyph) =>
          (tester.widget<CustomPaint>(paintedGlyph(glyph)).painter!
                  as CircleGlyphPainter)
              .ink;
      expect(
        ink(CircleGlyph.sound),
        SalaColors.of(tester.element(paintedGlyph(CircleGlyph.sound))).telha,
        reason: 'o alto-falante que sai guarda a telha dele (globals.css:124)',
      );
      expect(
        ink(CircleGlyph.hand),
        SalaColors.of(tester.element(paintedGlyph(CircleGlyph.hand))).azul,
        reason: 'a mão que entra é azul (globals.css:174)',
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(paintedGlyph(CircleGlyph.sound), findsNothing);
      expect(veil(CircleGlyph.hand), closeTo(0.92, 1e-6));

      await tester.pumpWidget(circle(noteMode: false, still: true));
      await tester.pump(const Duration(milliseconds: 1));
      expect(paintedGlyph(CircleGlyph.hand), findsNothing);
      expect(veil(CircleGlyph.sound), closeTo(0.92, 1e-6));
    },
  );
}
