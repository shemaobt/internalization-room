import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

const _barCount = 24;
const _barWidth = 5.0;
const _barRadius = 3.0;
const _step = 8.0;
const _meterHeight = 40.0;
const _chaseDuration = Duration(milliseconds: 60);

class EqBars extends StatefulWidget {
  final bool active;

  const EqBars({super.key, required this.active});

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  List<double> _heights = List.generate(_barCount, _baseHeight);
  List<double> _targets = List.generate(_barCount, _baseHeight);
  Duration? _lastElapsed;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  static double _baseHeight(int i) => 10.0 + (i * 7) % 26;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(EqBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  void _follow() {
    if (widget.active && !_still) {
      if (!_controller.isAnimating) {
        _controller.repeat();
        if (_lastElapsed != null) _lastElapsed = Duration.zero;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    // The only raw hex in the widget layer, and it was tuned against the dark background:
    // 2.5:1 on the light paper, against 4.6:1 for the room's own telha. This is the
    // strongest "the microphone is on" cue on the rehearsal screen, and it was the least
    // legible thing on it — on a tablet outdoors, which is where this runs.
    final activeColor = colors.telha;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _chase();
        return RepaintBoundary(
          child: CustomPaint(
            size: const Size(_barCount * _step, _meterHeight),
            painter: EqBarsPainter(
              heights: List.of(_heights),
              barColor: widget.active ? activeColor : colors.cord,
            ),
          ),
        );
      },
    );
  }

  double _target(int i) {
    if (!widget.active || _still) return _baseHeight(i);
    final phase = (_controller.value * (2 + i % 3) + i * 0.11) % 1.0;
    final wave = 0.35 + 0.65 * (0.5 + 0.5 * _triangle(phase));
    return _baseHeight(i) * wave;
  }

  void _chase() {
    final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
    final freshTargets = List.generate(_barCount, _target);
    final lastElapsed = _lastElapsed;
    if (lastElapsed == null) {
      _heights = List.of(freshTargets);
    } else {
      final dt = elapsed - lastElapsed;
      final weight = (dt.inMicroseconds / _chaseDuration.inMicroseconds).clamp(
        0.0,
        1.0,
      );
      for (var i = 0; i < _barCount; i++) {
        _heights[i] = _heights[i] + weight * (_targets[i] - _heights[i]);
      }
    }
    _targets = freshTargets;
    _lastElapsed = elapsed;
    if ((!widget.active || _still) && _controller.isAnimating && _settled()) {
      _controller.stop();
    }
  }

  bool _settled() {
    for (var i = 0; i < _barCount; i++) {
      if ((_heights[i] - _baseHeight(i)).abs() > 0.01) return false;
    }
    return true;
  }

  double _triangle(double t) => t < 0.5 ? 4 * t - 1 : 3 - 4 * t;
}

class EqBarsPainter extends CustomPainter {
  final List<double> heights;
  final Color barColor;

  const EqBarsPainter({required this.heights, required this.barColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = barColor;
    for (var i = 0; i < heights.length; i++) {
      final rect = Rect.fromLTWH(
        i * _step + 1.5,
        size.height - heights[i],
        _barWidth,
        heights[i],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_barRadius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(EqBarsPainter old) => true;
}
