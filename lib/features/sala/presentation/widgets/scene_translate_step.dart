import 'dart:math';

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
/// strip, «traduzir o ensaio da cena» until the team listens, the circle, the frases told,
/// «terminei», and «gravar o ensaio da cena de novo» under it.
class SceneTranslateStep extends ConsumerWidget {
  final SceneScreen scene;
  final Channel channel;
  final String language;
  final bool sending;
  final bool sendable;

  const SceneTranslateStep({
    super.key,
    required this.scene,
    required this.channel,
    required this.language,
    required this.sending,
    required this.sendable,
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
    final longest = frases.fold(
      1,
      (longest, frase) => max(longest, frase.spanIn(scene.length)),
    );

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
          if (frases.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final (i, frase) in frases.indexed)
              _FraseBar(
                n: i + 1,
                share: frase.spanIn(scene.length) / longest,
                words: said('frase', i + 1),
                style: words,
              ),
          ],
          const SizedBox(height: 16),
          _WrittenButton(
            said(sending ? 'sending' : 'send'),
            live: sendable && !sending,
            onTap: notifier.sendTheSceneRehearsal,
            large: true,
          ),
          const SizedBox(height: 8),
          _WrittenButton(
            said('again'),
            live: !sending,
            onTap: notifier.recordTheSceneAgain,
            bare: true,
          ),
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
  final bool large;
  final bool bare;

  const _WrittenButton(
    this.words, {
    required this.live,
    required this.onTap,
    this.large = false,
    this.bare = false,
  });

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
              padding: EdgeInsets.symmetric(
                horizontal: large ? 32 : 20,
                vertical: large ? 14 : 10,
              ),
              decoration: bare
                  ? null
                  : BoxDecoration(
                      color: large ? colors.vermelhoMic : null,
                      border: Border.all(color: colors.vermelhoMic, width: 1.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
              child: Text(
                words,
                style: TextStyle(
                  color: large ? colors.paper : colors.ink,
                  fontSize: large ? 18 : 14,
                  decoration: bare ? TextDecoration.underline : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One frase told, as on hers: its number, a bar as long as its stretch against the
/// longest, and «frase N».
class _FraseBar extends StatelessWidget {
  final int n;
  final double share;
  final String words;
  final TextStyle style;

  const _FraseBar({
    required this.n,
    required this.share,
    required this.words,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      label: words,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, child: Text('$n', style: style)),
              SizedBox(
                width: 200,
                height: 10,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: share > 0 ? max(0.08, share) : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.vermelhoMic.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(words, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
