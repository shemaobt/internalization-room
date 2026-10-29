import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';

class HearAgainButton extends ConsumerWidget {
  const HearAgainButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canHear = ref.watch(
      salaSessionProvider.select((session) => session.canHearAgain),
    );
    final screen = MediaQuery.sizeOf(context);
    return Positioned(
      right: screen.width * 0.08,
      bottom: MediaQuery.viewPaddingOf(context).bottom + screen.height * 0.16,
      child: SizedBox(
        width: 44,
        height: 44,
        child: canHear
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 0.42),
                duration: const Duration(milliseconds: 1200),
                builder: (context, opacity, arrow) =>
                    Opacity(opacity: opacity, child: arrow),
                child: RoundActionButton(
                  size: 44,
                  semanticLabel: roomLabelFor(
                    'hearAgain',
                    ref.watch(roomLanguageProvider),
                  ),
                  onTap: ref.read(salaSessionProvider.notifier).hearAgain,
                  child: Icon(
                    LucideIcons.rotateCcw,
                    size: 22,
                    color: SalaColors.of(context).verde,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
