import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/kept_take.dart';
import 'bead_styles.dart';
import 'motion.dart';

class ReplayChips extends StatelessWidget {
  final List<KeptTake> takes;
  final String? replayingScope;
  final void Function(String scopeId) onReplay;

  const ReplayChips({
    super.key,
    required this.takes,
    required this.replayingScope,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    if (takes.isEmpty) return const SizedBox(height: 44);
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final take in takes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _chip(context, take),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, KeptTake take) {
    final playing = take.scopeId == replayingScope;
    final chip = Semantics(
      button: true,
      label: 'Ouvir o ensaio guardado de vocês',
      child: GestureDetector(
        onTap: () => onReplay(take.scopeId),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: BeadStyles.wood,
            boxShadow: BeadStyles.matte,
          ),
          child: const Icon(
            LucideIcons.play,
            size: 16,
            color: ShemaBrand.branco,
          ),
        ),
      ),
    );
    if (!playing) return FadeUp(child: chip);
    return Pulse(child: chip);
  }
}
