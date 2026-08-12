import 'dart:math' as math;

import 'package:flutter/material.dart';

class DashedRing extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;
  final Widget? child;

  const DashedRing({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2.5,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRingPainter(color: color, strokeWidth: strokeWidth),
      child: SizedBox(
        width: size,
        height: size,
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _DashedRingPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    const dashes = 28;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}
