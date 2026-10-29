import 'package:flutter/material.dart';

class DashedEdge extends Decoration {
  final Color color;
  final double radius;

  const DashedEdge({required this.color, required this.radius});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedEdgePainter(this);
}

class _DashedEdgePainter extends BoxPainter {
  final DashedEdge edge;

  _DashedEdgePainter(this.edge);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final ink = Paint()
      ..color = edge.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (offset & configuration.size!).deflate(.5),
          Radius.circular(edge.radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 6) {
        canvas.drawPath(metric.extractPath(at, at + 3), ink);
      }
    }
  }
}
