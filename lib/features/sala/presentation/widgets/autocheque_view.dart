import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/meaning_map.dart';
import 'bead_styles.dart';
import 'motion.dart';

class AutochequeView extends ConsumerWidget {
  const AutochequeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < RuthOneMeaningMap.segmentCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: _checkBead(colors, i, session.checkIndex),
              ),
          ],
        ),
        const SizedBox(height: 56),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 64,
              semanticLabel: 'Ouvir de novo',
              background: colors.elev,
              border: Border.all(color: colors.line, width: 1.5),
              onTap: notifier.checkRedo,
              child: Icon(LucideIcons.rotateCcw, size: 26, color: colors.mut),
            ),
            const SizedBox(width: 28),
            RoundActionButton(
              size: 74,
              semanticLabel: 'Este trecho está bom',
              gradient: BeadStyles.verde,
              shadows: [
                BoxShadow(
                  color: ShemaBrand.verdeLo.withValues(alpha: 0.35),
                  offset: const Offset(0, 4),
                  blurRadius: 14,
                ),
              ],
              onTap: notifier.checkOk,
              child: const Icon(
                LucideIcons.check,
                size: 30,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _checkBead(SalaColors colors, int i, int checkIndex) {
    final current = i == checkIndex;
    final done = i < checkIndex;
    final size = current ? 48.0 : 32.0;
    final bead = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: done ? BeadStyles.verde : BeadStyles.wood,
        boxShadow: [
          ...BeadStyles.matte,
          if (current) BoxShadow(color: colors.halo, spreadRadius: 5),
        ],
      ),
    );
    if (!current) return bead;
    return Loop(
      period: const Duration(milliseconds: 1400),
      builder: (context, t) =>
          Transform.scale(scale: 1 + 0.12 * t, child: bead),
    );
  }
}
