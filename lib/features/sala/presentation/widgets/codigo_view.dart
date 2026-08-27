import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/device_link.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';

class CodigoView extends StatelessWidget {
  final ClaimCode? code;

  const CodigoView({super.key, this.code});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final showing = code;
    if (showing == null) {
      return const Center(
        child: FacilitatorCircle(
          size: 196,
          voice: VoiceState.thinking,
          semanticLabel: 'A sala está preparando o código deste aparelho',
        ),
      );
    }
    return Semantics(
      label: 'Mostre este código ao facilitador',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              showing.code,
              maxLines: 1,
              style: TextStyle(
                color: colors.ink,
                fontSize: 96,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
