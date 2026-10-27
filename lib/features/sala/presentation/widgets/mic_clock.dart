import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

const _longTake = Duration(minutes: 4);

class MicClock extends StatefulWidget {
  final double circleSize;

  const MicClock({super.key, required this.circleSize});

  @override
  State<MicClock> createState() => _MicClockState();
}

class _MicClockState extends State<MicClock> {
  final _since = clock.now();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.sizeOf(context).height / 2 - widget.circleSize / 2 - 38.4,
      child: Center(
        child: Loop(
          period: const Duration(seconds: 1),
          reducible: false,
          builder: (context, _) {
            final elapsed = clock.now().difference(_since);
            return Text(
              '${elapsed.inMinutes}:'
              '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                color: elapsed >= _longTake
                    ? SalaColors.of(context).telha.withValues(alpha: 0.95)
                    : ShemaBrand.azul.withValues(alpha: 0.75),
                fontSize: 13.76,
                letterSpacing: 1.376,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
          },
        ),
      ),
    );
  }
}
