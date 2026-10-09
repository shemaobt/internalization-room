import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/channel.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'moment_label.dart';
import 'motion.dart';

class ConversaView extends ConsumerWidget {
  const ConversaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 26),
              FacilitatorCircle(
                size: 158,
                halt: session.halt,
                voice: session.voice,
                reach: session.reach,
                noteMode: session.noteMode,
                peerCue: session.peerCue,
                warning: session.warning
                    ? warningNoticeLabelFor(language)
                    : null,
                semanticLabel: _circleLabel(session, language),
                onTap: notifier.conversaTap,
                onLongPress: session.canResolveWithPerson
                    ? notifier.resolveWithPerson
                    : null,
              ),
              const SizedBox(height: 44),
              SizedBox(
                height: 64,
                child: !session.needsPerson
                    ? FadeUp(
                        child: RoundActionButton(
                          size: 64,
                          mood: ButtonMood.beckoning,
                          gradient: BeadStyles.verde,
                          shadows: RoundActionButton.dropShadow,
                          semanticLabel: recordEntryLabelFor(language),
                          onTap: notifier.goEnsaio,
                          child: const Icon(
                            LucideIcons.check,
                            size: 26,
                            color: ShemaBrand.branco,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        if (session.moment case final moment?)
          Positioned(
            left: 0,
            right: 0,
            top: 18 + MediaQuery.viewPaddingOf(context).top,
            child: Center(
              child: AnimatedOpacity(
                opacity: _momentOpacity(session),
                duration: const Duration(milliseconds: 800),
                child: MomentLabel(
                  moment: moment,
                  words: momentLabelFor(moment, language),
                  language: language,
                ),
              ),
            ),
          ),
        if (session.handAck)
          Positioned(
            left: 0,
            right: 0,
            bottom: 110,
            child: Center(child: const PingIn(child: KnotMark(size: 15))),
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

  String _circleLabel(SalaSessionState session, String language) {
    if (session.needsPerson) return circleLabelFor('needsPerson', language);
    if (session.offline) return circleLabelFor('offline', language);
    if (session.channel case Microphone(owner: MicOwner.question)) {
      return circleLabelFor('noteMode', language);
    }
    if (session.peerCue && session.voice == VoiceState.invite) {
      return circleLabelFor('teamTalk', language);
    }
    if (session.voice == VoiceState.listening) {
      return circleLabelFor('listening', language);
    }
    return circleLabelFor('default', language);
  }
}
