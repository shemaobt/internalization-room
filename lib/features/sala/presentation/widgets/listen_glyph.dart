import 'package:flutter/material.dart';

enum ListenGlyph { play, pause, stop }

class ListenGlyphPainter extends CustomPainter {
  final ListenGlyph glyph;
  final Color ink;

  const ListenGlyphPainter({required this.glyph, required this.ink});

  static final _play = Path()
    ..moveTo(8, 6)
    ..lineTo(18, 12)
    ..lineTo(8, 18)
    ..close();

  static final _pause = Path()
    ..addRRect(RRect.fromLTRBR(6, 5, 10, 19, const Radius.circular(1)))
    ..addRRect(RRect.fromLTRBR(14, 5, 18, 19, const Radius.circular(1)));

  static final _stop = Path()
    ..addRRect(RRect.fromLTRBR(6, 6, 18, 18, const Radius.circular(2)));

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(switch (glyph) {
        ListenGlyph.play => _play,
        ListenGlyph.pause => _pause,
        ListenGlyph.stop => _stop,
      }, Paint()..color = ink)
      ..restore();
  }

  @override
  bool shouldRepaint(ListenGlyphPainter old) =>
      old.glyph != glyph || old.ink != ink;
}
