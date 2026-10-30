import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'motion.dart';
import 'way_back_chevron.dart';

class BackToPassageButton extends ConsumerWidget {
  const BackToPassageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!session.theWayBackIsOffered) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);

    return Positioned(
      left: screen.width * 0.06 - 2,
      top: MediaQuery.viewPaddingOf(context).top + screen.height * 0.05 - 2,
      child: IgnorePointer(
        ignoring: !session.theWayBackIsLive,
        child: Semantics(
          button: true,
          enabled: session.theWayBackIsLive,
          label: roomLabelFor('backToPassage', ref.watch(roomLanguageProvider)),
          child: GestureDetector(
            onTap: session.sceneRehearsalIsOpen
                ? ref.read(salaSessionProvider.notifier).leaveTheSceneRehearsal
                : ref.read(salaSessionProvider.notifier).returnToTheLeftEntry,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 44,
              height: 44,
              child: AnimatedOpacity(
                duration: herFade(context, const Duration(milliseconds: 250)),
                curve: Curves.ease,
                opacity: !session.theWayBackIsLive
                    ? 0.2
                    : session.sceneRehearsalIsOpen
                    ? 0.6
                    : 0.5,
                child: const Center(child: WayBackChevron()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
