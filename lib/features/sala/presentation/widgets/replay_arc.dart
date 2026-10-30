import 'package:flutter/material.dart';

class ReplayArcPainter extends CustomPainter {
  final Color ink;

  const ReplayArcPainter({required this.ink});

  static const _viewBox = 24.0;
  static const stroke = 1.4;

  static final _path = Path()
    ..moveTo(5, 9)
    ..arcToPoint(
      const Offset(4, 12.5),
      radius: const Radius.circular(7),
      largeArc: true,
    )
    ..moveTo(5, 4.5)
    ..lineTo(5, 9)
    ..relativeLineTo(4.5, 0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _viewBox, size.height / _viewBox)
      ..drawPath(
        _path,
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
  bool shouldRepaint(ReplayArcPainter old) => old.ink != ink;
}
