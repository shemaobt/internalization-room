import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_rehearsal.dart';
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
    String said(String control, [int? n]) =>
        sceneRehearsalLabelFor(control, language, n: n);
    final colors = SalaColors.of(context);
    final scene = session.scene;
    final sending = session.theSceneIsSending;
    final sendable = scene.sendable && !session.needsPerson;
    final unlessSending = sending ? ButtonMood.dimmed : ButtonMood.lit;
    final playable = sending || scene.waiting
        ? ButtonMood.dimmed
        : ButtonMood.lit;

    final terminei = RoundActionButton(
      size: 52,
      mood: sending
          ? ButtonMood.waiting
          : sendable
          ? ButtonMood.lit
          : ButtonMood.dimmed,
      halo: colors.vermelhoMic,
      semanticLabel: said(sending ? 'sending' : 'send'),
      onTap: notifier.sendTheSceneRehearsal,
      child: Icon(
        LucideIcons.check,
        size: 22,
        color: sending || sendable ? colors.vermelhoMic : colors.mut,
      ),
    );
    final again = RoundActionButton(
      size: 52,
      mood: unlessSending,
      semanticLabel: said('again'),
      onTap: notifier.recordTheSceneAgain,
      child: Icon(LucideIcons.mic, size: 22, color: colors.vermelhoMic),
    );
    final playIcon = Icon(
      session.channel is PartPlaying ? LucideIcons.pause : LucideIcons.play,
      size: 40,
      color: colors.vermelhoMic,
    );

    return Column(
      children: [
        Expanded(
          child: Center(
            child: switch (scene.step) {
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
                    mood: playable,
                    semanticLabel: said('translate'),
                    onTap: notifier.playTheSceneRehearsal,
                    border: Border.all(color: colors.vermelhoMic, width: 2),
                    child: playIcon,
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
                      mood: unlessSending,
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
                label: said('listen'),
                child: _ListenMode(
                  scene: scene,
                  said: said,
                  play: RoundActionButton(
                    size: 120,
                    mood: playable,
                    semanticLabel: said('playPause'),
                    onTap: notifier.playTheSceneRehearsal,
                    border: Border.all(color: colors.vermelhoMic, width: 2),
                    child: playIcon,
                  ),
                  again: again,
                ),
              ),
            },
          ),
        ),
        if (session.sceneRehearsals.isNotEmpty)
          Semantics(
            label: said('list'),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final row in session.sceneRehearsals)
                    _ListedRow(
                      row: row,
                      onScreen: row.rehearsalId == scene.rehearsal?.rehearsalId,
                      still:
                          sending ||
                          scene.waiting ||
                          session.channel is Microphone,
                      language: language,
                      onTap: () =>
                          notifier.openTheListedSceneRehearsal(row.rehearsalId),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ListedRow extends StatelessWidget {
  final SceneRehearsalRecord row;
  final bool onScreen;
  final bool still;
  final String language;
  final VoidCallback onTap;

  const _ListedRow({
    required this.row,
    required this.onScreen,
    required this.still,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return RoundActionButton(
      size: 44,
      mood: onScreen || still ? ButtonMood.dimmed : ButtonMood.lit,
      semanticLabel: sceneRehearsalRowLabelFor(
        row,
        language,
        onScreen: onScreen,
      ),
      onTap: onTap,
      border: Border.all(color: colors.vermelhoMic, width: 1.5),
      child: Icon(
        row.unsent ? LucideIcons.mic : LucideIcons.check,
        size: 18,
        color: colors.vermelhoMic,
      ),
    );
  }
}

class _ListenMode extends ConsumerWidget {
  final SceneScreen scene;
  final String Function(String control, [int? n]) said;
  final Widget play;
  final Widget again;

  const _ListenMode({
    required this.scene,
    required this.said,
    required this.play,
    required this.again,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final frases = scene.rehearsal?.currentFrases ?? const <SceneFrase>[];
    int span(SceneFrase frase) =>
        frase.placedIn(scene.length) ? frase.endsMs! - frase.startsMs! : 0;
    final longest = frases.map(span).fold(0, max);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        play,
        const SizedBox(height: 16),
        _Strip(frases: frases, length: scene.length),
        const SizedBox(height: 16),
        for (final (i, frase) in frases.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  enabled: !scene.waiting,
                  label: said('frase', i + 1),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: scene.waiting
                        ? null
                        : () => notifier.playTheFrase(frase.fraseId),
                    child: SizedBox(
                      width: 240,
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: span(frase) > 0
                              ? max(0.08, span(frase) / longest)
                              : 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.vermelhoMic.withValues(
                                alpha: span(frase) > 0 && !scene.waiting
                                    ? 0.6
                                    : 0.2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                RoundActionButton(
                  size: 40,
                  mood: scene.waiting ? ButtonMood.dimmed : ButtonMood.lit,
                  semanticLabel: said('hearMine', i + 1),
                  onTap: () => notifier.hearTheFraseTranslation(frase.fraseId),
                  child: Icon(
                    LucideIcons.volume2,
                    size: 18,
                    color: colors.vermelhoMic,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        again,
      ],
    );
  }
}

/// The take's length as a thin track, each placed frase's stretch marked on it.
class _Strip extends StatelessWidget {
  final List<SceneFrase> frases;
  final Duration? length;

  const _Strip({required this.frases, required this.length});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final whole = length?.inMilliseconds ?? 0;
    return ExcludeSemantics(
      child: SizedBox(
        width: 292,
        height: 8,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (whole > 0)
                for (final frase in frases.where((f) => f.placedIn(length)))
                  Positioned(
                    left: box.maxWidth * frase.startsMs! / whole,
                    width:
                        box.maxWidth *
                        (frase.endsMs! - frase.startsMs!) /
                        whole,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.vermelhoMic.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCircle extends StatelessWidget {
  final bool recording;
  final String Function(String control, [int? n]) label;
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
