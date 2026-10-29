import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/machine.dart' show TakeInTheAir, TheKeep;
import '../../domain/scene_question.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'scene_question.dart';
import 'scene_translate_step.dart';
import 'scene_take_state.dart';
import 'stage_heading.dart';

/// The scene rehearsal's screen; her title and this session's list are written on every
/// step, the translate, places-unknown and sent steps write her words (ADR 0014), the
/// record step writes her instruction and hint (ADR 0155) and the take's state (ADR
/// 0131), and its circle is named only through VoiceOver.
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

    return Column(
      children: [
        StageHeading(
          text: said('title'),
          style: TextStyle(
            color: colors.ink,
            fontSize: 26,
            fontWeight: FontWeight.w500,
          ),
          top:
              MediaQuery.viewPaddingOf(context).top +
              MediaQuery.sizeOf(context).height * 0.09,
          corner:
              MediaQuery.viewPaddingOf(context).top +
              MediaQuery.sizeOf(context).height * 0.05 +
              42,
        ),
        Expanded(
          child: Center(
            child: switch (scene.step) {
              SceneStep.record => switch (session.scenes) {
                ScenesAwaited() => const SizedBox.shrink(),
                final scenes => SingleChildScrollView(
                  child: _TheRecordStep(
                    recording: switch (session.channel) {
                      Microphone(owner: MicOwner.scene) => true,
                      _ => false,
                    },
                    keep: scene.keep,
                    inTheAir: session.sceneTakeInTheAir,
                    diskFailed: session.sceneLine == SceneLine.diskFailed,
                    label: said,
                    onTap: notifier.sceneTap,
                    onRetry: notifier.sendTheSceneTakeAgain,
                    onStop: notifier.stopTheSend,
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
                ),
              },
              SceneStep.translate => SceneTranslateStep(
                scene: scene,
                envelope: session.sceneEnvelope,
                channel: session.channel,
                language: language,
                sending: sending,
                sendable: sendable,
                unseen: session.sceneTranslationUnseen,
                adjusts: session.scenePausaAdjusts,
                moving: session.sceneFraseOnTheMove != null,
                line: session.sceneLine,
                restartShown: session.sceneRestartShown,
                restart: session.sceneRestart,
                stoppedAt: session.sceneStoppedAt,
              ),
              SceneStep.placesUnknown => SingleChildScrollView(
                child: ScenePlacesUnknown(
                  scene: scene,
                  language: language,
                  sending: sending,
                  sendable: sendable,
                  line: session.sceneLine,
                  restartShown: session.sceneRestartShown,
                  restart: session.sceneRestart,
                ),
              ),
              SceneStep.sent => SceneListenMode(
                scene: scene,
                envelope: session.sceneEnvelope,
                channel: session.channel,
                language: language,
                sending: sending,
                line: session.sceneLine,
                stoppedAt: session.sceneStoppedAt,
              ),
            },
          ),
        ),
        if (session.sceneRehearsals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 25.6, bottom: 32),
            child: SceneRehearsalList(
              rows: session.sceneRehearsals,
              onScreen: scene.rehearsal?.rehearsalId,
              still: sending || scene.waiting || session.channel is Microphone,
              language: language,
            ),
          ),
      ],
    );
  }
}

class _TheRecordStep extends StatelessWidget {
  final bool recording;
  final SceneKeep? keep;
  final bool diskFailed;
  final String Function(String control) label;
  final TakeInTheAir? inTheAir;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final void Function(TheKeep keep) onStop;
  final Widget? question;
  final Widget? chip;
  final bool focused;

  const _TheRecordStep({
    required this.recording,
    required this.keep,
    required this.inTheAir,
    required this.diskFailed,
    required this.label,
    required this.onTap,
    required this.onRetry,
    required this.onStop,
    required this.question,
    required this.chip,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(child: _theStep());

  Widget _theStep() {
    final chip = this.chip;
    final circle =
        question ??
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SceneSub(label('subRecord')),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            SceneRecordHint(
              recording: recording,
              keeping: keep is Keeping,
              label: label,
            ),
          ],
        );
    if (!recording && keep == null) {
      if (!diskFailed) return circle;
      return Semantics(
        label: label('diskFailed'),
        liveRegion: true,
        child: circle,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        SceneTakeState(
          recording: recording,
          keep: keep,
          inTheAir: inTheAir,
          label: label,
          onRetry: onRetry,
          onStop: onStop,
        ),
      ],
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
