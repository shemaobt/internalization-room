import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../../../core/config/env.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'hand_button.dart';
import 'motion.dart';

class ConversaView extends ConsumerWidget {
  const ConversaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 26),
              FacilitatorCircle(
                size: 158,
                voice: session.voice,
          reach: session.reach,
                noteMode: session.noteMode,
                peerCue: session.peerCue,
                      semanticLabel: _circleLabel(session),
                onTap: notifier.conversaTap,
                onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
              ),
              const SizedBox(height: 44),
              SizedBox(
                height: 64,
                child: session.conversaDone ||
                        (Env.devPularFases && session.sessionId != null)
                    ? AdvanceButton(
                        gradient: BeadStyles.verde,
                        semanticLabel: 'Ir para o ensaio',
                        onTap: notifier.goEnsaio,
                        child: const Icon(
                          LucideIcons.mic,
                          size: 26,
                          color: ShemaBrand.branco,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        Positioned(
          left: 14,
          bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
          child: HandButton(
            noteMode: session.noteMode,
            hasUnheardReply: session.hasUnheardReply,
            playingReply: session.playingReplyId != null,
            onTap: notifier.handTap,
          ),
        ),
        if (session.handAck)
          Positioned(
            left: 0,
            right: 0,
            bottom: 110,
            child: Center(
              child: const PingIn(child: KnotMark(size: 15)),
            ),
          ),
      ],
    );
  }

  String _circleLabel(SalaSessionState session) {
    if (session.needsPerson) return 'Um momento para uma pessoa';
    if (session.noteMode) return 'Enviar a pergunta';
    if (session.peerCue && session.voice == VoiceState.invite) {
      return 'Conversem entre vocês — tocar quando quiserem me contar';
    }
    if (session.voice == VoiceState.listening) return 'Tocar ao terminar';
    return 'Tocar para falar';
  }
}
