import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/device_link.dart';

class CodigoView extends StatelessWidget {
  final ClaimCode code;

  const CodigoView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      label: 'Mostre este código ao facilitador',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              code.code,
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
