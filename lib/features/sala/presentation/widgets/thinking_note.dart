import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import 'motion.dart';

class ThinkingNote extends StatelessWidget {
  final double circleSize;
  final String language;

  const ThinkingNote({
    super.key,
    required this.circleSize,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.sizeOf(context).height / 2 + circleSize / 2 + 35.2,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Loop(
              period: const Duration(milliseconds: 2400),
              reducible: false,
              builder: (context, t) => Opacity(
                opacity: still ? 0.72 + 0.24 * t : 0.45 + 0.55 * t,
                child: Text(
                  roomLabelFor('thinking', language),
                  style: TextStyle(
                    color: SalaColors.of(context).telha,
                    fontSize: 16.8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.008,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
