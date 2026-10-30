import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/grain.dart';
import '../../domain/session_state.dart';
import 'stage_heading.dart';
import 'unsent_notice.dart';

/// Her grain choice: «Como vocês querem gravar?», under her line when the rehearsals sit
/// in the other language's session, and her two buttons.
class GrainChoiceView extends ConsumerWidget {
  final bool elsewhere;

  const GrainChoiceView({super.key, required this.elsewhere});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final open = !session.grainSwitching;
    _GrainButton choice(Grain grain, (String, String) lines) => _GrainButton(
      lines: lines,
      open: open,
      onTap: () => notifier.chooseTheGrain(grain),
    );

    return SafeArea(
      bottom: false,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              StageHeading(
                stage: SalaStage.ensaio,
                text: recordingHomeLabelFor('title', language),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                recordingHomeLabelFor('how', language),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mut, fontSize: 15),
              ),
              UnsentNotice(
                session: session,
                language: language,
                onSend: notifier.enviarACena,
              ),
              if (elsewhere) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      recordingHomeLabelFor('elsewhere', language),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.telha, fontSize: 15),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              choice(Grain.whole, (
                recordingHomeLabelFor('wholePassage', language),
                recordingHomeLabelFor('oneRecording', language),
              )),
              const SizedBox(height: 12),
              choice(Grain.scene, (
                recordingHomeLabelFor('sceneByScene', language),
                recordingHomeLabelFor(
                  'parts',
                  language,
                  n: session.scenesOfThePassage?.length ?? 0,
                ),
              )),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrainButton extends StatelessWidget {
  final (String, String) lines;
  final bool open;
  final VoidCallback onTap;

  const _GrainButton({
    required this.lines,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final (name, size) = lines;
    return Semantics(
      button: true,
      enabled: open,
      label: size.isEmpty ? name : '$name, $size',
      onTap: open ? onTap : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: open ? 1 : 0.4,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (size.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(size, style: TextStyle(color: colors.mut, fontSize: 14)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of her `grain-change` controls: her text, dimmed and taking no tap while it may not
/// act — on the home and the plan while nothing may start (`nothingStartsNow`), on the
/// check by its own rule (`wholeSwitchActsOnTheCheck`) — or while its own arm has not
/// woken yet.
class GrainChange extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  final bool? toggled;
  final VoidCallback? onFocusLeft;

  const GrainChange({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
    this.toggled,
    this.onFocusLeft,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: open,
      toggled: toggled,
      label: label,
      onTap: open ? onTap : null,
      onDidLoseAccessibilityFocus: onFocusLeft,
      excludeSemantics: true,
      child: Opacity(
        opacity: open ? 1 : 0.4,
        child: GestureDetector(
          onTap: open ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.telha, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

/// «gravar a passagem inteira de uma vez», as her Armed tap reads it.
GrainChange wholeAtOnce(
  SalaSessionState session,
  String language,
  VoidCallback onTap, {
  bool? open,
  void Function(String control)? onFocusLeft,
}) => _armed(
  session,
  'whole',
  recordingHomeLabelFor('wholeAtOnce', language),
  armed: session.overAnApprovedDraft
      ? retroLabelFor('reopenArmed', language)
      : recordingHomeLabelFor('wholeArmed', language),
  needs: session.wholeSwitchArms,
  open: open,
  onTap: onTap,
  onFocusLeft: onFocusLeft,
);

/// «Ensaio Final: juntar os ensaios das cenas», armed only over an approved draft.
GrainChange backToJoin(
  SalaSessionState session,
  String language,
  VoidCallback onTap, {
  void Function(String control)? onFocusLeft,
}) => _armed(
  session,
  'backToJoin',
  recordingHomeLabelFor('backToJoin', language),
  armed: retroLabelFor('reopenArmed', language),
  onTap: onTap,
  onFocusLeft: onFocusLeft,
);

GrainChange _armed(
  SalaSessionState session,
  String control,
  String label, {
  required String armed,
  required VoidCallback onTap,
  bool? open,
  bool needs = false,
  void Function(String control)? onFocusLeft,
}) {
  final arm = session.armedTap;
  final mine = arm?.control == control;
  return GrainChange(
    label: mine ? armed : label,
    toggled: needs ? mine : null,
    open:
        (open ?? !session.nothingStartsNow) &&
        !(mine && arm?.phase == BtRecomeco.armado),
    onTap: onTap,
    onFocusLeft: onFocusLeft == null ? null : () => onFocusLeft(control),
  );
}

/// The recording home's grain controls, under its translate button.
class GrainControls extends ConsumerWidget {
  const GrainControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final open = !session.nothingStartsNow;
    return Column(
      children: [
        if (!session.recordsTheWhole)
          if (session.aPartWasJoined)
            wholeAtOnce(
              session,
              language,
              notifier.recordTheWholePassage,
              onFocusLeft: notifier.accessibilityFocusLeft,
            )
          else
            GrainChange(
              label: recordingHomeLabelFor('wholeInstead', language),
              open: open,
              onTap: notifier.recordTheWholePassageInstead,
            )
        else ...[
          GrainChange(
            label: recordingHomeLabelFor('sceneInstead', language),
            open: open,
            onTap: notifier.recordSceneByScene,
          ),
          if (session.offersTheWayBackToTheJoin)
            backToJoin(
              session,
              language,
              notifier.joinTheScenesAgain,
              onFocusLeft: notifier.accessibilityFocusLeft,
            ),
        ],
      ],
    );
  }
}
