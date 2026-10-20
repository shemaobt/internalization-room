import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';

class PauseAdjustRow extends StatelessWidget {
  final bool lit;
  final String language;
  final VoidCallback onEarlier;
  final VoidCallback onHear;
  final VoidCallback onLater;

  const PauseAdjustRow({
    super.key,
    required this.lit,
    required this.language,
    required this.onEarlier,
    required this.onHear,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final mood = lit ? ButtonMood.lit : ButtonMood.dimmed;
    Widget control(String label, IconData glyph, VoidCallback onTap) =>
        RoundActionButton(
          size: 48,
          semanticLabel: retroLabelFor(label, language),
          gradient: BeadStyles.wood,
          mood: mood,
          onTap: onTap,
          child: Icon(glyph, size: 20, color: ShemaBrand.branco),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        control('pauseEarlier', LucideIcons.chevronLeft, onEarlier),
        const SizedBox(width: 24),
        control('hearThePause', LucideIcons.ear, onHear),
        const SizedBox(width: 24),
        control('pauseLater', LucideIcons.chevronRight, onLater),
      ],
    );
  }
}
