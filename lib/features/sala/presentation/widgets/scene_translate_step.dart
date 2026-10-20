import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';
import 'scene_strip.dart';

/// The translate step, in her order: the instruction, the play control and the hint, the
/// strip, «traduzir o ensaio da cena» until the team listens, the circle between «gravar de
/// novo» and «terminei», then the frases told.
class SceneTranslateStep extends ConsumerWidget {
  final SceneScreen scene;
  final Channel channel;
  final String language;
  final bool sending;
  final Widget again;
  final Widget terminei;

  const SceneTranslateStep({
    super.key,
    required this.scene,
    required this.channel,
    required this.language,
    required this.sending,
    required this.again,
    required this.terminei,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final playback = ref.read(playbackRepositoryProvider);
    final colors = SalaColors.of(context);
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    final playing = channel is PartPlaying;
    final telling = channel is Microphone;
    final frases = scene.rehearsal?.currentFrases ?? const <SceneFrase>[];
    final idle = !sending && !scene.waiting && !telling;
    final words = TextStyle(color: colors.ink, fontSize: 16);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Written(said('subTranslate'), style: words),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RoundActionButton(
                size: 52,
                mood: idle && scene.listened
                    ? ButtonMood.lit
                    : ButtonMood.dimmed,
                semanticLabel: said('playPause'),
                onTap: notifier.playTheSceneRehearsal,
                border: Border.all(color: colors.vermelhoMic, width: 2),
                child: Icon(
                  playing ? LucideIcons.pause : LucideIcons.play,
                  size: 22,
                  color: colors.vermelhoMic,
                ),
              ),
              const SizedBox(width: 16),
              Loop(
                period: const Duration(seconds: 1),
                animate: playing,
                reducible: false,
                builder: (context, _) =>
                    switch (_hintOf(playing: playing, at: playback.position)) {
                      final hint? => _Written(
                        hint,
                        style: TextStyle(color: colors.mut, fontSize: 16),
                      ),
                      null => const SizedBox.shrink(),
                    },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SceneStrip(
            envelope: scene.envelope,
            length: scene.length,
            frases: frases,
            pausa: scene.pausa,
            playing: playing,
          ),
          if (!scene.listened) ...[
            const SizedBox(height: 12),
            _WrittenButton(
              said('translate'),
              live: idle,
              onTap: notifier.playTheSceneRehearsal,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              again,
              const SizedBox(width: 24),
              RoundActionButton(
                size: 180,
                mood: telling
                    ? ButtonMood.beckoning
                    : scene.waiting
                    ? ButtonMood.waiting
                    : sending || !scene.listened
                    ? ButtonMood.dimmed
                    : ButtonMood.lit,
                halo: colors.vermelhoMic,
                semanticLabel: said('tell'),
                onTap: notifier.tapTheTranslateCircle,
                background: colors.vermelhoMic.withValues(alpha: 0.10),
                border: Border.all(color: colors.vermelhoMic, width: 2),
                child: Icon(
                  telling ? LucideIcons.square : LucideIcons.mic,
                  size: 56,
                  color: colors.vermelhoMic,
                ),
              ),
              const SizedBox(width: 24),
              terminei,
            ],
          ),
          const SizedBox(height: 12),
          if (frases.isNotEmpty) ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final (i, _) in frases.indexed)
                  _Written(said('frase', i + 1), style: words),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Her hint: the pausa waiting, the take playing with her clock, the end of the take,
  /// or the take paused; nothing before the team listens.
  String? _hintOf({required bool playing, required Duration at}) {
    final end = scene.takeEnd;
    final pausa = scene.pausa;
    if (!scene.listened) return null;
    if (pausa != null) {
      if (end != null && pausa >= end) {
        return sceneRehearsalLabelFor('ended', language);
      }
      return retroLabelFor(
        scene.envelope == null ? 'pauseAtTheTap' : 'pauseHint',
        language,
      );
    }
    if (playing) return sceneListeningLineFor(at, scene.length, language);
    if (!scene.moreToTell) return sceneRehearsalLabelFor('ended', language);
    return sceneRehearsalLabelFor('paused', language);
  }
}

/// Her words written on the screen, read by VoiceOver as written.
class _Written extends StatelessWidget {
  final String words;
  final TextStyle style;

  const _Written(this.words, {required this.style});

  @override
  Widget build(BuildContext context) => Semantics(
    label: words,
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(words, style: style, textAlign: TextAlign.center),
      ),
    ),
  );
}

class _WrittenButton extends StatelessWidget {
  final String words;
  final bool live;
  final VoidCallback onTap;

  const _WrittenButton(this.words, {required this.live, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: live,
      label: words,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: live ? onTap : null,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: live ? 1 : 0.35,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: colors.vermelhoMic, width: 1.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(words, style: TextStyle(color: colors.ink)),
            ),
          ),
        ),
      ),
    );
  }
}
