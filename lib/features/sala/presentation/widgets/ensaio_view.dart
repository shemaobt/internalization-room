import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/bt_finding.dart';
import '../../domain/ensaio_final_plan.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/kept_take.dart';
import '../../domain/machine.dart' show TheKeep;
import '../../domain/scene_rehearsal.dart';
import '../../domain/session_state.dart';
import '../../domain/station.dart';
import 'approve_button.dart';
import 'bead_styles.dart';
import 'ensaio_final_plan_view.dart';
import 'external_check_button.dart';
import 'grain_choice_view.dart';
import 'listeners_line.dart';
import 'motion.dart';
import 'ouvir_tudo_view.dart';
import 'rehearsal_sheet.dart';
import 'saved_screen.dart';
import 'stage_heading.dart';
import 'stop_control.dart';

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
    if (session.ouvirTudo != OuvirTudo.fora) return const OuvirTudoView();
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
            if (session.rehearsalsElsewhere && session.partes.isEmpty)
              _Aviso(recordingHomeLabelFor('elsewhere', language)),
            if (session.aTakeFromAnEarlierVisitWaits)
              _Aviso(recordingHomeLabelFor('pending', language)),
            if (session.btFraseDevida != null)
              _Aviso(sceneRehearsalLabelFor('spliceFail', language)),
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
                            onStop: notifier.stopTheSend,
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
                  if (session.approveOffered) ...[
                    const SizedBox(height: 12),
                    ApproveButton(live: session.canApprove && !frozen),
                  ],
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
                  if (session.btAviso case final aviso?
                      when (aviso == BtAviso.checagemFalhou ||
                              aviso == BtAviso.checagemNaoAbre) &&
                          session.stage == SalaStage.ensaio) ...[
                    const SizedBox(height: 12),
                    Text(
                      retroLabelFor(switch (aviso) {
                        BtAviso.checagemNaoAbre => 'externalCheckNotFinal',
                        _ => 'externalCheckFailed',
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
                    ListenersLine(aprovado.listeners),
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
            if (session.canOuvirTudo)
              Semantics(
                button: true,
                label: recordingHomeLabelFor('listenAllAria', language),
                onTap: notifier.ouvirTudo,
                excludeSemantics: true,
                child: TextButton(
                  onPressed: notifier.ouvirTudo,
                  child: Text(
                    recordingHomeLabelFor('listenAll', language),
                    style: TextStyle(color: colors.telha, fontSize: 15),
                  ),
                ),
              ),
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
      answerOf: (rehearsal) => switch (session.swapLine) {
        (:final rehearsalId, :final cannotEnter)
            when rehearsalId == rehearsal.rehearsalId =>
          said(cannotEnter ? 'cannotEnter' : 'joinRetry'),
        _ => null,
      },
      useLabelOf: (rehearsal) => armed(rehearsal) && session.overAnApprovedDraft
          ? retroLabelFor('reopenArmed', language)
          : said('useThis'),
      armedOf: armed,
      wakingOf: (rehearsal) =>
          armed(rehearsal) && session.armedTap?.phase == BtRecomeco.armado,
      onRecordAgain: notifier.rehearseThisSceneAgain,
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;

  const _Aviso(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Semantics(
        liveRegion: true,
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(color: SalaColors.of(context).telha, fontSize: 15),
        ),
      ),
    ),
  );
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
  final void Function(TheKeep keep) onStop;
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
    required this.onStop,
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
    final playing = row.playing && session.playPing;
    final recording = row.recording && session.ensaio == EnsaioStatus.recording;
    final frozen = session.bringingBack != null;
    final another =
        session.ensaio != EnsaioStatus.idle && !row.recording ||
        session.needsPerson ||
        frozen;
    final mood = another ? ButtonMood.dimmed : ButtonMood.lit;
    final listens =
        session.needsPerson ||
            session.ensaio == EnsaioStatus.recording ||
            frozen
        ? ButtonMood.dimmed
        : ButtonMood.lit;

    return Semantics(
      container: true,
      label: [
        named,
        if (playing) recordingHomeLabelFor('playing', language),
      ].join(', '),
      value: row.part == null ? null : ['✓', ?mark].join(' '),
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
                if (row.beyondTheScenes)
                  const SizedBox.shrink()
                else if (recording)
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
                  if (!row.playsTheGoneTake) ...[
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
                  ],
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
            ?_takeState(recording, cena, colors),
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
    if (session.trechoChamado(session.btFraseQueAguarda)?.parte == parte) {
      return sceneRehearsalLabelFor('awaiting', language);
    }
    return null;
  }

  Widget? _takeState(bool recording, String cena, SalaColors colors) {
    String words(String key) => recordingHomeLabelFor(key, language);
    final inTheAir = row.inTheAir;
    final sendNow = switch (row.unsent) {
      final unsent? => sendNowLabelFor(unsent, cena, language),
      null => null,
    };
    final said = switch (row.unsent) {
      _ when recording => _said(words('recording'), colors),
      _ when inTheAir != null => Row(
        children: [
          _said(words('sending'), colors),
          StopControl(
            key: ValueKey(inTheAir.row),
            since: inTheAir.keep.since,
            label: words('stopSending'),
            aria: words('stopSendingAria'),
            color: colors.telha,
            onStop: () => onStop(inTheAir.keep),
          ),
        ],
      ),
      _ when sendNow != null => _tap(
        sendNow,
        words('sendAria'),
        onSend,
        colors,
      ),
      UnsentPart(failure: SendFailure.failed) => _tap(
        words('failed'),
        words('retryAria'),
        onSend,
        colors,
      ),
      UnsentPart(failure: SendFailure.gone) => _said(words('lost'), colors),
      UnsentPart(failure: SendFailure.tooLarge) => _said(
        words('tooLarge'),
        colors,
      ),
      UnsentPart(failure: SendFailure.refused) => _said(
        words('refused'),
        colors,
      ),
      UnsentPart() => _said(words('sending'), colors),
      null when row.saved => _said('✓ ${words('saved')}', colors),
      null => null,
    };
    if (said == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: said,
    );
  }

  static Widget _said(String words, SalaColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(words, style: TextStyle(color: colors.telha, fontSize: 15)),
  );

  Widget _tap(
    String visible,
    String aria,
    VoidCallback onTap,
    SalaColors colors,
  ) => Semantics(
    button: true,
    enabled: session.bringingBack == null ? null : false,
    label: aria,
    onTap: onTap,
    excludeSemantics: true,
    child: TextButton(
      onPressed: onTap,
      child: Text(visible, style: TextStyle(color: colors.telha, fontSize: 15)),
    ),
  );

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
    final failed = session.bringBackFailed;
    if (failed == null || failed.cena != row.number) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 4),
      child: Semantics(
        liveRegion: true,
        child: Text(
          failed.cannotEnter
              ? ensaioFinalPlanLabelFor('cannotEnter', language)
              : recordingHomeLabelFor('bringBackFailed', language),
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
