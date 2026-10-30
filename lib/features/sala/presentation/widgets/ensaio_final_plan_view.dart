import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/ensaio_final_plan.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_question.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'grain_choice_view.dart';
import 'listen_glyph.dart';
import 'rehearsal_sheet.dart';
import 'scene_question.dart';
import 'stage_heading.dart';
import 'unsent_notice.dart';
import 'way_back_button.dart';

/// Her Ensaio Final plan: «pensando…» while the room is read, then her heading and line,
/// a row per scene, the card of the Unlabelled rehearsals, «juntar as cenas e ouvir» and
/// «Gravar cena por cena» at the foot; or the Rehearsal sheet of one scene.
class EnsaioFinalPlanView extends ConsumerStatefulWidget {
  const EnsaioFinalPlanView({super.key});

  @override
  ConsumerState<EnsaioFinalPlanView> createState() =>
      _EnsaioFinalPlanViewState();
}

class _EnsaioFinalPlanViewState extends ConsumerState<EnsaioFinalPlanView> {
  int _cardAt = 0;
  String? _lastLabelled;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);

    final (read, sessionId) = (session.ensaioFinalPlan, session.sessionId);
    if (read case GrainAsked(:final elsewhere)) {
      return GrainChoiceView(elsewhere: elsewhere);
    }
    if (read is! PlanRead || sessionId == null) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox.expand(
            child: Stack(
              children: [
                Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      ensaioFinalPlanLabelFor('thinking', language),
                      style: TextStyle(color: colors.mut, fontSize: 15),
                    ),
                  ),
                ),
                const WayBackButton(stage: SalaStage.ensaio, top: 8),
              ],
            ),
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
    final unlabelledOnes = unlabelledRehearsalsOf(read, sessionId);
    final at = unlabelledOnes.isEmpty
        ? 0
        : min(_cardAt, unlabelledOnes.length - 1);
    final unlabelled = unlabelledOnes.isEmpty ? null : unlabelledOnes[at];
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
              UnsentNotice(
                session: session,
                language: language,
                onSend: notifier.enviarACena,
              ),
              if (session.sceneLine == SceneLine.diskFailed)
                Semantics(
                  label: sceneRehearsalLabelFor('diskFailed', language),
                  liveRegion: true,
                  child: const SizedBox.shrink(),
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
                        playing:
                            session.planListening?.rehearsalId ==
                            row.chosen?.rehearsalId,
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
                  playing:
                      session.planListening?.rehearsalId ==
                      unlabelled.rehearsalId,
                  failed:
                      session.labelLine &&
                      _lastLabelled == unlabelled.rehearsalId,
                  previous: at > 0 ? unlabelledOnes[at - 1] : null,
                  next: at + 1 < unlabelledOnes.length
                      ? unlabelledOnes[at + 1]
                      : null,
                  onLabel: (sceneId) {
                    _lastLabelled = unlabelled.rehearsalId;
                    notifier.labelTheRehearsal(unlabelled.rehearsalId, sceneId);
                  },
                  onPrevious: () => setState(() => _cardAt = at - 1),
                  onNext: () => setState(() => _cardAt = at + 1),
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
              wholeAtOnce(
                session,
                language,
                notifier.recordTheWholePassage,
                onFocusLeft: notifier.accessibilityFocusLeft,
              ),
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
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onSwap;
  final VoidCallback onRetry;

  const _PlanRowView({
    required this.row,
    required this.language,
    required this.outcome,
    required this.idle,
    required this.playing,
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
                  Semantics(
                    selected: playing,
                    child: RoundActionButton(
                      size: 44,
                      gradient: BeadStyles.wood,
                      semanticLabel:
                          '${ensaioFinalPlanLabelFor('listen', language)} — $facts',
                      mood: idle ? ButtonMood.lit : ButtonMood.dimmed,
                      onTap: onPlay,
                      child: CustomPaint(
                        size: const Size.square(18),
                        painter: ListenGlyphPainter(
                          glyph: playing ? ListenGlyph.pause : ListenGlyph.play,
                          ink: ShemaBrand.branco,
                        ),
                      ),
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

/// Her card «De que cena é este ensaio?»: one of the Unlabelled rehearsals, with previous
/// and next to step to its neighbours, its play and facts, and one scene button per scene of the passage, none highlighted.
class _UnlabelledCard extends ConsumerWidget {
  final SceneRehearsalRecord rehearsal;
  final List<Scene> scenes;
  final String language;
  final bool busy;
  final bool playing;
  final bool failed;
  final SceneRehearsalRecord? previous;
  final SceneRehearsalRecord? next;
  final void Function(String sceneId) onLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _UnlabelledCard({
    required this.rehearsal,
    required this.scenes,
    required this.language,
    required this.busy,
    required this.playing,
    required this.failed,
    required this.previous,
    required this.next,
    required this.onLabel,
    required this.onPrevious,
    required this.onNext,
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
            Semantics(
              container: true,
              header: true,
              headingLevel: 2,
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
                if (previous case final neighbour?) ...[
                  _StepControl(
                    toward: neighbour,
                    language: language,
                    busy: busy,
                    forward: false,
                    onTap: onPrevious,
                  ),
                  const SizedBox(width: 12),
                ],
                Semantics(
                  selected: playing,
                  child: RoundActionButton(
                    size: 44,
                    gradient: BeadStyles.wood,
                    mood: busy ? ButtonMood.dimmed : ButtonMood.lit,
                    semanticLabel: '${said('listen')} — $facts',
                    onTap: () => notifier.playARehearsal(rehearsal.rehearsalId),
                    child: CustomPaint(
                      size: const Size.square(18),
                      painter: ListenGlyphPainter(
                        glyph: playing ? ListenGlyph.pause : ListenGlyph.play,
                        ink: ShemaBrand.branco,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    facts,
                    style: TextStyle(color: colors.mut, fontSize: 14),
                  ),
                ),
                if (next case final neighbour?) ...[
                  const SizedBox(width: 12),
                  _StepControl(
                    toward: neighbour,
                    language: language,
                    busy: busy,
                    forward: true,
                    onTap: onNext,
                  ),
                ],
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
                      onTap: () => onLabel(scene.sceneId),
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

/// Her 40 px `.ctl` circle on the card: a chevron named by the row text of the rehearsal
/// it steps to.
class _StepControl extends StatelessWidget {
  final SceneRehearsalRecord toward;
  final String language;
  final bool busy;
  final bool forward;
  final VoidCallback onTap;

  const _StepControl({
    required this.toward,
    required this.language,
    required this.busy,
    required this.forward,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: !busy,
      label: planRowFactsFor(toward, language),
      onTap: busy ? null : onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: busy ? 0.5 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.areia.withValues(alpha: 0.25),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size.square(20),
                painter: _StepChevronPainter(
                  forward: forward,
                  ink: colors.verde,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChevronPainter extends CustomPainter {
  final bool forward;
  final Color ink;

  const _StepChevronPainter({required this.forward, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final path = forward
        ? (Path()
            ..moveTo(9 * unit, 5 * unit)
            ..relativeLineTo(7 * unit, 7 * unit)
            ..relativeLineTo(-7 * unit, 7 * unit))
        : (Path()
            ..moveTo(15 * unit, 5 * unit)
            ..relativeLineTo(-7 * unit, 7 * unit)
            ..relativeLineTo(7 * unit, 7 * unit));
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StepChevronPainter old) =>
      old.forward != forward || old.ink != ink;
}
