import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(EqBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active) {
      _controller.stop();
      _controller.value = 0;
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
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 24; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: _bar(i, colors, activeColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(int i, SalaColors colors, Color activeColor) {
    final baseHeight = 10.0 + (i * 7) % 26;
    var height = baseHeight;
    if (widget.active) {
      final phase = (_controller.value * (2 + i % 3) + i * 0.11) % 1.0;
      final wave = (0.35 + 0.65 * (0.5 + 0.5 * _triangle(phase)));
      height = baseHeight * wave;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      width: 5,
      height: height,
      decoration: BoxDecoration(
        color: widget.active ? activeColor : colors.cord,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  double _triangle(double t) => t < 0.5 ? 4 * t - 1 : 3 - 4 * t;
}
