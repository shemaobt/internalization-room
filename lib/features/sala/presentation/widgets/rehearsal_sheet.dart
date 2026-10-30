import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/scene_rehearsal.dart';
import 'bead_styles.dart';
import 'listen_glyph.dart';
import 'scene_question.dart';
import 'way_back_chevron.dart';

const _rem = 16.0;

/// Her `EnsaioFinalSheet`: one scene's rehearsals, newest first, the one the row holds
/// «✓ em uso» and «usar este» on the others its row offers; over the plan or over the
/// recording home, where «usar este» is the Rehearsal swap.
class RehearsalSheet extends ConsumerWidget {
  final int number;
  final String title;
  final String sub;
  final List<SceneRehearsalRecord> candidates;
  final String? inUseId;
  final String language;
  final bool busy;
  final bool Function(SceneRehearsalRecord) offersToUse;
  final String? Function(SceneRehearsalRecord)? answerOf;
  final String Function(SceneRehearsalRecord)? useLabelOf;
  final bool Function(SceneRehearsalRecord)? armedOf;
  final bool Function(SceneRehearsalRecord)? wakingOf;
  final VoidCallback? onRecordAgain;

  const RehearsalSheet({
    super.key,
    required this.number,
    required this.title,
    required this.sub,
    required this.candidates,
    required this.inUseId,
    required this.language,
    required this.busy,
    required this.offersToUse,
    this.answerOf,
    this.useLabelOf,
    this.armedOf,
    this.wakingOf,
    this.onRecordAgain,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(salaSessionProvider.notifier);
    final listening = ref.watch(salaSessionProvider).planListening;
    final colors = SalaColors.of(context);
    String said(String control) => ensaioFinalPlanLabelFor(control, language);
    final onRecordAgain = this.onRecordAgain;
    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewPaddingOf(context).top;
    final scene = recordingHomeLabelFor('scene', language, n: number);

    final sheet = Padding(
      padding: EdgeInsets.fromLTRB(
        screen.width * 0.08,
        inset + screen.height * 0.12,
        screen.width * 0.08,
        screen.height * 0.12,
      ),
      child: Column(
        children: [
          FocusOnArrival(
            wanted: true,
            child: Semantics(
              header: true,
              label: '$scene — $title',
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      scene,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.verde,
                        fontSize: 1.5 * _rem,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.verdeClaro,
                        fontSize: 0.95 * _rem,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 1.1 * _rem),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.verdeClaro, fontSize: 0.92 * _rem),
          ),
          const SizedBox(height: 1.7 * _rem),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Column(
              spacing: 0.55 * _rem,
              children: [
                for (final candidate in candidates)
                  _SheetLine(
                    rehearsal: candidate,
                    inUse: candidate.rehearsalId == inUseId,
                    offersToUse: offersToUse(candidate),
                    note: _cannotEnter(candidate),
                    answer: answerOf?.call(candidate),
                    useLabel: useLabelOf?.call(candidate) ?? said('useThis'),
                    armed: armedOf?.call(candidate) ?? false,
                    waking: wakingOf?.call(candidate) ?? false,
                    playing: listening?.rehearsalId == candidate.rehearsalId,
                    language: language,
                    busy: busy,
                    onPlay: () =>
                        notifier.playARehearsal(candidate.rehearsalId),
                    onUse: () =>
                        notifier.useThisRehearsal(candidate.rehearsalId),
                  ),
              ],
            ),
          ),
          if (onRecordAgain != null) ...[
            const SizedBox(height: 1.2 * _rem),
            Opacity(
              opacity: 0.7,
              child: TextButton(
                onPressed: busy ? null : onRecordAgain,
                child: Text(
                  said('recordSceneAgain'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.verdeClaro,
                    fontSize: 0.84 * _rem,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.verdeClaro,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Stack(
          children: [
            SizedBox(width: screen.width, child: sheet),
            Positioned(
              left: screen.width * 0.06 - 2,
              top: inset + screen.height * 0.05 - 2,
              child: Semantics(
                button: true,
                enabled: !busy,
                label: said('back'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: busy ? null : notifier.closeTheRehearsalSheet,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: const Opacity(
                      opacity: 0.6,
                      child: Center(child: WayBackChevron()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _cannotEnter(SceneRehearsalRecord rehearsal) =>
      rehearsal.rehearsalId != inUseId && !rehearsal.usable
      ? ensaioFinalPlanLabelFor('cannotEnter', language)
      : null;
}

class _SheetLine extends StatelessWidget {
  final SceneRehearsalRecord rehearsal;
  final bool inUse;
  final bool offersToUse;
  final String? note;
  final String? answer;
  final String useLabel;
  final bool armed;
  final bool waking;
  final bool playing;
  final String language;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onUse;

  const _SheetLine({
    required this.rehearsal,
    required this.inUse,
    required this.offersToUse,
    required this.note,
    required this.answer,
    required this.useLabel,
    required this.armed,
    required this.waking,
    required this.playing,
    required this.language,
    required this.busy,
    required this.onPlay,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    String said(String control) => ensaioFinalPlanLabelFor(control, language);
    final line = sheetLineFor(rehearsal, language);
    final note = this.note;
    final answer = this.answer;
    final usable = !busy && !waking;

    return Semantics(
      container: true,
      selected: inUse,
      label: line,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 0.55 * _rem,
          horizontal: 0.75 * _rem,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color.fromRGBO(236, 234, 220, .05)
              : const Color.fromRGBO(255, 255, 255, .4),
          border: Border.all(
            color: inUse ? colors.azul : colors.areia,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 0.75 * _rem,
          children: [
            Row(
              children: [
                Semantics(
                  selected: playing,
                  child: RoundActionButton(
                    size: 44,
                    gradient: BeadStyles.wood,
                    mood: busy ? ButtonMood.dimmed : ButtonMood.lit,
                    semanticLabel: '${said('listen')} — $line',
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
                const SizedBox(width: 0.75 * _rem),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          line,
                          style: TextStyle(
                            color: colors.verdeClaro,
                            fontSize: 0.78 * _rem,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (note != null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 0.1 * _rem),
                            child: Text(
                              note,
                              style: TextStyle(
                                color: colors.telha,
                                fontSize: 0.76 * _rem,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 0.8 * _rem,
              runSpacing: 0.4 * _rem,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (inUse)
                  Text(
                    '✓ ${said('inUse')}',
                    style: TextStyle(
                      color: colors.verde,
                      fontSize: 0.8 * _rem,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (offersToUse)
                  Semantics(
                    button: true,
                    enabled: usable,
                    toggled: armed,
                    label: '$useLabel — $line',
                    onTap: usable ? onUse : null,
                    excludeSemantics: true,
                    child: Opacity(
                      opacity: busy
                          ? 0.35
                          : waking
                          ? 0.55
                          : 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: usable ? onUse : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Align(
                            widthFactor: 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 0.5 * _rem,
                                horizontal: 1.1 * _rem,
                              ),
                              decoration: BoxDecoration(
                                color: armed ? colors.telha : null,
                                border: Border.all(
                                  color: armed ? colors.telha : colors.areia,
                                  width: 1.4,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                useLabel,
                                style: TextStyle(
                                  color: armed
                                      ? colors.paper
                                      : colors.verdeClaro,
                                  fontSize: 0.84 * _rem,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (answer != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      answer,
                      style: TextStyle(
                        color: colors.telha,
                        fontSize: 0.76 * _rem,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
