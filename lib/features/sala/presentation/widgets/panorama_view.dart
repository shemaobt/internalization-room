import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';
import 'mic_clock.dart';

class PanoramaView extends ConsumerWidget {
  const PanoramaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final circleSize = herCircleSize(MediaQuery.sizeOf(context), 58, 232);

    return Stack(
      children: [
        Center(
          child: FacilitatorCircle(
            size: circleSize,
            halt: session.halt,
            voice: session.voice,
            noteMode: session.noteMode,
            canvas: true,
            semanticLabel: session.voice == VoiceState.listening
                ? circleLabelFor('listening', language)
                : circleLabelFor('default', language),
            onTap: notifier.panoramaTap,
          ),
        ),
        if (session.channel case Microphone(owner: MicOwner.conversation))
          MicClock(circleSize: circleSize),
      ],
    );
  }
}
