import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'corner_disc.dart';

class LeavePassageButton extends ConsumerWidget {
  final ({SalaStage stage, double top})? carried;

  const LeavePassageButton({super.key, this.carried});

  static const _floating = {SalaStage.panorama, SalaStage.conversa};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final stands = carried == null
        ? _floating.contains(session.stage)
        : session.stage == carried!.stage;
    if (!stands) return const SizedBox.shrink();
    final away = session.wayOutIsHidden;

    return Positioned(
      left: 14,
      top: carried?.top ?? 118 + MediaQuery.viewPaddingOf(context).top,
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
                child: Center(child: CornerDisc(glyph: LucideIcons.menu)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
