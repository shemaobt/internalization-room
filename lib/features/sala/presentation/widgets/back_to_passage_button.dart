import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class BackToPassageButton extends ConsumerWidget {
  const BackToPassageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (session.stage != SalaStage.escolha ||
        session.leftEntry == null ||
        session.naRoda == null ||
        session.needsPerson) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 14,
      top: 118 + MediaQuery.viewPaddingOf(context).top,
      child: IgnorePointer(
        ignoring: session.voice != VoiceState.invite,
        child: Semantics(
          button: true,
          label: roomLabelFor('backToPassage', ref.watch(roomLanguageProvider)),
          child: GestureDetector(
            onTap: ref.read(salaSessionProvider.notifier).returnToTheLeftEntry,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Opacity(
                opacity: 0.5,
                child: Icon(
                  LucideIcons.chevronLeft,
                  size: 24,
                  color: SalaColors.of(context).mut,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
