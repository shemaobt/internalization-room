import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_question.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import '../../data/playback_repository.dart';
import '../../domain/pausa.dart';
import 'bead_styles.dart';
import 'motion.dart';
import 'scene_question.dart';
import 'scene_strip.dart';

/// The scene rehearsal's screen. Her words on the translate step are written as on hers
/// (ADR 0014); everywhere else they reach the team only through VoiceOver.
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
              SceneStep.record => switch (session.scenes) {
                ScenesAwaited() => const SizedBox.shrink(),
                final scenes => _TheRecordStep(
                  recording: switch (session.channel) {
                    Microphone(owner: MicOwner.scene) => true,
                    _ => false,
                  },
                  keep: scene.keep,
                  label: said,
                  onTap: notifier.sceneTap,
                  onRetry: notifier.sendTheSceneTakeAgain,
                  question: session.sceneQuestionShown
                      ? SceneQuestion(
                          scenes: scenes.scenes,
                          highlighted: session.sceneHighlighted,
                          language: language,
                          onPick: notifier.pickTheScene,
                        )
                      : null,
                  chip: !session.sceneChipShown
                      ? null
                      : switch (scenes.numberOf(scene.picked)) {
                          final n? => SceneChip(
                            words: sceneChipTextFor(
                              n,
                              scenes.scenes[n - 1].title,
                              language,
                            ),
                            label: sceneChipLabelFor(
                              n,
                              scenes.scenes[n - 1].title,
                              language,
                            ),
                            live: session.sceneChipLive,
                            onTap: notifier.backToTheSceneQuestion,
                          ),
                          null => null,
                        },
                  focused: scene.picked != null,
                ),
              },
              SceneStep.translate => _TranslateStep(
                scene: scene,
                channel: session.channel,
                language: language,
                still: sending,
                again: again,
                terminei: terminei,
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

/// The translate step, in her order: the instruction, the play control and the hint, the
/// strip, «traduzir o ensaio da cena» until the team listens, the circle between «gravar de
/// novo» and «terminei», then the frases told.
class _TranslateStep extends ConsumerWidget {
  final SceneScreen scene;
  final Channel channel;
  final String language;
  final bool still;
  final Widget again;
  final Widget terminei;

  const _TranslateStep({
    required this.scene,
    required this.channel,
    required this.language,
    required this.still,
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
    final moving = !still && !scene.waiting && !telling;
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
                mood: moving && scene.listened
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
              live: moving,
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
                    : still || !scene.listened
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
    final told = scene.told;
    final pausa = scene.pausa;
    final frontier = scene.rehearsal?.frontier ?? Duration.zero;
    if (!scene.listened) return null;
    if (pausa != null) {
      if (told != null && pausa >= told) {
        return sceneRehearsalLabelFor('ended', language);
      }
      return retroLabelFor(
        scene.envelope == null ? 'pauseAtTheTap' : 'pauseHint',
        language,
      );
    }
    if (playing) return sceneListeningLineFor(at, scene.length, language);
    if (told != null && pauseBounds(frontier, told) == null) {
      return sceneRehearsalLabelFor('ended', language);
    }
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

class _TheRecordStep extends StatelessWidget {
  final bool recording;
  final SceneKeep? keep;
  final String Function(String control) label;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final Widget? question;
  final Widget? chip;
  final bool focused;

  const _TheRecordStep({
    required this.recording,
    required this.keep,
    required this.label,
    required this.onTap,
    required this.onRetry,
    required this.question,
    required this.chip,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final chip = this.chip;
    final circle =
        question ??
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chip != null) ...[chip, const SizedBox(height: 24)],
            FocusOnArrival(
              wanted: focused,
              child: _RecordCircle(
                recording: recording,
                keeping: keep is Keeping,
                label: label,
                onTap: onTap,
              ),
            ),
          ],
        );
    final waiting = keep;
    if (recording || waiting is! NotKept) return circle;
    final colors = SalaColors.of(context);
    return Semantics(
      label: label(waiting.tooLarge ? 'tooLarge' : 'saveFailed'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(height: 32),
          RoundActionButton(
            size: 52,
            semanticLabel: label('retry'),
            onTap: onRetry,
            child: Icon(
              LucideIcons.rotateCw,
              size: 22,
              color: colors.vermelhoMic,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCircle extends StatelessWidget {
  final bool recording;
  final bool keeping;
  final String Function(String control) label;
  final VoidCallback onTap;

  const _RecordCircle({
    required this.recording,
    required this.keeping,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return RoundActionButton(
      size: 180,
      mood: keeping
          ? ButtonMood.dimmed
          : recording
          ? ButtonMood.beckoning
          : ButtonMood.lit,
      halo: colors.vermelhoMic,
      semanticLabel: label(
        keeping
            ? 'saving'
            : recording
            ? 'recording'
            : 'record',
      ),
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
