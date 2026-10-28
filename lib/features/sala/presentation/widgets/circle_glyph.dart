import 'dart:math' as math;

import 'package:flutter/material.dart';

enum CircleGlyph { sound, team, hand }

class CircleGlyphPainter extends CustomPainter {
  final CircleGlyph glyph;
  final Color ink;

  const CircleGlyphPainter({required this.glyph, required this.ink});

  static const _wideBox = Rect.fromLTWH(-76, -78, 152, 160);

  static final _soundBody = Path()
    ..moveTo(-56, -13)
    ..lineTo(-38, -13)
    ..lineTo(-18, -30)
    ..lineTo(-18, 30)
    ..lineTo(-38, 13)
    ..lineTo(-56, 13)
    ..close();

  static final _soundWaves = Path()
    ..moveTo(-6, -16)
    ..arcToPoint(const Offset(-6, 16), radius: const Radius.circular(20))
    ..moveTo(8, -28)
    ..arcToPoint(const Offset(8, 28), radius: const Radius.circular(34))
    ..moveTo(22, -40)
    ..arcToPoint(const Offset(22, 40), radius: const Radius.circular(48));

  void _fit(Canvas canvas, Size size, Rect box) {
    final scale = math.min(size.width / box.width, size.height / box.height);
    canvas
      ..translate(
        (size.width - box.width * scale) / 2,
        (size.height - box.height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-box.left, -box.top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    switch (glyph) {
      case CircleGlyph.sound:
        _fit(canvas, size, _wideBox);
        canvas
          ..drawPath(_soundBody, Paint()..color = ink)
          ..drawPath(
            _soundWaves,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5.5
              ..strokeCap = StrokeCap.round,
          );
      case CircleGlyph.team:
      case CircleGlyph.hand:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CircleGlyphPainter old) =>
      old.glyph != glyph || old.ink != ink;
}
