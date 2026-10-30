import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'facilitator_circle.dart';
import 'mic_clock.dart';
import 'thinking_note.dart';

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
            voice: session.circleVoice,
            noteMode: session.noteMode,
            canvas: true,
            semanticLabel: circleLabelFor('default', language),
            onTap: notifier.panoramaTap,
          ),
        ),
        if (session.takeRecordingSince case final since?)
          MicClock(circleSize: circleSize, since: since),
        if (session.writesTheThinkingNote)
          ThinkingNote(circleSize: circleSize, language: language),
      ],
    );
  }
}
