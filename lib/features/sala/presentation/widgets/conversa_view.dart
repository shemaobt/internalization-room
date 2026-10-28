import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';
import 'kept_retelling_buttons.dart';
import 'mic_clock.dart';
import 'moment_label.dart';
import 'motion.dart';

class ConversaView extends ConsumerWidget {
  const ConversaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final dotIsGone = session.orangeDotLook == OrangeDotLook.gone;
    final screen = MediaQuery.sizeOf(context);
    final phone = screen.width <= 520;
    final circleSize = herCircleSize(screen, 58, 232);

    return Stack(
      children: [
        Center(
          child: FacilitatorCircle(
            size: circleSize,
            halt: session.halt,
            voice: session.voice,
            noteMode: session.noteMode,
            peerCue: session.peerCue,
            canvas: true,
            semanticLabel: circleLabelFor('default', language),
            onTap: notifier.conversaTap,
          ),
        ),
        if (session.channel case Microphone(owner: MicOwner.conversation))
          MicClock(circleSize: circleSize),
        if (session.partsToReplay.isNotEmpty)
          KeptRetellingButtons(
            parts: session.partsToReplay,
            language: language,
            away: session.keptRetellingsAreAway,
            onTap: notifier.playKeptRetelling,
          ),
        if (session.moment case final moment?)
          if (momentLabelFor(moment, language) case final words?)
            Positioned(
              left: 0,
              right: 0,
              top: phone
                  ? max(screen.height * 0.08 + 66, screen.height * 0.05 + 94)
                  : screen.height * 0.08 + 58,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _momentOpacity(session),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 800),
                  child: MomentLabel(
                    at: moment.at,
                    words: words,
                    aria: momentAriaFor(language),
                    size: phone ? 11.52 : 12.8,
                  ),
                ),
              ),
            ),
        Positioned(
          right: 14,
          top: 118 + MediaQuery.viewPaddingOf(context).top,
          child: IgnorePointer(
            ignoring: dotIsGone,
            child: AnimatedOpacity(
              opacity: switch (session.orangeDotLook) {
                OrangeDotLook.gone => 0,
                OrangeDotLook.faint => 0.22,
                OrangeDotLook.bright => 0.85,
              },
              duration: const Duration(milliseconds: 400),
              child: ExcludeSemantics(
                excluding: dotIsGone,
                child: Semantics(
                  button: true,
                  label: roomLabelFor(
                    session.aPartWasJoined ? 'openEnsaioFinal' : 'recordEnsaio',
                    language,
                  ),
                  child: GestureDetector(
                    onTap: notifier.openTheEnsaioFinal,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SalaColors.of(context).momentoEf,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 15, height: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: phone ? 7 : 56,
          top: 118 + MediaQuery.viewPaddingOf(context).top + (phone ? 42 : -7),
          child: IgnorePointer(
            ignoring: !session.redMicrophoneIsShown,
            child: AnimatedOpacity(
              opacity: session.redMicrophoneIsShown ? 0.95 : 0,
              duration: const Duration(milliseconds: 400),
              child: _RedMicrophone(
                label: sceneRehearsalLabelFor('enter', language),
                onTap: notifier.openTheSceneRehearsal,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _momentOpacity(SalaSessionState session) {
    if (session.needsPerson || session.noteMode) return 0;
    return switch (session.voice) {
      VoiceState.listening || VoiceState.thinking || VoiceState.speaking => 0.6,
      _ => 1,
    };
  }
}

/// Her red microphone: round, red, haloed, and wordless.
class _RedMicrophone extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RedMicrophone({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final red = SalaColors.of(context).vermelhoMic;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Loop(
            period: const Duration(milliseconds: 2800),
            builder: (context, t) => Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: red.withValues(alpha: 0.10),
                border: Border.all(color: red, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: red.withValues(alpha: 0.38 * (1 - t)),
                    spreadRadius: 14 * t,
                  ),
                ],
              ),
              child: Icon(LucideIcons.mic, size: 22, color: red),
            ),
          ),
        ),
      ),
    );
  }
}
