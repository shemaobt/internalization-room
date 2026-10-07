import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class LeavePassageButton extends ConsumerWidget {
  const LeavePassageButton({super.key});

  static const _inside = {
    SalaStage.panorama,
    SalaStage.conversa,
    SalaStage.ensaio,
    SalaStage.retro,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!_inside.contains(session.stage)) return const SizedBox.shrink();
    final away = session.wayOutIsHidden;

    return Positioned(
      left: 14,
      top: 118 + MediaQuery.viewPaddingOf(context).top,
      child: IgnorePointer(
        ignoring: away,
        child: AnimatedOpacity(
          opacity: away ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Semantics(
            button: true,
            label: roomLabelFor(
              'leavePassage',
              ref.watch(roomLanguageProvider),
            ),
            child: GestureDetector(
              onTap: ref.read(salaSessionProvider.notifier).leaveThePassage,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Opacity(
                  opacity: 0.5,
                  child: Icon(
                    LucideIcons.menu,
                    size: 24,
                    color: SalaColors.of(context).mut,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
