import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

class ThinkNote extends StatelessWidget {
  final double circleSize;
  final String words;

  const ThinkNote({super.key, required this.circleSize, required this.words});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.sizeOf(context).height / 2 + circleSize / 2 + 35.2,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Center(
            child: Text(
              words,
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
    );
  }
}
