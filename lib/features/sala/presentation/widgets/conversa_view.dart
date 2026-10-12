import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/channel.dart';
import '../../domain/moment.dart';
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
    final screen = MediaQuery.sizeOf(context);
    final phone = screen.width <= 520;

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
                  duration: const Duration(milliseconds: 800),
                  child: MomentLabel(
                    at: moment.at,
                    words: words,
                    aria: momentAriaFor(language),
                    size: phone ? 11.52 : 12.8,
                  ),
                ),
              ),
            ),
        if (session.endOfThePassage ||
            session.moment?.at == MomentAt.ensaioFinal)
          Positioned(
            right: 14,
            top: 118 + MediaQuery.viewPaddingOf(context).top,
            child: IgnorePointer(
              ignoring: _dotIsHidden(session),
              child: AnimatedOpacity(
                opacity: _dotIsHidden(session) ? 0 : 0.85,
                duration: const Duration(milliseconds: 400),
                child: Semantics(
                  button: true,
                  label: roomLabelFor('recordDraft', language),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: SalaColors.of(context).telha,
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

  bool _dotIsHidden(SalaSessionState session) =>
      session.needsPerson ||
      switch (session.voice) {
        VoiceState.listening ||
        VoiceState.thinking ||
        VoiceState.speaking => true,
        _ => false,
      };

  String _circleLabel(SalaSessionState session, String language) {
    if (session.needsPerson) return circleLabelFor('needsPerson', language);
    if (session.offline) return circleLabelFor('offline', language);
    if (session.channel case Microphone(owner: MicOwner.question)) {
      return circleLabelFor('noteMode', language);
    }
    if (session.voice == VoiceState.listening) {
      return circleLabelFor('listening', language);
    }
    if (session.noteMode) return circleLabelFor('default', language);
    if (session.peerCue && session.voice == VoiceState.invite) {
      return circleLabelFor('teamTalk', language);
    }
    return circleLabelFor('default', language);
  }
}
