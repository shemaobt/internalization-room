import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

const _longTake = Duration(minutes: 4);

class MicClock extends StatelessWidget {
  final double circleSize;
  final DateTime since;

  const MicClock({super.key, required this.circleSize, required this.since});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.sizeOf(context).height / 2 - circleSize / 2 - 38.4,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Center(
            child: Loop(
              period: const Duration(seconds: 1),
              reducible: false,
              builder: (context, _) {
                final elapsed = clock.now().difference(since);
                return Text(
                  '${elapsed.inMinutes}:'
                  '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: elapsed >= _longTake
                        ? SalaColors.of(context).telha.withValues(alpha: 0.95)
                        : SalaColors.of(context).azul.withValues(alpha: 0.75),
                    fontSize: 13.76,
                    letterSpacing: 1.376,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
