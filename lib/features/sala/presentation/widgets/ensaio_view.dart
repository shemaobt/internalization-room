import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/bt_finding.dart';
import '../../domain/ensaio_final_plan.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import '../../domain/station.dart';
import 'bead_styles.dart';
import 'ensaio_final_plan_view.dart';
import 'external_check_button.dart';
import 'facilitator_circle.dart';
import 'grain_choice_view.dart';
import 'motion.dart';
import 'rehearsal_sheet.dart';
import 'saved_screen.dart';
import 'stage_heading.dart';

class EnsaioView extends ConsumerWidget {
  const EnsaioView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (session.station case Ensaio(step: EnsaioStep.plan)) {
      return const EnsaioFinalPlanView();
    }
    if (session.ensaioSalvo case final versao?) {
      return SavedScreen(version: versao);
    }
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    final colors = SalaColors.of(context);
    final homeRows = session.homeRows;
    final sheet = homeRows.values
        .where((row) => row.plan.scene.sceneId == session.homeSheet)
        .firstOrNull;
    if (sheet != null) return _homeSheet(session, notifier, sheet, language);
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
                            home: homeRows[row.number]?.home,
                            session: session,
                            language: language,
                            onSheet: () =>
                                notifier.openTheHomeSheet(row.number),
                            onRecord: () => notifier.gravarACena(row.number),
                            onListen: () => notifier.ouvirACena(row.number),
                            onSend: () => notifier.enviarACena(row.number),
                            onBringBack: () =>
                                notifier.trazerDeVoltaAsTraducoes(row.number),
                          ),
                      ],
                    ),
                  ),
                  if (session.btChecked) ...[
                    const SizedBox(height: 12),
                    Text(
                      '✓ ${retroLabelFor('translated', language)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.ink, fontSize: 17),
                    ),
                  ],
                  if (session.hearNewScene) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        ensaioFinalPlanLabelFor('hearNewScene', language),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.telha, fontSize: 15),
                      ),
                    ),
                  ],
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
                      if (session.approveOffered) ...[
                        const SizedBox(width: 24),
                        RoundActionButton(
                          size: 60,
                          mood: session.canApprove && !frozen
                              ? ButtonMood.lit
                              : ButtonMood.dimmed,
                          gradient: BeadStyles.verde,
                          semanticLabel: retroLabelFor('approve', language),
                          onTap: notifier.aprovarRascunhoFinal,
                          child: const Icon(
                            LucideIcons.check,
                            size: 24,
                            color: ShemaBrand.branco,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (session.btRecusa case final recusa?
                      when session.stage == SalaStage.ensaio) ...[
                    const SizedBox(height: 12),
                    Text(
                      retroLabelFor(switch (recusa) {
                        CheckRefusal.partUnheard => 'partUnheard',
                        CheckRefusal.notConferida => 'notConferida',
                        _ => 'checkFailed',
                      }, language),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.telha, fontSize: 15),
                    ),
                  ],
                  if (session.approvedOnTheHome case final aprovado?) ...[
                    const SizedBox(height: 12),
                    Text(
                      retroLabelFor(
                        'approvedDraft',
                        language,
                        n: aprovado.version,
                      ),
                      style: TextStyle(color: colors.ink, fontSize: 17),
                    ),
                    const SizedBox(height: 12),
                    const ExternalCheckButton(),
                  ],
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

  Widget _homeSheet(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    ({PlanRow plan, HomeRow home}) row,
    String language,
  ) {
    final (:plan, :home) = row;
    String said(String control) => ensaioFinalPlanLabelFor(control, language);
    bool armed(SceneRehearsalRecord rehearsal) =>
        session.armedTap?.control == swapControl(plan.scene.sceneId, rehearsal);
    return RehearsalSheet(
      number: plan.number,
      title: plan.scene.title,
      sub: said(home.useScene ? 'useScene' : 'swap'),
      candidates: plan.candidates,
      inUseId: home.inUse,
      language: language,
      busy: session.homeBusy,
      offersToUse: (rehearsal) => offersToSwapIn(home, rehearsal),
      noteOf: (rehearsal) => switch (session.swapLine) {
        (:final rehearsalId, :final cannotEnter)
            when rehearsalId == rehearsal.rehearsalId =>
          said(cannotEnter ? 'cannotEnter' : 'joinRetry'),
        _ => null,
      },
      useLabelOf: (rehearsal) => armed(rehearsal) && session.overAnApprovedDraft
          ? retroLabelFor('reopenArmed', language)
          : said('useThis'),
      wakingOf: (rehearsal) =>
          armed(rehearsal) && session.armedTap?.phase == BtRecomeco.armado,
      onRecordAgain: notifier.rehearseThisSceneAgain,
    );
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
  final HomeRow? home;
  final SalaSessionState session;
  final String language;
  final VoidCallback onSheet;
  final VoidCallback onRecord;
  final VoidCallback onListen;
  final VoidCallback onSend;
  final VoidCallback onBringBack;

  const _SceneRowView({
    required this.row,
    required this.home,
    required this.session,
    required this.language,
    required this.onSheet,
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
    final mark = _mark();
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
      value: row.part == null && mark == null
          ? null
          : [if (row.part != null) '✓', ?mark].join(' '),
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
                        Row(
                          children: [
                            Text(
                              cena,
                              style: TextStyle(
                                color: colors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (row.part != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                '✓',
                                style: TextStyle(
                                  color: colors.mut,
                                  fontSize: 17,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (title != null)
                          Text(
                            title,
                            style: TextStyle(color: colors.mut, fontSize: 14),
                          ),
                        if (mark != null)
                          Text(
                            mark,
                            style: TextStyle(color: colors.telha, fontSize: 14),
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
            ?_sheetDoor(cena, colors),
          ],
        ),
      ),
    );
  }

  String? _mark() {
    final parte = session.partIndexOf(row.number);
    if (parte == null) return null;
    if (session.btTrechosRegravados.any((trecho) => trecho.parte == parte)) {
      return retroLabelFor('stale', language);
    }
    return null;
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

  Widget? _sheetDoor(String cena, SalaColors colors) {
    final home = this.home;
    if (home == null ||
        !(home.swap || home.useScene) ||
        session.ensaio != EnsaioStatus.idle) {
      return null;
    }
    final label = ensaioFinalPlanLabelFor(
      home.swap ? 'swap' : 'useScene',
      language,
    );
    final open =
        session.homeBusy || session.needsPerson || session.bringingBack != null
        ? null
        : onSheet;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: Semantics(
        button: true,
        enabled: open != null,
        label: '$label — $cena',
        onTap: open,
        excludeSemantics: true,
        child: TextButton(
          onPressed: open,
          child: Text(
            label,
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
