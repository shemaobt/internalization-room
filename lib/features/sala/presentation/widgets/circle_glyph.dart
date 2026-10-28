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

  static final _teamSides = Path()
    ..addOval(Rect.fromCircle(center: const Offset(-40, -22), radius: 17))
    ..moveTo(-68, 30)
    ..relativeArcToPoint(
      const Offset(56, 0),
      radius: const Radius.elliptical(28, 24),
    )
    ..close()
    ..addOval(Rect.fromCircle(center: const Offset(40, -22), radius: 17))
    ..moveTo(12, 30)
    ..relativeArcToPoint(
      const Offset(56, 0),
      radius: const Radius.elliptical(28, 24),
    )
    ..close();

  static final _teamMiddle = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0, -6), radius: 21))
    ..moveTo(-36, 48)
    ..relativeArcToPoint(
      const Offset(72, 0),
      radius: const Radius.elliptical(36, 30),
    )
    ..close();

  static const _handBox = Rect.fromLTWH(0, 0, 24, 24);

  static final _hand = Path()
    ..moveTo(8.2, 11.5)
    ..lineTo(8.2, 5.6)
    ..relativeArcToPoint(
      const Offset(2.4, 0),
      radius: const Radius.circular(1.2),
    )
    ..relativeLineTo(0, 4.7)
    ..relativeMoveTo(0, -5.6)
    ..relativeArcToPoint(
      const Offset(2.4, 0),
      radius: const Radius.circular(1.2),
    )
    ..relativeLineTo(0, 5.6)
    ..relativeMoveTo(0, -4.4)
    ..relativeArcToPoint(
      const Offset(2.4, 0),
      radius: const Radius.circular(1.2),
    )
    ..relativeLineTo(0, 5)
    ..relativeMoveTo(0, -3.4)
    ..relativeArcToPoint(
      const Offset(2.4, 0),
      radius: const Radius.circular(1.2),
    )
    ..relativeLineTo(0, 6.4)
    ..relativeCubicTo(0, 3.6, -2.3, 6, -5.8, 6)
    ..relativeCubicTo(-2.6, 0, -4, -0.9, -5.3, -3)
    ..relativeLineTo(-2, -3.3)
    ..relativeArcToPoint(
      const Offset(2.1, -1.3),
      radius: const Radius.circular(1.25),
    )
    ..relativeLineTo(1.4, 2.1);

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
      case CircleGlyph.hand:
        _fit(canvas, size, _handBox);
        canvas.drawPath(
          _hand,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      case CircleGlyph.team:
        _fit(canvas, size, _wideBox);
        canvas
          ..drawPath(_teamSides, Paint()..color = const Color(0xFF3F7F76))
          ..drawPath(_teamMiddle, Paint()..color = const Color(0xFF2F6B62));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CircleGlyphPainter old) =>
      old.glyph != glyph || old.ink != ink;
}
