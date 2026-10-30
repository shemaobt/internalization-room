import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';
import 'motion.dart';
import 'replay_arc.dart';

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
      child: ExcludeSemantics(
        excluding: !canHear,
        child: IgnorePointer(
          ignoring: !canHear,
          child: AnimatedOpacity(
            opacity: canHear ? 0.42 : 0,
            duration: herFade(context, const Duration(milliseconds: 1200)),
            curve: Curves.ease,
            child: RoundActionButton(
              size: 44,
              semanticLabel: roomLabelFor(
                'hearAgain',
                ref.watch(roomLanguageProvider),
              ),
              onTap: ref.read(salaSessionProvider.notifier).hearAgain,
              child: CustomPaint(
                size: const Size.square(22),
                painter: ReplayArcPainter(ink: SalaColors.of(context).verde),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
