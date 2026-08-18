import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

/// Where the team is in the book, and the way they move through it.
///
/// This used to be a hairline with a dot — a readout, inert to touch, while moving was a
/// tap on the circle that also said the passage's name. One gesture meant two things, it
/// only ever went forward, and coming back one passage cost a lap of the whole wheel.
///
/// So the readout became the control. A finger runs along the row and the mark follows,
/// both ways; each passage has its own notch, so the row says how many there are without
/// a number. It is a measuring stick, not a second necklace: the beads belong to the
/// coverage of one passage and would say the wrong thing here.
class PassageRuler extends StatefulWidget {
  final int total;
  final int at;

  /// Passages this tablet has work waiting in. They stand taller and take the room's
  /// own colour, because going back to one is a different act from starting one.
  final Set<int> started;

  /// While the finger is down: move, and stay quiet.
  final ValueChanged<int> onAim;

  /// When it lifts: say where they landed.
  final VoidCallback onSettle;

  /// Nothing has been touched yet, so the mark shows what it can do.
  final bool hint;

  const PassageRuler({
    super.key,
    required this.total,
    required this.at,
    required this.onAim,
    required this.onSettle,
    this.started = const {},
    this.hint = false,
  });

  static const _pad = 30.0;
  static const height = 76.0;

  static double _placeOf(int index, int total, double width) {
    if (total <= 1) return width / 2;
    final span = width - _pad * 2;
    return _pad + span * (index / (total - 1));
  }

  int _indexAt(double x, double width) {
    if (total <= 1) return 0;
    final span = width - _pad * 2;
    final t = ((x - _pad) / span).clamp(0.0, 1.0);
    return (t * (total - 1)).round();
  }

  @override
  State<PassageRuler> createState() => _PassageRulerState();
}

class _PassageRulerState extends State<PassageRuler> {
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final total = widget.total;
    if (total <= 0) return const SizedBox(height: PassageRuler.height);

    // Once a finger has run the row, the row has said what it does. Showing the hint for
    // the rest of the session would repaint this screen sixty times a second forever, to
    // teach something already learned.
    final hinting = widget.hint && !_touched;

    return LayoutBuilder(
      builder: (context, box) {
        void aimAt(double dx) {
          if (!_touched) setState(() => _touched = true);
          widget.onAim(widget._indexAt(dx, box.maxWidth));
        }

        return Semantics(
          slider: true,
          label: 'Escolher a passagem, correndo o dedo pela fileira',
          value: '${widget.at + 1} de $total',
          increasedValue: '${(widget.at + 2).clamp(1, total)} de $total',
          decreasedValue: '${widget.at.clamp(1, total)} de $total',
          onIncrease: () {
            aimAt(PassageRuler._placeOf(widget.at + 1, total, box.maxWidth));
            widget.onSettle();
          },
          onDecrease: () {
            aimAt(PassageRuler._placeOf(widget.at - 1, total, box.maxWidth));
            widget.onSettle();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => aimAt(details.localPosition.dx),
            onTapUp: (_) => widget.onSettle(),
            onHorizontalDragStart: (details) => aimAt(details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                aimAt(details.localPosition.dx),
            onHorizontalDragEnd: (_) => widget.onSettle(),
            child: SizedBox(
              height: PassageRuler.height,
              width: double.infinity,
              child: Loop(
                period: const Duration(milliseconds: 2600),
                animate: hinting,
                builder: (context, t) => CustomPaint(
                  painter: _RulerPainter(
                    total: total,
                    at: widget.at,
                    started: widget.started,
                    // Toward the end that has room, so the mark never drifts off the row.
                    nudge: hinting
                        ? 7 * t * (widget.at < total - 1 ? 1 : -1)
                        : 0,
                    cord: colors.cord,
                    mark: colors.telha,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  final int total;
  final int at;
  final Set<int> started;
  final double nudge;
  final Color cord;
  final Color mark;

  const _RulerPainter({
    required this.total,
    required this.at,
    required this.started,
    required this.nudge,
    required this.cord,
    required this.mark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..color = cord
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(PassageRuler._pad, y),
      Offset(size.width - PassageRuler._pad, y),
      line,
    );

    for (var index = 0; index < total; index++) {
      final x = PassageRuler._placeOf(index, total, size.width);
      // A passage with work waiting stands taller and wears the room's own colour, so a
      // team can find the one they left without anyone reading them a list.
      final waiting = started.contains(index);
      final reach = waiting ? 9.0 : 5.0;
      canvas.drawLine(
        Offset(x, y - reach),
        Offset(x, y + reach),
        Paint()
          ..color = waiting ? mark : cord
          ..strokeWidth = waiting ? 2.5 : 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final here = PassageRuler._placeOf(at, total, size.width) + nudge;
    canvas.drawCircle(Offset(here, y), 9, Paint()..color = mark);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.at != at ||
      old.total != total ||
      old.nudge != nudge ||
      old.cord != cord ||
      old.mark != mark ||
      old.started.length != started.length ||
      !old.started.containsAll(started);
}
