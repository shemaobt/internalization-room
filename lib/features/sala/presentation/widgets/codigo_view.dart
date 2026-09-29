import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/device_link.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';

class CodigoView extends StatelessWidget {
  final ClaimCode? code;
  final String language;

  const CodigoView({super.key, this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final showing = code;
    if (showing == null) {
      return Center(
        child: FacilitatorCircle(
          size: facilitatorCircleSize,
          voice: VoiceState.thinking,
          semanticLabel: codigoLabelFor('preparing', language),
        ),
      );
    }
    return Semantics(
      label: codigoLabelFor('showIt', language),
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
