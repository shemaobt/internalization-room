import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';

/// The scene rehearsal's screen; her words reach the team only through VoiceOver.
class SceneRehearsalView extends ConsumerWidget {
  const SceneRehearsalView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    String said(String control) => sceneRehearsalLabelFor(control, language);
    final colors = SalaColors.of(context);

    final terminei = RoundActionButton(
      size: 52,
      mood: ButtonMood.dimmed,
      semanticLabel: said('send'),
      onTap: () {},
      child: Icon(LucideIcons.check, size: 22, color: colors.mut),
    );
    final again = RoundActionButton(
      size: 52,
      semanticLabel: said('again'),
      onTap: notifier.recordTheSceneAgain,
      child: Icon(LucideIcons.mic, size: 22, color: colors.vermelhoMic),
    );

    return Center(
      child: switch (session.scene.step) {
        SceneStep.record => _RecordCircle(
          recording: switch (session.channel) {
            Microphone(owner: MicOwner.scene) => true,
            _ => false,
          },
          label: said,
          onTap: notifier.sceneTap,
        ),
        SceneStep.translate => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 120,
              semanticLabel: said('translate'),
              onTap: notifier.playTheSceneRehearsal,
              border: Border.all(color: colors.vermelhoMic, width: 2),
              child: Icon(
                session.channel is PartPlaying
                    ? LucideIcons.pause
                    : LucideIcons.play,
                size: 40,
                color: colors.vermelhoMic,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [again, const SizedBox(width: 24), terminei],
            ),
          ],
        ),
        SceneStep.placesUnknown => Semantics(
          label: said('placesUnknown'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              terminei,
              const SizedBox(width: 24),
              RoundActionButton(
                size: 52,
                semanticLabel: said('restart'),
                onTap: notifier.restartTheSceneTranslation,
                child: Icon(
                  LucideIcons.rotateCcw,
                  size: 22,
                  color: colors.vermelhoMic,
                ),
              ),
              const SizedBox(width: 24),
              again,
            ],
          ),
        ),
        SceneStep.sent => Semantics(
          label: said('sent'),
          child: const SizedBox(width: 120, height: 120),
        ),
      },
    );
  }
}

class _RecordCircle extends StatelessWidget {
  final bool recording;
  final String Function(String control) label;
  final VoidCallback onTap;

  const _RecordCircle({
    required this.recording,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return RoundActionButton(
      size: 180,
      mood: recording ? ButtonMood.beckoning : ButtonMood.lit,
      halo: colors.vermelhoMic,
      semanticLabel: label(recording ? 'recording' : 'record'),
      onTap: onTap,
      background: colors.vermelhoMic.withValues(alpha: 0.10),
      border: Border.all(color: colors.vermelhoMic, width: 2),
      child: Icon(
        recording ? LucideIcons.square : LucideIcons.mic,
        size: 56,
        color: colors.vermelhoMic,
      ),
    );
  }
}
