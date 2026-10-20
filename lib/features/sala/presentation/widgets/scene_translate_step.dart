import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/pausa.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';
import 'scene_strip.dart';

/// The translate step, in her order: the instruction, the play control and the hint, the
/// strip, «traduzir o ensaio da cena» until the team listens, the circle, her message
/// under it and «manter a tradução de antes» while a frase is translated again, the
/// frases told, «terminei», and «gravar o ensaio da cena de novo» under it.
class SceneTranslateStep extends ConsumerWidget {
  final SceneScreen scene;
  final Envelope? envelope;
  final Channel channel;
  final String language;
  final bool sending;
  final bool sendable;
  final bool unseen;

  const SceneTranslateStep({
    super.key,
    required this.scene,
    required this.envelope,
    required this.channel,
    required this.language,
    required this.sending,
    required this.sendable,
    required this.unseen,
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
    final message = _messageOf(frases);

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
            envelope: envelope,
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
          if (message != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: _Written(
                message,
                style: TextStyle(color: colors.mut, fontSize: 16),
              ),
            ),
          ],
          if (scene.translatingAgain != null && !unseen) ...[
            const SizedBox(height: 8),
            _WrittenButton(
              said('keepTheEarlier'),
              live: !scene.waiting && !telling,
              onTap: notifier.keepTheEarlierTranslation,
              bare: true,
            ),
          ],
          if (frases.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final (i, frase) in frases.indexed)
              _FraseBar(
                n: i + 1,
                share: frase.spanIn(scene.length) / longest,
                words: said('frase', i + 1),
                translateAgain: said('retellFrase', i + 1),
                hearMine: said('hearMine', i + 1),
                live: idle,
                style: words,
                onTranslateAgain: () =>
                    notifier.translateTheFraseAgain(frase.fraseId),
                onHear: () => notifier.hearTheFraseTranslation(frase.fraseId),
              ),
          ],
          if (!scene.wentToTheVoice) ...[
            const SizedBox(height: 16),
            _WrittenButton(
              said(sending ? 'sending' : 'send'),
              live: sendable && !sending,
              onTap: notifier.sendTheSceneRehearsal,
              large: true,
            ),
          ],
          const SizedBox(height: 8),
          _WrittenButton(
            said('again'),
            live: !sending && !scene.waiting,
            onTap: notifier.recordTheSceneAgain,
            bare: true,
          ),
        ],
      ),
    );
  }

  /// Her line under the circle: the send-off, a frase the room did not understand, or
  /// the frase being translated again.
  String? _messageOf(List<SceneFrase> frases) {
    final again = frases.indexWhere(
      (frase) => frase.fraseId == scene.translatingAgain?.fraseId,
    );
    if (scene.wentToTheVoice) {
      return sceneRehearsalLabelFor('wentToTheVoice', language);
    }
    if (scene.notUnderstood) return retroLabelFor('notUnderstood', language);
    if (again >= 0) {
      return sceneRehearsalLabelFor('retelling', language, n: again + 1);
    }
    return null;
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
        envelope == null ? 'pauseAtTheTap' : 'pauseHint',
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
/// longest that plays its stretch and translates it again, «frase N», and the speaker
/// that plays the team's translation of it.
class _FraseBar extends StatelessWidget {
  final int n;
  final double share;
  final String words;
  final String translateAgain;
  final String hearMine;
  final bool live;
  final TextStyle style;
  final VoidCallback onTranslateAgain;
  final VoidCallback onHear;

  const _FraseBar({
    required this.n,
    required this.share,
    required this.words,
    required this.translateAgain,
    required this.hearMine,
    required this.live,
    required this.style,
    required this.onTranslateAgain,
    required this.onHear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: live,
            label: translateAgain,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: live ? onTranslateAgain : null,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: live ? 1 : 0.35,
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
                                color: colors.vermelhoMic.withValues(
                                  alpha: 0.6,
                                ),
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
            ),
          ),
          const SizedBox(width: 12),
          RoundActionButton(
            size: 40,
            mood: live ? ButtonMood.lit : ButtonMood.dimmed,
            semanticLabel: hearMine,
            onTap: onHear,
            child: Icon(
              LucideIcons.volume2,
              size: 18,
              color: colors.vermelhoMic,
            ),
          ),
        ],
      ),
    );
  }
}
