import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';
import 'stage_heading.dart';

class EnsaioView extends ConsumerWidget {
  const EnsaioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final pending = session.ensaio == EnsaioStatus.recorded;
    final titulo = recordingHomeLabelFor(
      session.joined ? 'joinedTitle' : 'title',
      language,
    );

    final scrolling = SizedBox.expand(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            StageHeading(
              stage: SalaStage.ensaio,
              text: titulo,
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
                recordingHomeLabelFor('sub', language),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mut, fontSize: 15, height: 1.35),
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  for (final row in session.sceneRows)
                    _SceneRowView(
                      row: row,
                      session: session,
                      language: language,
                      onRecord: () => notifier.gravarACena(row.number),
                      onListen: () => notifier.ouvirACena(row.number),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FacilitatorCircle(
              size: facilitatorCircleSize,
              halt: session.halt,
              voice: _voice(session),
              tongue: Tongue.motherTongue,
              warning: session.warning ? warningNoticeLabelFor(language) : null,
              semanticLabel: _circleLabel(session, language),
              onTap: notifier.ensaioTap,
              onLongPress: session.canResolveWithPerson
                  ? notifier.resolveWithPerson
                  : null,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoundActionButton(
                  size: 60,
                  mood: session.canPlayTheRehearsal
                      ? ButtonMood.lit
                      : ButtonMood.dimmed,
                  gradient: BeadStyles.wood,
                  semanticLabel: rehearsalLabelFor(
                    session.playPing ? 'pause' : 'play',
                    language,
                  ),
                  onTap: notifier.playTheRehearsal,
                  child: Icon(
                    session.playPing ? LucideIcons.pause : LucideIcons.play,
                    size: 24,
                    color: ShemaBrand.branco,
                  ),
                ),
                const SizedBox(width: 24),
                RoundActionButton(
                  size: 60,
                  mood: pending ? ButtonMood.lit : ButtonMood.dimmed,
                  gradient: BeadStyles.verde,
                  semanticLabel: rehearsalLabelFor('check', language),
                  onTap: notifier.takeKeep,
                  child: const Icon(
                    LucideIcons.check,
                    size: 24,
                    color: ShemaBrand.branco,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FadeUp(
              child: RoundActionButton(
                size: 78,
                mood: session.ensaioDone
                    ? ButtonMood.beckoning
                    : ButtonMood.dimmed,
                gradient: BeadStyles.wood,
                shadows: RoundActionButton.dropShadow,
                halo: ShemaBrand.wood,
                semanticLabel: rehearsalLabelFor('advance', language),
                onTap: notifier.startRetro,
              ),
            ),
            if (session.someScenesWaitForTheirPart) ...[
              const SizedBox(height: 12),
              Text(
                recordingHomeLabelFor('needsAll', language),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.telha, fontSize: 15),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
    return SafeArea(bottom: false, child: scrolling);
  }

  VoiceState _voice(SalaSessionState session) {
    if (session.ensaio == EnsaioStatus.recording && !session.micTaken) {
      return VoiceState.listening;
    }
    if (session.playPing) return VoiceState.speaking;
    return VoiceState.invite;
  }

  String _circleLabel(SalaSessionState session, String language) {
    if (session.ensaio == EnsaioStatus.recording) {
      return rehearsalLabelFor('recording', language);
    }
    if (session.ensaio == EnsaioStatus.recorded) {
      return rehearsalLabelFor('pending', language);
    }
    if (session.parteARegravar != null) {
      return rehearsalLabelFor('pending', language);
    }
    if (session.partes.isNotEmpty) {
      return rehearsalLabelFor('nextPart', language);
    }
    return rehearsalLabelFor('firstPart', language);
  }
}

class _SceneRowView extends StatelessWidget {
  final SceneRow row;
  final SalaSessionState session;
  final String language;
  final VoidCallback onRecord;
  final VoidCallback onListen;

  const _SceneRowView({
    required this.row,
    required this.session,
    required this.language,
    required this.onRecord,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final cena = recordingHomeLabelFor('scene', language, n: row.number);
    final title = row.title;
    final named = title == null ? cena : '$cena — $title';
    final playing = row.current && session.playPing;
    final recording = row.recording && session.ensaio == EnsaioStatus.recording;
    final another =
        session.ensaio != EnsaioStatus.idle && !row.recording ||
        session.needsPerson;
    final mood = row.dimmed || another ? ButtonMood.dimmed : ButtonMood.lit;
    final listens =
        row.dimmed ||
            session.needsPerson ||
            session.ensaio == EnsaioStatus.recording
        ? ButtonMood.dimmed
        : ButtonMood.lit;

    return Semantics(
      container: true,
      selected: row.current,
      label: [
        named,
        if (playing) recordingHomeLabelFor('playing', language),
        if (row.part != null && row.unsent)
          recordingHomeLabelFor('notSent', language),
      ].join(', '),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: row.current ? colors.card : null,
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
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
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cena,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (title != null)
                      Text(
                        title,
                        style: TextStyle(color: colors.mut, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ),
            if (recording)
              _control(
                'stop',
                _glyph(BorderRadius.circular(2)),
                onRecord,
                ButtonMood.lit,
              )
            else if (row.part == null)
              _control(
                'record',
                _glyph(BorderRadius.circular(7)),
                onRecord,
                mood,
              )
            else ...[
              _control(
                'listen',
                Icon(
                  playing ? LucideIcons.pause : LucideIcons.play,
                  size: 18,
                  color: ShemaBrand.branco,
                ),
                onListen,
                listens,
              ),
              const SizedBox(width: 12),
              _control(
                'recordAgain',
                const Icon(
                  LucideIcons.rotateCcw,
                  size: 18,
                  color: ShemaBrand.branco,
                ),
                onRecord,
                mood,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _control(
    String key,
    Widget glyph,
    VoidCallback onTap,
    ButtonMood mood,
  ) => RoundActionButton(
    size: 44,
    mood: mood,
    gradient: BeadStyles.wood,
    semanticLabel: recordingHomeLabelFor(key, language),
    onTap: onTap,
    child: glyph,
  );

  static Widget _glyph(BorderRadius corners) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(color: ShemaBrand.branco, borderRadius: corners),
  );
}
