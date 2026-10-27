import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/ensaio_final_plan.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_question.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'grain_choice_view.dart';
import 'rehearsal_sheet.dart';
import 'scene_question.dart';
import 'stage_heading.dart';

/// Her Ensaio Final plan: «pensando…» while the room is read, then her heading and line,
/// a row per scene, the card of the Unlabelled rehearsals, «juntar as cenas e ouvir» and
/// «Gravar cena por cena» at the foot; or the Rehearsal sheet of one scene.
class EnsaioFinalPlanView extends ConsumerWidget {
  const EnsaioFinalPlanView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);

    final (read, sessionId) = (session.ensaioFinalPlan, session.sessionId);
    if (read case GrainAsked(:final elsewhere)) {
      return GrainChoiceView(elsewhere: elsewhere);
    }
    if (read is! PlanRead || sessionId == null) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text(
            ensaioFinalPlanLabelFor('thinking', language),
            style: TextStyle(color: colors.mut, fontSize: 15),
          ),
        ),
      );
    }
    final rows = planRowsOf(read, sessionId, session.planChoices);
    final joining = session.joining;
    final idle = !session.planBusy;
    final sheet = rows
        .where((row) => row.scene.sceneId == session.planSheet)
        .firstOrNull;
    if (sheet != null) {
      return RehearsalSheet(
        number: sheet.number,
        title: sheet.scene.title,
        sub: ensaioFinalPlanLabelFor('swap', language),
        candidates: sheet.candidates,
        inUseId: sheet.chosen?.rehearsalId,
        language: language,
        busy: session.planBusy,
        offersToUse: sheet.offersToUse,
        onRecordAgain: notifier.rehearseThisSceneAgain,
      );
    }
    final unlabelled = unlabelledRehearsalsOf(read, sessionId).firstOrNull;
    return SafeArea(
      bottom: false,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              StageHeading(
                stage: SalaStage.ensaio,
                text: ensaioFinalPlanLabelFor('title', language),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  ensaioFinalPlanLabelFor('sub', language),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.mut,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
              if (joining != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    ensaioFinalPlanLabelFor(
                      'joining',
                      language,
                      i: joining,
                      k: read.scenes.length,
                    ),
                    style: TextStyle(color: colors.ink, fontSize: 15),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    for (final row in rows)
                      _PlanRowView(
                        row: row,
                        language: language,
                        outcome: session.joinRows[row.number],
                        idle: idle,
                        onPlay: () =>
                            notifier.playThePlanRow(row.scene.sceneId),
                        onSwap: () =>
                            notifier.swapTheRehearsal(row.scene.sceneId),
                        onRetry: () => notifier.retryTheJoin(row.number),
                      ),
                  ],
                ),
              ),
              if (unlabelled != null)
                _UnlabelledCard(
                  rehearsal: unlabelled,
                  scenes: read.scenes,
                  language: language,
                  busy: session.planBusy,
                  failed: session.labelLine,
                ),
              if (planHoldsARehearsal(read, sessionId)) ...[
                const SizedBox(height: 24),
                RoundActionButton(
                  size: 78,
                  mood: idle && canJoin(rows, held: session.heldScenes)
                      ? ButtonMood.beckoning
                      : ButtonMood.dimmed,
                  gradient: BeadStyles.wood,
                  shadows: RoundActionButton.dropShadow,
                  halo: ShemaBrand.wood,
                  semanticLabel: ensaioFinalPlanLabelFor('join', language),
                  onTap: notifier.joinTheScenes,
                ),
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: Text(
                    ensaioFinalPlanLabelFor('join', language),
                    style: TextStyle(color: colors.ink, fontSize: 15),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              wholeAtOnce(session, language, notifier.recordTheWholePassage),
              TextButton(
                onPressed: idle && !session.grainSwitching
                    ? notifier.recordSceneByScene
                    : null,
                child: Text(
                  ensaioFinalPlanLabelFor('sceneByScene', language),
                  style: TextStyle(color: colors.telha, fontSize: 15),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanRowView extends StatelessWidget {
  final PlanRow row;
  final String language;
  final JoinRow? outcome;
  final bool idle;
  final VoidCallback onPlay;
  final VoidCallback onSwap;
  final VoidCallback onRetry;

  const _PlanRowView({
    required this.row,
    required this.language,
    required this.outcome,
    required this.idle,
    required this.onPlay,
    required this.onSwap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final cena = recordingHomeLabelFor('scene', language, n: row.number);
    final chosen = row.chosen;
    final facts = chosen == null ? null : planRowFactsFor(chosen, language);
    final note = switch ((outcome, row.note)) {
      (JoinRow.cannotEnter, _) || (_, PlanNote.cannotEnter) =>
        ensaioFinalPlanLabelFor('cannotEnter', language),
      (_, PlanNote.missing) => ensaioFinalPlanLabelFor('missing', language),
      _ => null,
    };
    final retry = ensaioFinalPlanLabelFor('joinRetry', language);

    return Semantics(
      container: true,
      label: '$cena — ${row.scene.title}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 32,
                  child: ExcludeSemantics(
                    child: Text(
                      '${row.number}',
                      style: TextStyle(color: colors.mut, fontSize: 15),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          cena,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Text(
                          row.scene.title,
                          style: TextStyle(color: colors.mut, fontSize: 14),
                        ),
                      ),
                      if (row.joined)
                        Text(
                          '✓',
                          style: TextStyle(color: colors.ink, fontSize: 15),
                        ),
                      if (facts != null)
                        Text(
                          facts,
                          style: TextStyle(color: colors.mut, fontSize: 14),
                        ),
                      if (row.partial)
                        Text(
                          ensaioFinalPlanLabelFor('partial', language),
                          style: TextStyle(color: colors.telha, fontSize: 14),
                        ),
                      if (note != null)
                        Text(
                          note,
                          style: TextStyle(color: colors.telha, fontSize: 14),
                        ),
                    ],
                  ),
                ),
                if (facts != null)
                  RoundActionButton(
                    size: 44,
                    gradient: BeadStyles.wood,
                    semanticLabel:
                        '${ensaioFinalPlanLabelFor('listen', language)} — $facts',
                    mood: idle ? ButtonMood.lit : ButtonMood.dimmed,
                    onTap: onPlay,
                    child: const Icon(
                      LucideIcons.play,
                      size: 18,
                      color: ShemaBrand.branco,
                    ),
                  ),
              ],
            ),
            if (outcome == JoinRow.retry)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Semantics(
                  button: true,
                  label: '$retry — $cena',
                  onTap: idle ? onRetry : null,
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: idle ? onRetry : null,
                    child: Text(
                      retry,
                      style: TextStyle(color: colors.telha, fontSize: 15),
                    ),
                  ),
                ),
              ),
            if (row.canSwap)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: Semantics(
                  button: true,
                  label: '${ensaioFinalPlanLabelFor('swap', language)} — $cena',
                  onTap: idle ? onSwap : null,
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: idle ? onSwap : null,
                    child: Text(
                      ensaioFinalPlanLabelFor('swap', language),
                      style: TextStyle(color: colors.telha, fontSize: 15),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Her card «De que cena é este ensaio?»: the oldest Unlabelled rehearsal, its play and
/// facts, and one scene button per scene of the passage, none highlighted.
class _UnlabelledCard extends ConsumerWidget {
  final SceneRehearsalRecord rehearsal;
  final List<Scene> scenes;
  final String language;
  final bool busy;
  final bool failed;

  const _UnlabelledCard({
    required this.rehearsal,
    required this.scenes,
    required this.language,
    required this.busy,
    required this.failed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    String said(String control) => ensaioFinalPlanLabelFor(control, language);
    final facts = planRowFactsFor(rehearsal, language);

    return Semantics(
      container: true,
      label: said('whichScene'),
      child: Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Text(
                said('whichScene'),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RoundActionButton(
                  size: 44,
                  gradient: BeadStyles.wood,
                  mood: busy ? ButtonMood.dimmed : ButtonMood.lit,
                  semanticLabel: '${said('listen')} — $facts',
                  onTap: () => notifier.playARehearsal(rehearsal.rehearsalId),
                  child: const Icon(
                    LucideIcons.play,
                    size: 18,
                    color: ShemaBrand.branco,
                  ),
                ),
                const SizedBox(width: 12),
                Text(facts, style: TextStyle(color: colors.mut, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            for (final (i, scene) in scenes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  enabled: !busy,
                  child: Opacity(
                    opacity: busy ? 0.5 : 1,
                    child: SceneButton(
                      label: sceneButtonLabelFor(i + 1, scene.title, language),
                      number: i + 1,
                      highlighted: false,
                      onTap: () => notifier.labelTheRehearsal(
                        rehearsal.rehearsalId,
                        scene.sceneId,
                      ),
                    ),
                  ),
                ),
              ),
            if (failed)
              Semantics(
                liveRegion: true,
                child: Text(
                  said('labelFailed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.telha, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
