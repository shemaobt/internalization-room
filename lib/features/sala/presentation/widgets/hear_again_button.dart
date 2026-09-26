import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';
import 'motion.dart';

class HearAgainButton extends ConsumerWidget {
  const HearAgainButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canHear = ref.watch(
      salaSessionProvider.select((session) => session.canHearAgain),
    );
    // The opening was told in two movements, so a held press can give back the one a tap
    // leaves out. Nothing on the button says so; the necklace coming off the cord and
    // being strung again is what the team sees when the press lands.
    final twoMovements = ref.watch(
      salaSessionProvider.select(
        (session) => session.lastSpoken?.toldInTwoMovements ?? false,
      ),
    );
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
                    size: 44,
                    semanticLabel: roomLabelFor(
                      'hearAgain',
                      ref.watch(roomLanguageProvider),
                    ),
                    onTap: ref.read(salaSessionProvider.notifier).hearAgain,
                    onLongPress: twoMovements
                        ? ref
                              .read(salaSessionProvider.notifier)
                              .hearTheWholeOpening
                        : null,
                    child: const Icon(
                      LucideIcons.rotateCcw,
                      size: 22,
                      color: ShemaBrand.verdeClaro,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
