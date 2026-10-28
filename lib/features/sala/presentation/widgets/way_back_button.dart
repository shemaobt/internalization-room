import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';

class WayBackButton extends ConsumerWidget {
  final SalaStage stage;
  final double top;

  const WayBackButton({super.key, required this.stage, required this.top});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (session.stage != stage) return const SizedBox.shrink();
    final away = session.wayOutIsHidden;

    return Positioned(
      left: 14,
      top: top,
      child: IgnorePointer(
        ignoring: away,
        child: AnimatedOpacity(
          opacity: away ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: Semantics(
            button: true,
            label: roomLabelFor(
              stage == SalaStage.retro ? 'backToRecording' : 'backToPassage',
              ref.watch(roomLanguageProvider),
            ),
            child: GestureDetector(
              onTap: stage == SalaStage.retro
                  ? ref
                        .read(salaSessionProvider.notifier)
                        .leaveTheBackTranslation
                  : ref.read(salaSessionProvider.notifier).leaveTheRecording,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Center(
                  child: Icon(
                    LucideIcons.chevronLeft,
                    size: 22,
                    color: ShemaBrand.verdeClaro,
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
