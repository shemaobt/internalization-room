import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
import '../../domain/session_state.dart';
import '../../domain/station.dart';
import 'bead_styles.dart';
import 'ensaio_final_plan_view.dart';
import 'facilitator_circle.dart';
import 'grain_choice_view.dart';
import 'motion.dart';
import 'stage_heading.dart';

class EnsaioView extends ConsumerWidget {
  const EnsaioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (session.station case Ensaio(step: EnsaioStep.plan)) {
      return const EnsaioFinalPlanView();
    }
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final pending = session.ensaio == EnsaioStatus.recorded;
    final titulo = recordingHomeLabelFor(
      session.joined ? 'joinedTitle' : 'title',
      language,
    );

    final frozen = session.bringingBack != null;
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
            if (session.rehearsalsElsewhere && session.partes.isEmpty) ...[
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
            if (session.aTakeFromAnEarlierVisitWaits) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    recordingHomeLabelFor('pending', language),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.telha, fontSize: 15),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            IgnorePointer(
              ignoring: frozen,
              child: Column(
                children: [
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
                            onSend: () => notifier.enviarACena(row.number),
                            onBringBack: () =>
                                notifier.trazerDeVoltaAsTraducoes(row.number),
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
                    warning: session.warning
                        ? warningNoticeLabelFor(language)
                        : null,
                    semanticLabel: _circleLabel(session, language),
                    enabled: !frozen,
                    onTap: notifier.ensaioTap,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RoundActionButton(
                        size: 60,
                        mood: session.canPlayTheRehearsal && !frozen
                            ? ButtonMood.lit
                            : ButtonMood.dimmed,
                        gradient: BeadStyles.wood,
                        semanticLabel: recordingHomeLabelFor(
                          session.playPing ? 'stop' : 'listen',
                          language,
                        ),
                        onTap: notifier.playTheRehearsal,
                        child: Icon(
                          session.playPing
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          size: 24,
                          color: ShemaBrand.branco,
                        ),
                      ),
                      const SizedBox(width: 24),
                      RoundActionButton(
                        size: 60,
                        mood: pending && !frozen
                            ? ButtonMood.lit
                            : ButtonMood.dimmed,
                        gradient: BeadStyles.verde,
                        semanticLabel: recordingHomeLabelFor(
                          'sendAria',
                          language,
                        ),
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
                      mood: session.ensaioDone && !frozen
                          ? ButtonMood.beckoning
                          : ButtonMood.dimmed,
                      gradient: BeadStyles.wood,
                      shadows: RoundActionButton.dropShadow,
                      halo: ShemaBrand.wood,
                      semanticLabel: recordingHomeLabelFor(
                        session.joined ? 'listenAndCheck' : 'translate',
                        language,
                      ),
                      onTap: notifier.startRetro,
                    ),
                  ),
                ],
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
            const SizedBox(height: 16),
            const GrainControls(),
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

  String _circleLabel(SalaSessionState session, String language) =>
      recordingHomeLabelFor(switch (session.ensaio) {
        EnsaioStatus.recording => 'stop',
        EnsaioStatus.recorded => 'recordAgain',
        EnsaioStatus.idle when session.parteARegravar != null => 'recordAgain',
        EnsaioStatus.idle => 'record',
      }, language);
}

class _SceneRowView extends StatelessWidget {
  final SceneRow row;
  final SalaSessionState session;
  final String language;
  final VoidCallback onRecord;
  final VoidCallback onListen;
  final VoidCallback onSend;
  final VoidCallback onBringBack;

  const _SceneRowView({
    required this.row,
    required this.session,
    required this.language,
    required this.onRecord,
    required this.onListen,
    required this.onSend,
    required this.onBringBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final whole = session.recordsTheWhole;
    final cena = whole
        ? recordingHomeLabelFor('wholePassage', language)
        : recordingHomeLabelFor('scene', language, n: row.number);
    final title = row.title;
    final named = title == null ? cena : '$cena — $title';
    final playing = row.current && session.playPing;
    final recording = row.recording && session.ensaio == EnsaioStatus.recording;
    final frozen = session.bringingBack != null;
    final another =
        session.ensaio != EnsaioStatus.idle && !row.recording ||
        session.needsPerson ||
        frozen;
    final mood = row.dimmed || another ? ButtonMood.dimmed : ButtonMood.lit;
    final listens =
        row.dimmed ||
            row.away == PartAway.coming ||
            row.away == PartAway.lost ||
            session.needsPerson ||
            session.ensaio == EnsaioStatus.recording ||
            frozen
        ? ButtonMood.dimmed
        : ButtonMood.lit;

    return Semantics(
      container: true,
      selected: row.current,
      label: [
        named,
        if (playing) recordingHomeLabelFor('playing', language),
      ].join(', '),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: row.current ? colors.card : null,
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
                      whole ? '' : '${row.number}',
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
            ?_unsentControl(row.unsent, cena, colors),
            ?_bringBackControl(cena, colors),
            ?_bringBackFailed(colors),
          ],
        ),
      ),
    );
  }

  Widget? _unsentControl(UnsentPart? unsent, String cena, SalaColors colors) {
    if (unsent == null) return null;
    final (visible, aria) = switch (unsent) {
      UnsentPart(fromAnEarlierVisit: true, :final length) => (
        [
          cena,
          if (length != null) ' · ${minutesAndSecondsOf(length)}',
          ' — ${recordingHomeLabelFor('sendNow', language)}',
        ].join(),
        recordingHomeLabelFor('sendAria', language),
      ),
      UnsentPart(failed: true) => (
        recordingHomeLabelFor('failed', language),
        recordingHomeLabelFor('retryAria', language),
      ),
      _ => (null, null),
    };
    if (visible == null || aria == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: Semantics(
        button: true,
        enabled: session.bringingBack == null ? null : false,
        label: aria,
        onTap: onSend,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onSend,
          child: Text(
            visible,
            style: TextStyle(color: colors.telha, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget? _bringBackControl(String cena, SalaColors colors) {
    if (!session.toBringBack.contains(row.number)) return null;
    final control = 'bringBack:${row.number}';
    final armedTap = session.armedTap;
    final label = recordingHomeLabelFor(
      armedTap?.control == control ? 'bringBackArmed' : 'bringBack',
      language,
    );
    final asleep =
        armedTap?.control == control && armedTap?.phase == BtRecomeco.armado;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: Semantics(
        button: true,
        enabled: !asleep && session.bringingBack == null,
        label: '$label — $cena',
        onTap: onBringBack,
        excludeSemantics: true,
        child: Opacity(
          opacity: asleep ? 0.4 : 1,
          child: TextButton(
            onPressed: onBringBack,
            child: Text(
              label,
              style: TextStyle(color: colors.mut, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _bringBackFailed(SalaColors colors) {
    if (session.bringBackFailed != row.number) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: Semantics(
        liveRegion: true,
        child: Text(
          recordingHomeLabelFor('bringBackFailed', language),
          style: TextStyle(color: colors.telha, fontSize: 15),
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
