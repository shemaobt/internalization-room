import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/device_link.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';

String _preparing(String language) => switch (language) {
      'pt' => 'A sala está preparando o código deste aparelho',
      'es' => 'La sala está preparando el código de este aparato',
      _ => 'The room is getting a code for this tablet',
    };

String _showIt(String language) => switch (language) {
      'pt' => 'Mostre este código ao facilitador',
      'es' => 'Muestre este código al facilitador',
      _ => 'Show this code to the facilitator',
    };

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
          size: 196,
          voice: VoiceState.thinking,
          semanticLabel: _preparing(language),
        ),
      );
    }
    return Semantics(
      label: _showIt(language),
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
