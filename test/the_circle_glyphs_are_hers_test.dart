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
}
