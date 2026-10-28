import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
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
            ..path(style: PaintingStyle.stroke, strokeWidth: 5.5, color: telha),
          reason:
              '${theme.brightness.name}: o corpo do alto-falante dela é '
              '«M -56 -13 H -38 L -18 -30 V 30 L -38 13 H -56 Z» cheio, e as '
              'três ondas são traços de 5.5 (page.tsx:60-65), em telha',
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
}
