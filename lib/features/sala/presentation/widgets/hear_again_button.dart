import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import 'bead_styles.dart';
import 'motion.dart';

class HearAgainButton extends ConsumerWidget {
  const HearAgainButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canHear = ref.watch(
      salaSessionProvider.select((session) => session.canHearAgain),
    );
    final colors = SalaColors.of(context);

    return Positioned(
      right: 14,
      bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
      child: SizedBox(
        width: 76,
        height: 76,
        child: canHear
            ? Center(
                child: FadeUp(
                  child: RoundActionButton(
                    size: 60,
                    gradient: BeadStyles.telha(colors),
                    shadows: [
                      BoxShadow(
                        color: colors.telha.withValues(alpha: 0.3),
                        offset: const Offset(0, 6),
                        blurRadius: 18,
                      ),
                    ],
                    semanticLabel: 'Ouvir de novo',
                    onTap: ref.read(salaSessionProvider.notifier).hearAgain,
                    child: const Icon(
                      LucideIcons.rotateCcw,
                      size: 26,
                      color: ShemaBrand.branco,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
