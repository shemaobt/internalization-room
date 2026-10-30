import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'motion.dart';

class LeavePassageButton extends ConsumerWidget {
  const LeavePassageButton({super.key});

  static const _floating = {SalaStage.panorama, SalaStage.conversa};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!_floating.contains(session.stage)) return const SizedBox.shrink();
    final away = session.wayOutIsHidden;
    final screen = MediaQuery.sizeOf(context);
    final bar = SalaColors.of(context).verdeClaro;

    return Positioned(
      left: screen.width * 0.06 - 7,
      top: MediaQuery.viewPaddingOf(context).top + screen.height * 0.05 - 11,
      child: IgnorePointer(
        ignoring: away,
        child: AnimatedOpacity(
          opacity: away ? 0 : 0.22,
          duration: herFade(context, const Duration(milliseconds: 400)),
          curve: Curves.ease,
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
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 22,
                    padding: const EdgeInsets.all(3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: bar,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
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
