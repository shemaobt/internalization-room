import 'package:flutter/material.dart';

class ReplayArcPainter extends CustomPainter {
  final Color ink;
  final double stroke;

  const ReplayArcPainter({required this.ink, this.stroke = 1.4});

  static const _viewBox = 24.0;

  static final _arc = Path()
    ..moveTo(3, 12)
    ..arcToPoint(
      const Offset(12, 3),
      radius: const Radius.circular(9),
      largeArc: true,
      clockwise: false,
    )
    ..arcToPoint(
      const Offset(5.26, 5.74),
      radius: const Radius.circular(9.75),
      clockwise: false,
    )
    ..lineTo(3, 8)
    ..moveTo(3, 3)
    ..relativeLineTo(0, 5)
    ..relativeLineTo(5, 0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _viewBox, size.height / _viewBox)
      ..drawPath(
        _arc,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(ReplayArcPainter old) =>
      old.ink != ink || old.stroke != stroke;
}
