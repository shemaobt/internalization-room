import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../domain/approval_answer.dart';
import '../domain/bt_finding.dart';
import '../domain/capture_guard.dart';
import '../domain/escuta_das_partes.dart';
import '../domain/facilitator_script.dart';
import '../domain/hand_reply.dart';
import '../domain/kept_take.dart';
import '../domain/passagem.dart';
import '../domain/coverage.dart';
import '../domain/coverage_event.dart';
import '../domain/room_reach.dart';
import '../domain/session_snapshot.dart';
import '../domain/session_state.dart';
import '../domain/spoken_line.dart';
import '../domain/turn_clock.dart';
import '../domain/turn_result.dart';
import 'connectivity_service.dart';
import 'facilitator_voice_service.dart';
import 'finished_passages.dart';
import 'hand_inbox_repository.dart';
import 'linked_team.dart';
import 'mic_permission.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';
import 'room_repository.dart';
import 'take_upload_queue.dart';
import 'work_in_progress.dart';

final roomPollDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

final coverageFallbackDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

const _clockSegments = <(String, String, String)>[
  ('recorder_stop', 'stop', 'recorder'),
  ('stop_to_answer', 'stop', 'answer'),
  ('answer_to_clip', 'answer', 'clip'),
  ('clip_to_sound', 'clip', 'sound'),
  ('sound_to_beads', 'sound', 'beads'),
  ('health_to_session', 'health', 'session'),
  ('session_to_open', 'session', 'open'),
  ('open_to_sound', 'open', 'sound'),
];

const _unplayableTurnsBeforeNeedsPerson = 3;
const _roomFailuresBeforeNeedsPerson = 3;

/// How many times the room may answer nothing before the app stops waiting for it.
const _slowAnswersBeforeGivingUp = 3;

/// How many times the recorder may fail to start in a row before the room calls a
/// person — mirroring `micFails` in her client.
const _captureFailsBeforeAPerson = 2;

/// How many times in a row the room may answer broken while resuming a stored session
/// before the id is dropped, the way a 404 drops it.
const _resumeFailuresBeforeForgetting = 2;

const _umInstanteOuvido = Duration(milliseconds: 400);

/// What a reopening found where the team left off.
enum _Resume {
  /// The station they left, standing again, with the rehearsal under it.
  landed,

  /// Nothing behind this passage to come back to: it opens at the conversa.
  nothingToRestore,

  /// The room could not hand the rehearsal back. A person is called and the resume point
  /// is left exactly as it was, so the next opening tries again.
  halted,

  /// Nobody is waiting for this answer any more — the team left the passage, or the
  /// container went. It is not a reading of what the room holds and must not be read as
  /// one.
  abandoned,
}

final busyStateCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 330),
);

final resendMarginProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Starts the clock `_sendTheTake` reads its own wait from. A provider, not a bare
/// `Stopwatch()`, so a test can drive the wait on a fake clock instead of the wall one —
/// the only real clock left on the resend-versus-watchdog race.
final turnElapsedSourceProvider = Provider<Duration Function() Function()>(
  (ref) => () {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  },
);

/// How often an open microphone touches the room again. The shared client lets an idle
/// connection go at 90 s and only the team's tap ends a take, so a take longer than that
/// would otherwise hand its upload a connection that already lapsed. A provider, not a
/// constant, so a test can reach the second touch without waiting a minute; null, like
/// the busy ceiling, leaves only the first touch, for tests that end with the microphone
/// open and cannot outlive a pending timer.
final connectionRewarmIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 60),
);

/// Slack added to a clip's own length before the room decides the playback is lost. A
/// provider, not a constant, because a ceiling nothing can shrink is a ceiling no test
/// can reach — which is how the paused-clip bug shipped.
final clipGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

final playbackCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 6),
);

/// The tap boundary the conversa recorder is held to: a take under 1,200 ms or 800 bytes
/// never becomes a question for the room.
final captureGuardProvider = Provider<CaptureGuard>(
  (ref) => const CaptureGuard(),
);

/// The book the room is serving. One string, in one place, so another book is a config
/// change rather than a code change — the catalogue route takes it as a parameter.
final bookProvider = Provider<String>((ref) => 'Ruth');

final devLanguageProvider = NotifierProvider<DevLanguage, String?>(
  DevLanguage.new,
);

class DevLanguage extends Notifier<String?> {
  @override
  String? build() => null;

  void choose(String language) {
    if (!Env.devPularFases) return;
    if (!languages.contains(language)) return;
    state = language;
  }

  String next(String current) =>
      languages[(languages.indexOf(current) + 1) % languages.length];
}

final roomLanguageProvider = Provider<String>((ref) {
  final chosen = ref.watch(devLanguageProvider);
  if (chosen != null) return chosen;
  return languageFor(
    WidgetsBinding.instance.platformDispatcher.locales.map(
      (locale) => locale.languageCode,
    ),
  );
});

final fimLingerProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 14),
);

final entradaSettleProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);

final roomRetryBackoffProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ],
);

/// The holes a refused approval names that this room has somewhere to take the team.
///
/// Declared in the order the room opens them — the one place that order lives — which is
/// not the order the gate raises them in: the gate lists the check's own errand before the
/// holes that have ground to stand on, and a team sent to ask for the verdict again over
/// a part nobody told back is sent to be refused again.
///
/// A code no arm of [_portaDaRecusa] names has no door, and the switch's own default sends
/// it to a person.
enum _PortaDaRecusa { trecho, parteNaoContada, parteNaoOuvida, conferir }

_PortaDaRecusa? _portaDaRecusa(String blocker) => switch (blocker) {
  'untold_stretch' => _PortaDaRecusa.trecho,
  'untold_part' => _PortaDaRecusa.parteNaoContada,
  'playback_did_not_cover_the_clip' => _PortaDaRecusa.parteNaoOuvida,
  'telling_back_not_checked' ||
  'telling_back_never_analysed' => _PortaDaRecusa.conferir,
  _ => null,
};

class SalaSessionNotifier extends Notifier<SalaSessionState> {
  final Map<String, Timer> _timers = {};
  String? _haltWatched;
  int _epoch = 0;
  int _unplayableTurns = 0;
  int _roomFailures = 0;
  List<String>? _fileiraDaUltimaRecusa;
  final Set<String> _contadasSemResposta = {};
  int _resumeFailures = 0;

  /// When and in what language the session now open was created, so a row rewritten by
  /// a later stage advance carries them instead of going blank the moment the team leaves
  /// the conversa. A resume judges by the language; the date is the record of when the
  /// session was born, and nothing decides by it (ADR 0031).
  DateTime? _sessionSavedAt;
  String? _sessionLanguage;
  int _slowAnswers = 0;
  int _calmTurns = 0;
  int _retryStep = 0;
  bool _noticeSpoken = false;
  bool _conviteOpened = false;
  bool _returning = false;
  bool _strandedSpoken = false;
  bool _personAsked = false;
  bool _askingForAPerson = false;
  int _personAskStep = 0;
  int _ackSpoken = 0;
  DateTime? _listeningSince;
  bool _recordingStarting = false;
  int _starts = 0;
  VoiceState _voiceBeforeQuestion = VoiceState.invite;
  String? _emCurso;
  Trecho? get _trechoTraduzidoDeNovo => state.btTrechoTraduzidoDeNovo;
  set _trechoTraduzidoDeNovo(Trecho? trecho) => state = trecho == null
      ? state.copyWith(clearTrechoTraduzidoDeNovo: true)
      : state.copyWith(btTrechoTraduzidoDeNovo: trecho);

  final Set<String> _traducoesGuardadas = {};

  /// The outbox row a guarded translation landed on, by the path it was guarded for.
  ///
  /// Populated once `_guard` has actually enqueued the file, so a discard that races
  /// ahead of that enqueue finds nothing to withdraw — the same window `_semNome`
  /// already lives with for the rehearsal's own rows.
  final Map<String, PendingTake> _traducaoNaFila = {};

  /// The clip is paused. `_onPlaybackComplete` deliberately survives a pause — the resume
  /// still has to be able to end the part — so it cannot be what tells a ceiling whether
  /// there is any sound left to measure.
  bool _clipHeld = false;
  Duration? _cabecaForaDoPlayer;
  int _captureFails = 0;

  /// Whether the part currently chosen has ever actually gone in the air.
  ///
  /// False only between the entry picking a part and `_tocarParteDaRetro` landing it —
  /// the one window nothing else in state tells apart from a part a hold left silent
  /// partway through.
  bool _parteJaTocou = false;

  /// What a halt found the room doing, read before `_silenceTheRoom` clears every flag
  /// that would answer the question afterwards.
  bool _soavaQuandoParou = false;
  Duration get _trechoStart => state.btCursor;

  /// Moving the cursor always asks the head-since-cursor question again: whatever the
  /// deadline answered about the ground before this move says nothing about the ground
  /// after it. A landing's own `openings` event schedules the deadline fresh, against a
  /// position that belongs to this cursor; a retell's own walk-back moves the cursor with
  /// no clip of its own in the air, and leaves the fact false until the room lands
  /// somewhere again — the label reads none of this while a retell is armed, so nothing
  /// asks the fact in the meantime.
  set _trechoStart(Duration cursor) =>
      state = state.copyWith(btCursor: cursor, btOuvidoAlemDoCursor: false);

  Duration get _trechoEnd => state.btCorte;
  set _trechoEnd(Duration corte) => state = state.copyWith(btCorte: corte);

  int get _parteTocando => state.btParte;
  set _parteTocando(int parte) => state = state.copyWith(btParte: parte);

  /// The part in the air is the one the verdict named in a refusal — unheard or untold —
  /// and hearing it to its end hands the finish back.
  ///
  /// The finish was already the team's — it is how the refusal was asked for — and the
  /// refusal only takes it away for the length of this one part. Without this, a refusal
  /// naming any part but the last made the team cross and listen through everything after
  /// it to get the press back, which is hearing the story again: the very thing the jump
  /// over the ground already told exists to spare them.
  bool _pousadaNaParteApontadaPelaRecusa = false;

  /// The approval is in the air, and the approval has landed.
  ///
  /// Two, not one: the first stops a second press from minting a second request while the
  /// first is still out, and the second stops one after the answer is in, when the room is
  /// already speaking the line and closing the necklace.
  bool _aprovando = false;
  bool _aprovada = false;

  /// How long each part of the rehearsal turned out to be, by the file the part is kept
  /// as and never by where the part sits in the row.
  ///
  /// A mend hands a part a new file, and a length written down under the old one's place
  /// would outlive it. Keyed by the file, a swapped part needs only its own measurement,
  /// and the listening ledger — keyed by the file too — cannot disagree with the ruler
  /// about which recording a length belongs to.
  final Map<String, int> _tamanhoDaParteMs = {};
  final EscutaDasPartes _escuta = EscutaDasPartes();
  int _desdeMs = 0;
  VoidCallback? _depoisDaPausa;
  List<(String, (Duration, Duration)?, int)> _ensaioATocar = const [];
  String? _panoramaSessionId;

  /// The opening turn this instance is asking for, minted once and carried across every
  /// retry of it — a resend under a fresh id is a fresh id the server has never seen, so
  /// it runs the whole pipeline again instead of answering with what it already produced.
  String? _openTurnId;
  bool _openingOwed = false;
  TurnClock? _pendingClock;
  TurnClock? _coverageClock;

  String? _pendingTakePath;
  StreamSubscription<void>? _playbackDone;
  StreamSubscription<void>? _playbackFailed;
  StreamSubscription<void>? _playbackOpened;
  StreamSubscription<void>? _networkWatch;
  Timer? _ladder;
  StreamSubscription<CoverageEvent>? _coverageWatch;
  String? _coverageSessionId;
  String? _awaitingCoverageTurnId;
  String? _resolvedCoverageTurnId;
  String? _coverageReopenedForTurnId;
  bool _doneSeenMidTurn = false;
  StreamSubscription<bool>? _micWatch;
  VoidCallback? _onPlaybackComplete;
  VoidCallback? _onPlaybackFailed;

  FacilitatorVoiceService get _voice => ref.read(facilitatorVoiceProvider);
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);
  PlaybackRepository get _playback => ref.read(playbackRepositoryProvider);
  HandInboxRepository get _inbox => ref.read(handInboxRepositoryProvider);
  RoomRepository get _room => ref.read(roomRepositoryProvider);
  LinkedTeam get _ledger => ref.read(linkedTeamProvider);
  TakeUploadQueue get _takes => ref.read(takeUploadQueueProvider);
  ConnectivityService get _network => ref.read(connectivityServiceProvider);
  FinishedPassages get _feitas => ref.read(finishedPassagesProvider);
  WorkInProgress get _emAberto => ref.read(workInProgressProvider);
  CaptureGuard get _captureGuard => ref.read(captureGuardProvider);

  String get _book => ref.read(bookProvider);

  String get _lingua => ref.read(roomLanguageProvider);

  /// The room is gone and its providers with it.
  ///
  /// Half this class is fire-and-forget: `_guard` queues a take and counts what is left
  /// long after the gesture that started it returned. Reading a provider once the
  /// container is disposed throws, and the throw lands in no one's `catch` — it showed up
  /// as two tests that failed only on a slower machine, which is the same thing happening
  /// where nobody was looking.
  bool _gone = false;

  /// Whether the halt the room is standing in is a resume that could not fetch the
  /// rehearsal.
  ///
  /// Letting the team out of it has to try the resume again. Handed the conversa of the
  /// session they were resuming — which is where they stand while it runs — the next
  /// rehearsal they record goes up over the one the room is already holding, which is the
  /// very thing the fetch exists to prevent.
  bool _haltedResuming = false;

  @override
  SalaSessionState build() {
    ref.onDispose(() {
      _gone = true;
      _cancelTimers();
      _ladder?.cancel();
      unawaited(_playbackDone?.cancel());
      unawaited(_playbackFailed?.cancel());
      unawaited(_playbackOpened?.cancel());
      unawaited(_networkWatch?.cancel());
      unawaited(_micWatch?.cancel());
      unawaited(_coverageWatch?.cancel());
    });
    return const SalaSessionState();
  }

  void sayTheMicIsBlocked() =>
      unawaited(_voice.playAsset(micBlockedAsset(_lingua)));

  void _after(String key, Duration delay, VoidCallback fn) {
    _timers[key]?.cancel();
    final epoch = _epoch;
    _timers[key] = Timer(delay, () {
      if (epoch == _epoch) fn();
    });
  }

  void _cancelTimers() {
    _epoch++;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    // The mark says the room is being watched out of a halt, and the beat it names has
    // just been cancelled with the rest. Left standing, it told the next halt in the same
    // session that a watch was already running — a room that lost the network under a
    // halt came back stopped, unwatched, and the desk's mark never reached it again.
    _haltWatched = null;
  }

  void _clearAll() {
    _cancelTimers();
    _openTurnId = null;
    _openingOwed = false;
    _doneSeenMidTurn = false;
    state = state.copyWith(clearLastSpoken: true, clearParteARegravar: true);
    _silenceTheRoom();
    unawaited(_recorder.discard());
  }

  /// What every gesture that moves the room to another action does first: it silences
  /// the rehearsal player and the Guide's voice, writes down what the team heard, and
  /// clears every flag that says something is sounding, so the next tap finds nothing
  /// playing. Only a play/pause toggle on the sound itself is exempt.
  ///
  /// One place, because the room has two independent players and thirty gestures that
  /// move it: silencing inside each gesture is what left the last sound playing under
  /// the next one.
  ///
  /// [holdTheClip] for the gestures that come back to the very part they leave — the
  /// scissors, the circle that opens and closes a capture, telling a stretch again, and
  /// the check. A hold silences the rehearsal just as well and is what keeps the clip
  /// open: stopped, the room loses the length that the listening ceiling and the end of
  /// the part are both measured against.
  ///
  /// It never cancels the room's timers, never bumps the epoch and never touches the
  /// recorder: those belong to [_clearAll], which leaves a passage rather than moving
  /// inside one.
  void _silenceTheRoom({bool holdTheClip = false}) {
    if (holdTheClip) {
      // A hold writes the playhead down before it stops playing, so the ledger reads it
      // afterwards, exactly as it always has.
      _holdClip();
      _anotarOQueFoiOuvido();
    } else {
      // A stop does not. just_audio only extrapolates `position` while the player is
      // playing, so a read taken after a stop answers with the stale place the clip was
      // opened at — and the span would be written short, or dropped for good.
      _anotarOQueFoiOuvido();
      _clipHeld = false;
      // What the clip owed the room dies with the clip. Left armed, the ceiling of a
      // part that was still loading fires a whole clip later, on a room that has long
      // since moved on, and ends a part under the team.
      _onPlaybackComplete = null;
      _onPlaybackFailed = null;
      _timers.remove('playback')?.cancel();
      _timers.remove('cursor')?.cancel();
      unawaited(_playback.stop());
    }
    unawaited(_voice.stop());
    state = state.copyWith(
      btTrechoTocando: false,
      btTrechoPausada: false,
      btRetroTocando: false,
      btRetroPausada: false,
      clearContaEscolhida: true,
      playPing: false,
      takePaused: false,
      clearParteDoEnsaioTocando: true,
    );
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _play(
    String path, {
    Duration from = Duration.zero,
    VoidCallback? onComplete,
    VoidCallback? onFailed,
  }) {
    _clipHeld = false;
    _onPlaybackComplete = onComplete;
    _onPlaybackFailed = onFailed;
    _listenForTheEnd();
    unawaited(_playback.play(path, from: from));
    _watchPlayback(clipStillOpening: true);
  }

  void _listenForTheEnd() {
    _playbackDone ??= _playback.completions.listen((_) => _releasePlayback());
    _playbackFailed ??= _playback.failures.listen(
      (_) => _cannotPlayTheirOwnAudio(),
    );
    _playbackOpened ??= _playback.openings.listen((_) {
      _watchPlayback();
      _medirAParteNoAr();
      // Only the part's own clip carries a cursor: a bead or a stretch replay opens
      // through the same event, with no cursor of its own to arm a deadline against.
      if (state.btClipRodando) _armCursorDeadline();
    });
  }

  void _cannotPlayTheirOwnAudio() {
    _timers.remove('playback')?.cancel();
    _onPlaybackComplete = null;
    final undo = _onPlaybackFailed;
    _onPlaybackFailed = null;
    undo?.call();
    _haltForAPerson();
  }

  void _releasePlayback() {
    _timers.remove('playback')?.cancel();
    final callback = _onPlaybackComplete;
    _onPlaybackComplete = null;
    _onPlaybackFailed = null;
    callback?.call();
  }

  void _watchPlayback({bool clipStillOpening = false}) {
    if (_onPlaybackComplete == null || _clipHeld) return;
    final length = clipStillOpening ? null : _playback.playingLength;
    final ceiling = length == null
        ? ref.read(playbackCeilingProvider)
        : _leftToHear(length);
    if (ceiling == null) return;
    _after('playback', ceiling, _releasePlayback);
  }

  /// The ceiling counts what is left of the clip, never its whole length: the retro pauses
  /// the take for as long as the team needs to tell a stretch back, and a wall-clock ceiling
  /// would end the clip mid-listening — after which nothing resumes it.
  Duration _leftToHear(Duration length) {
    final grace = ref.read(clipGraceProvider);
    final left = length - _playback.position;
    return left.isNegative ? grace : left + grace;
  }

  void _holdClip() {
    _clipHeld = true;
    _timers.remove('playback')?.cancel();
    unawaited(_playback.pause());
    // A held head has stopped moving, and a wall-clock deadline armed against it would
    // fire on schedule over a clip that never reached the cursor. Checked now instead,
    // against wherever the head actually stands.
    _checkCursorNow();
  }

  void _letTheClipRun() {
    _clipHeld = false;
    unawaited(_playback.resume());
    _watchPlayback();
    if (state.btClipRodando) _armCursorDeadline();
  }

  /// Straight to speaking for a line already on the tablet.
  ///
  /// `thinking` is there to cover a download, and a replay has nothing to download: the
  /// circle went clay and then orange for a line that starts the instant it is asked for.
  Future<void> _readyToRepeat(String url, String fixedLine) async {
    if (fixedLine.isNotEmpty || await _voice.holds(url)) return;
    await _readyToSpeak(url, fixedLine);
  }

  /// Bring the line down first, then let the circle show it speaking.
  ///
  /// The download rides the room's own turn budget, not a ceiling of its own, and every
  /// caller used to enter `speaking` before it landed — the room rippled as if it were
  /// talking while nothing came out. `thinking` is what this actually is, and it is also
  /// what makes the screen refuse a touch that would start a second line on top of this
  /// one.
  Future<void> _readyToSpeak(String url, String fixedLine) async {
    if (fixedLine.isEmpty) {
      state = state.copyWith(voice: VoiceState.thinking);
      _watchBusyState();
      await _voice.ready(url);
    }
  }

  /// Say a line, and remember it as the one "ouvir de novo" gives back.
  ///
  /// [remember] is false for a canned line. A fail-safe is what the room says when it could
  /// not compose an answer, and letting it take the place of the last real line meant the
  /// replay handed a team "vamos parar um instante aqui" instead of the scene they were
  /// asking to hear again. The room repeats what it actually told them.
  Future<bool> _speak(
    String url,
    String fixedLine, {
    String panoramaUrl = '',
    bool remember = true,
    void Function()? onSoundStart,
  }) async {
    final epoch = _epoch;
    final played = fixedLine.isEmpty
        ? await _voice.play(url, onSoundStart: onSoundStart)
        : await _voice.playAsset(
            fixedLineAsset(fixedLine, _lingua),
            onSoundStart: onSoundStart,
          );
    if (played && remember && epoch == _epoch) {
      state = state.copyWith(
        lastSpoken: SpokenLine(
          url: url,
          fixedLine: fixedLine,
          panoramaUrl: panoramaUrl,
        ),
      );
    }
    return played;
  }

  Future<void> hearAgain() async {
    if (!state.canHearAgain) return;
    await _repeatLastSpoken(state.lastSpoken!);
  }

  /// Repeat the narrator's last line on the circle in `findings`, instead of the stretch
  /// the findings' play already offers.
  ///
  /// [canHearAgain] hides its button for the whole retro stage, so this reaches
  /// [_repeatLastSpoken] on its own guard: a stored line and a room not already speaking
  /// one. Nothing plays when there is none — a fail-safe verdict is never remembered, and
  /// the circle answers a tap on it with nothing rather than falling back to the trecho.
  Future<void> _repeatTheFinding() async {
    final line = state.lastSpoken;
    if (line == null || state.voice != VoiceState.invite) return;
    await _repeatLastSpoken(line);
  }

  Future<void> _repeatLastSpoken(SpokenLine line) async {
    final epoch = _epoch;
    await _readyToRepeat(line.url, line.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    try {
      final played = await _speak(
        line.url,
        line.fixedLine,
        panoramaUrl: line.panoramaUrl,
      );
      if (epoch != _epoch) return;
      if (!played) return _registerUnplayableTurn(leavesTeamTalk: false);
      _unplayableTurns = 0;
      state = state.copyWith(voice: VoiceState.invite);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
  }

  /// The whole opening again — the shape of the passage, and then the scene.
  ///
  /// A short tap gives back the scene, which is what a team asks for most of the time. The
  /// movement before it was said once and would otherwise be gone, so it lives here, under
  /// a press held. The necklace comes off the cord and is strung again as the scene
  /// arrives: the same movement backwards, which is how the room says what just happened
  /// without a word for it.
  Future<void> hearTheWholeOpening() async {
    final line = state.lastSpoken;
    if (line == null || !state.canHearAgain) return;
    if (!line.toldInTwoMovements) {
      await hearAgain();
      return;
    }
    final epoch = _epoch;
    state = state.copyWith(contasEnfiadas: false);
    await _readyToRepeat(line.panoramaUrl, '');
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    try {
      final played = await _speakTheFirstMovement(line.panoramaUrl, epoch);
      if (epoch != _epoch) return;
      if (!played) return _registerUnplayableTurn(leavesTeamTalk: false);
      _watchBusyState();
      final scene = await _speak(line.url, '', panoramaUrl: line.panoramaUrl);
      if (epoch != _epoch) return;
      if (!scene) return _registerUnplayableTurn(leavesTeamTalk: false);
      _unplayableTurns = 0;
      state = state.copyWith(voice: VoiceState.invite);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
  }

  Future<void> _voiceTurn(
    TurnResult turn,
    int epoch, {
    TurnClock? clock,
    void Function()? onSoundStart,
  }) async {
    if (epoch != _epoch) return;
    state = state.copyWith(coverage: turn.coverage);
    clock?.mark('answer');
    _awaitCoverageSettle(turn, clock: clock);
    _scheduleInboxPoll();
    await _readyToSpeak(
      turn.toldInTwoMovements ? turn.panoramaUrl : turn.audioUrl,
      turn.fixedLine,
    );
    if (epoch != _epoch) return;
    clock?.mark('clip');
    if (turn.audioUrl.isEmpty && turn.fixedLine.isEmpty) {
      _registerUnplayableTurn();
      return;
    }
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    final played = turn.toldInTwoMovements
        ? await _speakTheOpening(turn, epoch, onSoundStart: onSoundStart)
        : await _speak(
            turn.audioUrl,
            turn.fixedLine,
            remember: !turn.usedFailSafe,
            onSoundStart: onSoundStart,
          );
    if (epoch != _epoch) return;
    if (!played) {
      _registerUnplayableTurn();
      return;
    }
    _settleNetworkHealth(calm: !turn.degraded);
    _resumeFailures = 0;
    _openTurnId = null;
    _openingOwed = false;
    state = state.copyWith(
      voice: turn.done || _doneSeenMidTurn
          ? VoiceState.done
          : VoiceState.invite,
      peerCue: turn.peerCue,
    );
    _doneSeenMidTurn = false;
    _awaitCoverageSettle(turn, clock: clock);
    _scheduleInboxPoll();
  }

  /// The opening said in the two movements the room wrote it in.
  ///
  /// The necklace waits for the second one: the beads belong to the scene, and hanging
  /// them over the passage's own shape said the work was already laid out. Whatever
  /// happens to the scene's clip, the beads are handed over — a necklace held back by a
  /// failure would never come.
  Future<bool> _speakTheOpening(
    TurnResult turn,
    int epoch, {
    void Function()? onSoundStart,
  }) async {
    state = state.copyWith(contasEnfiadas: false);
    // Brought in while the first movement is being spoken, so the second follows it
    // without a gap — and awaited before it is asked for, so the download and the playing
    // are never two callers racing for the same file.
    final arriving = _voice.fetch(turn.sceneUrl);
    final opened = await _speakTheFirstMovement(
      turn.panoramaUrl,
      epoch,
      onSoundStart: onSoundStart,
    );
    if (epoch != _epoch) return opened;
    if (!opened) return false;
    await arriving;
    if (epoch != _epoch) return true;
    // The voice stays `speaking` across both: one opening in two breaths, not a turn that
    // ended and another that began. Dropping to `thinking` in between showed the team the
    // room had stopped talking while it was still mid-sentence.
    _watchBusyState();
    return _speak(turn.sceneUrl, '', panoramaUrl: turn.panoramaUrl);
  }

  /// The passage's own shape, with the beads handed over however it ends.
  ///
  /// Both openings take the necklace off the cord before it and string it again after — a
  /// line that played, one that did not, and one the room failed to serve alike. Handed
  /// over only past the call, a failure the room threw jumped the hand-over, and the
  /// necklace stayed off until the team left the passage.
  Future<bool> _speakTheFirstMovement(
    String panoramaUrl,
    int epoch, {
    void Function()? onSoundStart,
  }) async {
    try {
      return await _speak(
        panoramaUrl,
        '',
        panoramaUrl: panoramaUrl,
        onSoundStart: onSoundStart,
      );
    } finally {
      if (epoch == _epoch) state = state.copyWith(contasEnfiadas: true);
    }
  }

  void _registerUnplayableTurn({bool leavesTeamTalk = true}) {
    _openTurnId = null;
    _unplayableTurns++;
    _calmTurns = 0;
    if (_unplayableTurns >= _unplayableTurnsBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(
      voice: VoiceState.invite,
      peerCue: leavesTeamTalk ? false : null,
    );
  }

  /// The build has no address or no key, so nothing the team does can work.
  ///
  /// Reached before the room opens, because the alternative is discovering it one failed
  /// request at a time — and `Env`'s throw is an `Error`, which the network layer's
  /// catches all miss. That is why this halt never asks: touching `Env` for a device-scoped
  /// ask would throw that same uncatchable `Error`, and this method is itself the only
  /// signal that there is no server to reach.
  void haltForABrokenBuild() => _haltForAPerson(reachable: false);

  void _haltForAPerson({
    bool sessionIsGone = false,
    bool reachable = true,
    bool read = false,
    bool wheelExhausted = false,
  }) {
    // A lift only replays what this halt actually caught sounding — a part, a bead
    // replay, or a part chosen but never landed yet. A held part, or one already at its
    // end with nothing else sounding over it, answers false on its own: an ended part
    // clears `btClipRodando` and, having played once, `_parteJaTocou` is already true.
    // Read before the silence, because that is what clears the very flags this asks
    // about.
    _soavaQuandoParou =
        state.stage == SalaStage.retro &&
        (state.btClipRodando ||
            state.btTrechoTocando ||
            state.btRetroTocando ||
            !_parteJaTocou);
    _silenceTheRoom();
    if (state.btPhase == BtPhase.capturing) {
      unawaited(_recorder.discard());
      _undoTheListening();
    }
    _leaveThinking();
    state = state.copyWith(
      voice: VoiceState.needsPerson,
      peerCue: false,
      clearSession: sessionIsGone,
      // Set on every call, never left standing from an earlier one: a stall entering
      // the panorama spoke also halts without leaving the Choice's stage, and lifting
      // that halt must retry with the same turn id, not reload the wheel out from
      // under it.
      wheelHalted: wheelExhausted,
    );
    if (read) {
      _watchTheHalt();
      return;
    }
    if (reachable) _tellTheRoomAPersonIsNeeded();
    if (_personAsked) _watchTheHalt();
  }

  /// A blocking halt is lifted by a facilitator at the desk, not by this tablet.
  ///
  /// The only way out used to be a long press, which asked nobody: the team let
  /// themselves out of a room no one had looked at, and a room already attended stayed
  /// shut until somebody thought to hold the screen.
  void _watchTheHalt() {
    final sessionId = state.sessionId;
    if (sessionId == null || _haltWatched == sessionId) return;
    _haltWatched = sessionId;
    _beatTheWatch();
  }

  /// Starting the watch again on a halt already being watched would push the next read
  /// away by a whole beat, every time. A settle scheduled by an older turn still lands
  /// inside a halt, finds `needs_person`, and halts a second time for the same reason —
  /// so the answer that lets the team out would keep being deferred by the room noticing
  /// again what it already knew.
  void _beatTheWatch() {
    _after('halt', ref.read(roomPollDelayProvider), () {
      unawaited(_askIfTheHaltIsOver());
    });
  }

  Future<void> _askIfTheHaltIsOver() async {
    final sessionId = _haltWatched;
    if (sessionId == null) return;
    final epoch = _epoch;
    try {
      final snapshot = await _room.fetchState(sessionId);
      if (epoch != _epoch || _haltWatched != sessionId) return;
      state = state.copyWith(warning: snapshot.halt == HaltKind.warning);
      if (snapshot.needsPerson) {
        if (!state.needsPerson) _haltForAPerson(read: true);
      } else {
        if (state.needsPerson) {
          _comeBack();
          _leaveTheHalt();
        }
        if (!state.warning) {
          // A warning walks no voice, so there is nothing to hand back: the field going
          // out is the whole of it, and the halt's way out would give the team an invite
          // over a clip already playing.
          _endTheWatch();
          return;
        }
      }
    } on SessionGone {
      // There is no longer a session to be let out of, so there is nothing left to ask:
      // the room keeps the halt and the long press is the way out of it, as it is for a
      // build with no session at all.
      if (epoch != _epoch || _haltWatched != sessionId) return;
      _endTheWatch();
      state = state.copyWith(clearSession: true);
      return;
    } on Exception {
      // A read that failed says nothing about the halt. Asking again on the same beat is
      // the whole answer; counting it as a second halt would talk over the first.
      if (epoch != _epoch || _haltWatched != sessionId) return;
    }
    _beatTheWatch();
  }

  void _tellTheRoomAPersonIsNeeded() {
    if (_personAsked || _askingForAPerson) return;
    if (state.sessionId == null) {
      unawaited(_askForAPersonWithoutASession());
    } else {
      unawaited(_askForAPerson());
    }
  }

  /// The call is only made when the server says it has it.
  ///
  /// Most of the ways into a halt are bad network and a room that is not answering, so
  /// the call goes out at the worst possible moment to be delivered — and a lost one left
  /// no trace anywhere: the session never entered the desk's queue, no facilitator was
  /// told, and nobody arrived to tap the screen that is the only thing that asked again.
  Future<void> _askForAPerson() async {
    final sessionId = state.sessionId;
    if (sessionId == null || _personAsked || _askingForAPerson) return;
    _askingForAPerson = true;
    var sessionGone = false;
    try {
      await _room.askForAPerson(sessionId);
      // The watch begins here and not at the halt: releasing on a state read that went
      // out before the call landed would let the team out of a room whose halt the desk
      // has not heard of yet, and nobody would ever come.
      if (!_gone && state.needsPerson) {
        _personAsked = true;
        _watchTheHalt();
      }
    } on SessionGone {
      // The server has already said this session is gone; insisting on the same route
      // just spends the backoff. Clearing it here — the way the state poll's SessionGone
      // path does — is what gives the device-scoped ask its turn.
      sessionGone = true;
    } on Exception {
      _keepAskingForAPerson(_askForAPerson);
    } finally {
      _askingForAPerson = false;
    }
    // A person may have arrived and resolved the halt while this ask was still in
    // flight — `resolveWithPerson()` cannot cancel it. A late 404 must not reopen a
    // halt nobody is in anymore, the same guard the two branches around this one lean on.
    if (sessionGone && !_gone && state.needsPerson) {
      _haltForAPerson(sessionIsGone: true);
    }
  }

  /// The same ask, for a halt with no session to name: the server forgot it, or the
  /// build never opened one. Asks by the tablet's own device id, from the link ledger.
  Future<void> _askForAPersonWithoutASession() async {
    if (_personAsked || _askingForAPerson) return;
    _askingForAPerson = true;
    try {
      final deviceId = (await _ledger.read()).deviceId;
      if (deviceId == null || _gone) return;
      await _room.askForAPersonWithoutASession(deviceId);
      if (!_gone && state.needsPerson) _personAsked = true;
    } on NobodyToReach {
      // No team can be reached for this device; asking again cannot change that.
    } on Exception {
      _keepAskingForAPerson(_askForAPersonWithoutASession);
    } finally {
      _askingForAPerson = false;
    }
  }

  /// Whether to try again is `state.needsPerson` and not the epoch: `_cancelTimers` runs
  /// on the way into other halts, and an attempt still in flight when it does would
  /// otherwise land on a room that is still stopped and stop insisting in silence.
  void _keepAskingForAPerson(Future<void> Function() retry) {
    if (_gone || !state.needsPerson) return;
    final backoff = ref.read(roomRetryBackoffProvider);
    final step = _personAskStep < backoff.length
        ? _personAskStep
        : backoff.length - 1;
    _personAskStep++;
    _after('person', backoff[step], () => unawaited(retry()));
  }

  /// [turnCall] marks the openSession/sendTurn/loadWheel family: every call to one of the
  /// three, through whichever door reaches it — including the opening turn a resume with
  /// nothing to restore falls through to. A `RoomBroke` there raises the affordance on
  /// the spot, the same turn a person would have been shown E0 in. Every other caller —
  /// the resume itself, upload, a written question, a retro edit, an approval — keeps the
  /// three-strike ladder `_registerRoomFailure` runs underneath.
  void _handleRoomFailure(Object error, {bool turnCall = false}) {
    _leaveThinking();
    if (turnCall && error is RoomBroke) {
      _haltForAPerson();
      return;
    }
    switch (error) {
      case RoomRefused():
        _haltForAPerson();
      case SessionGone():
        _leaveTheDeadPassage();
      case PassageCannotOpen():
        final refused = _emCurso;
        if (refused != null) {
          state = state.copyWith(
            refusedThisVisit: {...state.refusedThisVisit, refused},
          );
        }
        unawaited(abrirEscolha(afterRefusal: true));
      case RoomBroke() || StretchNoLongerCounts():
        _registerRoomFailure();
      case RoomSlow():
        _registerSlowRoom();
      default:
        _goOffline(RoomReach.noNetwork);
    }
  }

  /// The room answered nothing in time. It is still there.
  ///
  /// Every timeout used to be spent as a verdict — one slow turn and the room told a team
  /// on a working network that the internet was gone. The upload queue has always paced
  /// waits apart from refusals; this is the same distinction, arriving late.
  void _registerSlowRoom() {
    _slowAnswers++;
    _calmTurns = 0;
    _conviteOpened = false;
    if (_slowAnswers >= _slowAnswersBeforeGivingUp) {
      _goOffline(RoomReach.roomSilent);
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
  }

  void _registerRoomFailure() {
    _roomFailures++;
    _calmTurns = 0;
    _conviteOpened = false;
    if (_roomFailures >= _roomFailuresBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
  }

  /// A played turn only earns `_roomFailures`/`_slowAnswers` back after two calm turns
  /// in a row — a network failing every other turn traded one failure for one success
  /// every time, and the counter it gated never climbed. A resolve clears every counter
  /// outright: it is the room's own word the trouble is over, not one more turn to weigh.
  void _settleNetworkHealth({bool resolved = false, bool calm = true}) {
    _unplayableTurns = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    if (resolved) {
      _roomFailures = 0;
      _slowAnswers = 0;
      _calmTurns = 0;
      return;
    }
    if (!calm) {
      _calmTurns = 0;
      return;
    }
    _calmTurns++;
    if (_calmTurns < 2) return;
    _calmTurns = 0;
    if (_roomFailures > 0) _roomFailures--;
    if (_slowAnswers > 0) _slowAnswers--;
  }

  void _watchBusyState() {
    final ceiling = ref.read(busyStateCeilingProvider);
    if (ceiling != null) _after('watchdog', ceiling, _giveUpOnBusyState);
  }

  void _giveUpOnBusyState() {
    // Only a wait can be stuck. A line that is being spoken is judged by the voice
    // itself, which times out on the clip's own length plus a grace
    // (`FacilitatorVoiceService._sayItWhole`); a flat ceiling here read a 122 s opening
    // as a room that had stopped answering and called for a person two seconds before
    // the Guide finished the sentence.
    if (state.voice != VoiceState.thinking) return;
    _cancelTimers();
    _conviteOpened = false;
    _leaveThinking();
    _haltForAPerson();
  }

  /// The room gave up on a call it was making, however it came to that.
  ///
  /// This is the seam rather than `_handleRoomFailure`, because the watchdog that gives up
  /// on a busy state is not a room failure — it is this tablet deciding the wait is over —
  /// and it is the one give-up that fires while a correction's own call is in the air, with
  /// no refusal and no offline circle to show for it. Both stations do all their waiting in
  /// this phase.
  void _leaveThinking() {
    if (state.stage == SalaStage.retro && state.btPhase == BtPhase.thinking) {
      state = state.copyWith(btPhase: BtPhase.playing);
    }
  }

  void _goOffline(RoomReach why) {
    if (state.unreachable) {
      _drawTheFallAgain(why);
      return;
    }
    _cancelTimers();
    _leaveThinking();
    state = state.copyWith(
      voice: VoiceState.offline,
      reach: why,
      peerCue: false,
    );
    if (!_noticeSpoken) {
      _noticeSpoken = true;
      unawaited(_voice.playAsset(offlineNoticeAsset(_lingua)));
    }
    _watchForNetwork();
    _scheduleRetry();
  }

  void _drawTheFallAgain(RoomReach why) {
    if (state.offline || state.needsPerson) return;
    _leaveThinking();
    state = state.copyWith(
      voice: VoiceState.offline,
      reach: why,
      peerCue: false,
    );
  }

  void _watchForNetwork() {
    _networkWatch ??= _network.onNetworkReturned.listen((_) {
      unawaited(_attemptReturn());
    });
  }

  void _scheduleRetry() {
    final backoff = ref.read(roomRetryBackoffProvider);
    final step = _retryStep < backoff.length ? _retryStep : backoff.length - 1;
    _retryStep++;
    _ladder?.cancel();
    _ladder = Timer(backoff[step], () => unawaited(_attemptReturn()));
  }

  Future<void> _attemptReturn() async {
    if (!state.unreachable || _returning) return;
    _returning = true;
    try {
      final reach = await _network.reachRoom();
      if (_gone || !state.unreachable) return;
      if (reach == RoomReach.fine) {
        _comeBack();
      } else {
        state = state.copyWith(reach: reach);
        _scheduleRetry();
      }
    } finally {
      _returning = false;
    }
  }

  void retryNow() {
    if (!state.unreachable) return;
    _ladder?.cancel();
    unawaited(_attemptReturn());
  }

  void _comeBack() {
    if (!state.unreachable) return;
    _ladder?.cancel();
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
    final epoch = _epoch;
    final queue = _takes;
    unawaited(
      queue.flush().then((_) async {
        if (epoch != _epoch) return;
        await _adoptTheNames(queue);
        if (epoch == _epoch) unawaited(_countUnsent());
      }),
    );
    state = state.copyWith(reach: RoomReach.fine);
    // The fall took the watch with the rest of the timers. A blocking halt gets its own
    // back the next time the room stops, but nothing stops for a warning: left here, a
    // room that lost the network under one came back green for good.
    if (state.warning) _watchTheHalt();
    if (!state.offline) return;
    state = state.copyWith(voice: VoiceState.invite);
    if (state.stage == SalaStage.fim) {
      _startOver();
    } else if (state.stage == SalaStage.escolha) {
      unawaited(abrirEscolha());
    } else if (state.stage == SalaStage.convite &&
        state.conviteStep == ConviteStep.boasVindas) {
      _conviteOpened = false;
    } else if (state.sessionId == null && state.stage == SalaStage.conversa) {
      unawaited(goConversa(pericope: _emCurso));
    }
  }

  void beginAgain() => _startOver();

  /// The press asks rather than answers: a facilitator who has just marked the session
  /// attended hands the room back at once, instead of on the next beat of the watch.
  /// Where there is nobody to ask it keeps the local release, the rule `offline` has.
  void resolveWithPerson() {
    if (!state.needsPerson && !state.offline) return;
    if (state.needsPerson && _haltWatched != null) {
      unawaited(_tellTheRoomAPersonArrived(_haltWatched!));
      unawaited(_askIfTheHaltIsOver());
      return;
    }
    _leaveTheHalt();
  }

  /// One attempt per press. The re-read above is what actually lifts the halt, so a
  /// failed ping here is not retried — it would just spend the backoff on a signal the
  /// desk already has another way to get.
  Future<void> _tellTheRoomAPersonArrived(String sessionId) async {
    try {
      await _room.personArrived(sessionId);
    } on Exception {
      // Silent: the re-read still happens and the halt still ends the normal way.
    }
  }

  void _endTheWatch() {
    _haltWatched = null;
    _timers.remove('halt')?.cancel();
  }

  void _leaveTheHalt() {
    _endTheWatch();
    _ladder?.cancel();
    _timers.remove('person')?.cancel();
    _personAsked = false;
    _personAskStep = 0;
    _settleNetworkHealth(resolved: true);
    _resumeFailures = 0;
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
    state = state.copyWith(voice: VoiceState.invite, reach: RoomReach.fine);
    // Every way out of a halt ends the watch, and a warning standing under it is a
    // session still asking for somebody. Left ended, the halt's own exit — the beat that
    // reads it away, or the long press on a room that is out — carried the warning off
    // with it, and the desk's mark never reached the circle again.
    if (state.warning) _watchTheHalt();
    // A halt withholds the sound and nothing else: a lift replays only what it caught
    // sounding, from the part's own cursor — a part, a bead replay, or a part chosen but
    // never landed yet, the way `_soavaQuandoParou` reads it. A part a hold left silent,
    // or one already at its end, comes back exactly as it stood.
    //
    // A cut is the team's own work in progress, never touched by this — not even when
    // the halt caught the team listening to the very thing it named. A pending
    // translation always stands on one, and a retell arms its own. `_tocarParteDaRetro`
    // re-cursors and re-cuts unconditionally, which is right for the part this reading covers and wrong for one
    // already telling something back: a confirm or a correction still in flight when the
    // halt landed reads its own `_trechoStart`/`_trechoEnd` fresh once it resolves, and a
    // lift that had touched them first would send what it reads as a stretch of no
    // length.
    if (state.stage == SalaStage.retro &&
        state.btPhase == BtPhase.playing &&
        _parteNoAr != null &&
        _soavaQuandoParou &&
        !state.btCortado) {
      _tocarParteDaRetro(_parteTocando);
    }
    if (_haltedResuming ||
        (state.sessionId == null && state.stage == SalaStage.conversa)) {
      unawaited(goConversa(pericope: _emCurso));
    }
    // The wheel itself having nothing unrefused to offer has no session to resume into,
    // and leaving that halt is a fresh visit: the server may have changed, the same way
    // leaving the book and coming back is. Left un-reloaded, a wheel emptied by refusal
    // stayed dead forever — every gesture on it guarded by `needsPerson` while it was
    // true, and by the very memory this clears once it is not. A stall reaching some
    // other door without leaving the Choice's stage (the panorama's) is not this: it
    // retries that same door, not the wheel behind it.
    if (state.wheelHalted) {
      state = state.copyWith(wheelHalted: false, refusedThisVisit: {});
      unawaited(abrirEscolha());
    }
  }

  /// Arms the wait for the coverage channel to say what this turn's classification
  /// decided. A turn the server never meant to grade — no id, or nothing pending — has
  /// nothing to wait for, so it is not the panorama's own turns that skip this: it is any
  /// turn the server already settled by the time it answered. Called twice per turn, once
  /// before it speaks and once after — a turn the channel already settled while it spoke
  /// stays settled, rather than being rearmed for the same wait a second time.
  void _awaitCoverageSettle(TurnResult turn, {TurnClock? clock}) {
    final sessionId = state.sessionId;
    final turnId = turn.turnId;
    if (sessionId == null ||
        turnId == null ||
        !turn.classificationPending ||
        turnId == _resolvedCoverageTurnId) {
      return;
    }
    _watchCoverageChannel(sessionId);
    _awaitingCoverageTurnId = turnId;
    _coverageClock = clock;
    _after('coverage', ref.read(coverageFallbackDelayProvider), () {
      if (_awaitingCoverageTurnId != turnId) return;
      _resolveCoverageWait(sessionId, turnId, pullState: true);
    });
  }

  void _scheduleInboxPoll() {
    _after('inbox-poll', ref.read(roomPollDelayProvider), () {
      unawaited(_pullInbox());
    });
  }

  void _watchCoverageChannel(String sessionId) {
    if (_coverageSessionId == sessionId) return;
    unawaited(_coverageWatch?.cancel());
    _coverageSessionId = sessionId;
    // The repository closes the channel right after every error it raises
    // (RR:watchCoverage), so onDone is where the channel dies, once; onError only records
    // why. Only the room refusing the device or no longer holding the session is a
    // refusal. A body that breaks mid-stream, or a status the room could not serve, may be
    // how Cloud Run's 300 s cut reaches the tablet — read as a refusal, it left the beads
    // waiting on the fallback again, the very bug the reopen exists to fix.
    var refused = false;
    _coverageWatch = _room
        .watchCoverage(sessionId)
        .listen(
          _onCoverageFrame,
          onDone: () => _coverageChannelDied(sessionId, reopen: !refused),
          onError: (Object error) {
            refused = error is RoomRefused || error is SessionGone;
          },
        );
  }

  /// A dead channel is always forgotten, so the next turn that needs one does not find a
  /// subscription this class already thinks is alive. Only an ordinary end — the Cloud
  /// Run cut, not a refusal — reopens it right away, and only for a turn still waiting on
  /// it; a session with nothing pending is left closed for the next `_awaitCoverageSettle`
  /// to reopen, and a refusal is never retried on its own. That reopen still fires at most
  /// once per armed turn: a room the client cannot reach keeps closing the channel it just
  /// reopened, and reopening on every one of those deaths turned an unreachable room into
  /// a reopen-and-fetch loop for the whole 30 s fallback window. The guard is scoped to the
  /// turn's own id, not a flag `_awaitCoverageSettle` clears — that method arms the same
  /// turn twice, once before it speaks and once after, and a flag reset on every arm let a
  /// death landing between those two calls buy the turn a second reopen.
  void _coverageChannelDied(String sessionId, {required bool reopen}) {
    _coverageWatch = null;
    _coverageSessionId = null;
    if (reopen &&
        _awaitingCoverageTurnId != null &&
        _coverageReopenedForTurnId != _awaitingCoverageTurnId) {
      _coverageReopenedForTurnId = _awaitingCoverageTurnId;
      _watchCoverageChannel(sessionId);
      unawaited(_recoverCoverageWait(sessionId));
    }
  }

  /// The reopen's own recovery read: a frame published while the channel was down is
  /// lost, so this asks the state directly instead of waiting on the channel to say it
  /// again. Landing an advance for the turn still waiting closes that wait right here —
  /// left open, the 30 s fallback still fired later, asked the state a second time, and
  /// restamped the beads clock on a turn that had already landed.
  Future<void> _recoverCoverageWait(String sessionId) async {
    final turnId = _awaitingCoverageTurnId;
    final advanced = await _pullState(
      sessionId,
      clock: _coverageClock,
    ).catchError((_) => false);
    if (turnId != null && advanced && _awaitingCoverageTurnId == turnId) {
      _resolveCoverageWait(sessionId, turnId, pullState: false);
    }
  }

  void _onCoverageFrame(CoverageEvent frame) {
    if (frame.turnId != _awaitingCoverageTurnId) return;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    _applyCoverage(frame.coverage, clock: _coverageClock);
    _resolveCoverageWait(
      sessionId,
      frame.turnId,
      pullState: frame.status == CoverageStatus.settled,
    );
  }

  /// A turn that carried no coverage, or fewer beads than the necklace already shows,
  /// leaves the necklace where it is. Reading a missing field as zero emptied the cord
  /// mid-passage — the only record of progress this team can perceive — and a read
  /// that raced ahead of a slower one used to be able to put it back. The same guard
  /// runs whether the number came from the coverage frame or from the state pull that
  /// follows it, so the pull confirming what the frame already painted never re-marks
  /// the clock a second time.
  bool _applyCoverage(Coverage? told, {TurnClock? clock}) {
    final before = state.coverage.engaged;
    final advanced = told != null && told.engaged > before;
    if (advanced) clock?.mark('beads');
    if (told != null && told.engaged >= before) {
      state = state.copyWith(coverage: told);
    }
    return advanced;
  }

  void _resolveCoverageWait(
    String sessionId,
    String turnId, {
    required bool pullState,
  }) {
    _awaitingCoverageTurnId = null;
    _resolvedCoverageTurnId = turnId;
    _timers.remove('coverage')?.cancel();
    final clock = _coverageClock;
    _coverageClock = null;
    if (pullState) {
      unawaited(_pullState(sessionId, clock: clock).catchError((_) => false));
    }
    unawaited(_pullInbox());
  }

  /// Reads the state directly, folding in whatever the coverage channel might have
  /// missed. Reports whether the necklace actually moved, so a caller settling a wait
  /// from this alone — the recovery read after a reopen — knows whether it landed
  /// something, and the clock that measures the trip only marks a beat that happened:
  /// stamping it on a pull that changed nothing timed a turn that never actually landed.
  Future<bool> _pullState(String sessionId, {TurnClock? clock}) async {
    final epoch = _epoch;
    try {
      final snapshot = await _room.fetchState(sessionId);
      if (epoch != _epoch || state.sessionId != sessionId) return false;
      final advanced = _applyCoverage(snapshot.coverage, clock: clock);
      state = state.copyWith(warning: snapshot.halt == HaltKind.warning);
      if (state.warning) _watchTheHalt();
      if (snapshot.needsPerson) {
        _haltForAPerson(read: true);
      } else if (snapshot.done && state.stage == SalaStage.conversa) {
        if (state.voice == VoiceState.invite) {
          state = state.copyWith(voice: VoiceState.done, peerCue: false);
        } else if (state.voice == VoiceState.speaking ||
            state.voice == VoiceState.listening ||
            state.voice == VoiceState.thinking) {
          _doneSeenMidTurn = true;
        }
      }
      return advanced;
    } on SessionGone {
      if (epoch != _epoch) return false;
      _leaveTheDeadPassage();
      return false;
    } on RoomRefused {
      if (epoch != _epoch) return false;
      _haltForAPerson();
      return false;
    }
  }

  /// Open the room: go straight to the passages if the book was already opened on this
  /// tablet. The panorama belongs to a book, not to a launch. Otherwise the room says
  /// nothing and waits for the touch that opens the convite.
  Future<void> openTheRoom() async {
    if (state.stage != SalaStage.convite) return;
    if (state.conviteStep != ConviteStep.boasVindas) return;
    if (await _feitas.bookOpened(_book)) {
      await abrirEscolha();
    }
  }

  Future<void> openConvite() async {
    if (state.stage != SalaStage.convite || _conviteOpened) return;
    _conviteOpened = true;
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    final reach = await _network.reachRoom();
    if (epoch != _epoch) return;
    if (reach != RoomReach.fine) {
      _conviteOpened = false;
      _goOffline(reach);
      return;
    }
    _watchBusyState();
    try {
      // A panorama that fails to play sends the team back to the invite, and every touch
      // used to mint another session for the same book — the server collected one
      // abandoned panorama per attempt. One launch asks for one panorama.
      final created = _panoramaSessionId == null
          ? await _room.createSession(
              pericope: panoramaPericope,
              language: _lingua,
            )
          : null;
      if (epoch != _epoch) return;
      // Asking for the panorama is a request and not an instruction: which passage a
      // session is for is the room's to say, and the answer carries it. The answer is
      // also the session to enter: opening another for the same passage left the one the
      // room had just made abandoned, one ghost row per launch.
      final given = created?.pericope;
      if (given != null && !isThePanorama(given)) {
        // The room answering a passage is its word that the panorama was heard. Left
        // unwritten, a tablet without the mark asked for the panorama on every launch and
        // adopted a new session each time, its coverage starting over from zero.
        unawaited(_feitas.markBookOpened(_book).catchError((_) {}));
        unawaited(goConversa(pericope: given, opened: created));
        return;
      }
      final panorama = _panoramaSessionId ?? created!.sessionId;
      _panoramaSessionId = panorama;
      final turn = await _room.openSession(
        panorama,
        turnId: _openTurnId ??= _stamp(),
      );
      if (epoch != _epoch) return;
      await _voicePanorama(turn);
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _conviteOpened = false;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  Future<void> _voicePanorama(TurnResult turn) async {
    final epoch = _epoch;
    await _readyToSpeak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    final played = await _speak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    if (!played) {
      _conviteOpened = false;
      _registerUnplayableTurn();
      return;
    }
    _settleNetworkHealth();
    _resumeFailures = 0;
    _openTurnId = null;
    unawaited(_feitas.markBookOpened(_book).catchError((_) {}));
    state = state.copyWith(
      voice: VoiceState.invite,
      conviteStep: ConviteStep.entrada,
    );
  }

  void conviteTap() {
    if (state.stage != SalaStage.convite) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.playingReplyId != null) return;
    if (state.noteMode) {
      _noteTap();
      return;
    }
    if (state.conviteStep == ConviteStep.entrada) {
      switch (state.voice) {
        case VoiceState.invite:
          _startListening('panorama_${_stamp()}');
        case VoiceState.listening:
          unawaited(_finishPanoramaListening());
        case VoiceState.thinking:
        case VoiceState.speaking:
        case VoiceState.done:
        case VoiceState.needsPerson:
        case VoiceState.offline:
        case VoiceState.blocked:
          break;
      }
      return;
    }
    if (state.voice != VoiceState.invite) return;
    if (state.conviteStep == ConviteStep.boasVindas) unawaited(openConvite());
  }

  Future<void> _finishPanoramaListening() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final panorama = _panoramaSessionId!;
    if (path == null || !_hasAudio(path)) {
      state = state.copyWith(voice: VoiceState.invite);
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    _sayImThinking();
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    try {
      final turn = await _sendTheTake(panorama, File(path), epoch);
      if (epoch != _epoch) return;
      await _voicePanorama(turn);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  Future<void> abrirEscolha({bool afterRefusal = false}) async {
    // Still the same visit to the Choice when this call never left its stage — a network
    // blip that comes back mid-visit, or the wheel-never-loaded retry — as well as the
    // reload a refusal itself triggers, which leaves the stage but is not a fresh entry.
    final sameVisit = afterRefusal || state.stage == SalaStage.escolha;
    if (state.stage != SalaStage.escolha) {
      final unplayableTurns = _unplayableTurns;
      _forgetThePassage();
      _unplayableTurns = unplayableTurns;
    }
    _clearAll();
    final epoch = _epoch;
    state = state.copyWith(
      stage: SalaStage.escolha,
      voice: VoiceState.thinking,
      peerCue: false,
      clearRoda: true,
      refusedThisVisit: sameVisit ? null : const {},
    );
    _watchBusyState();
    final List<Passagem> todas;
    try {
      todas = await _room.passagesOf(_book, language: _lingua);
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error, turnCall: true);
      return;
    }
    if (epoch != _epoch) return;
    // Held before the awaits: a provider read after the container is disposed throws,
    // and this method is reached from a fire-and-forget touch.
    final ledger = _feitas;
    final open = _emAberto;
    final book = _book;
    final feitas = await ledger.all(book);
    final comecadas = await open.startedIn(book);
    if (epoch != _epoch || _gone) return;
    final primeiraOfertavel = todas.indexWhere(_isOfertavel);
    state = state.copyWith(
      naRoda: todas,
      comecadas: comecadas,
      feitas: feitas,
      aOferecer: primeiraOfertavel < 0 ? 0 : primeiraOfertavel,
      voice: VoiceState.invite,
      // A reload that finds something to offer must never leave `oferecida` stuck null
      // under a halt this same reload is about to lift or that never applied to begin
      // with.
      wheelHalted: false,
    );
    if (todas.every(
      (passagem) =>
          passagem.isPanorama ||
          state.refusedThisVisit.contains(passagem.pericope),
    )) {
      // Nothing left for the room to offer, which is exactly what needsPerson means —
      // and it is the only state here with a glyph, a spoken line and a way out. A green
      // disc that refused every gesture in silence looked like a room that had died.
      //
      // The panorama's own spoke is not a passage, and neither is a real one this visit
      // already offered and the room refused to open.
      _haltForAPerson(wheelExhausted: true);
      return;
    }
    unawaited(
      _dizerAOferecida().then((_) => _fetchTheNamesTheWheelLacks(epoch)),
    );
  }

  /// Whether the wheel can land on this passage and speak it: a spoke of the panorama
  /// always is, and a real passage is unless this same visit to the Choice already had
  /// it refused at creation.
  bool _isOfertavel(Passagem passagem) =>
      passagem.isPanorama ||
      !state.refusedThisVisit.contains(passagem.pericope);

  /// One number per quiet download of the wheel's names. Every way off the wheel bumps the
  /// epoch except the panorama spoke, which never passes through `_clearAll`; entering any
  /// spoke bumps this instead, so a download started for the wheel dies with it either way.
  int _wheelPrefetch = 0;

  Future<void> _fetchTheNamesTheWheelLacks(int epoch) async {
    final run = ++_wheelPrefetch;
    final roda = state.naRoda;
    if (roda == null || roda.isEmpty) return;
    final pending = List<int>.generate(roda.length, (i) => i);
    while (pending.isNotEmpty) {
      if (epoch != _epoch || run != _wheelPrefetch) return;
      final aim = state.aOferecer;
      pending.sort(
        (a, b) => ((a - aim) % roda.length).compareTo((b - aim) % roda.length),
      );
      final url = roda[pending.removeAt(0)].audioUrl;
      if (url.isEmpty || await _voice.holds(url)) continue;
      await _voice.fetch(url);
    }
  }

  /// The circle on the wheel says the passage again. It no longer moves.
  ///
  /// One tap used to both advance and speak, so a team could never hear a passage twice
  /// without leaving it, and going back one meant riding the whole wheel through
  /// fourteen names. Moving is the ruler's job now, and the ruler is dragged.
  void escolhaTap() {
    if (state.stage != SalaStage.escolha) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.needsPerson) return;
    if (state.voice != VoiceState.invite) return;
    final roda = state.naRoda;
    if (roda == null) {
      // The wheel never loaded. There is nothing to say and nothing to enter, so the
      // touch is the retry — otherwise this screen has no live gesture at all.
      unawaited(abrirEscolha());
      return;
    }
    if (roda.isEmpty) return;
    unawaited(_dizerAOferecida());
  }

  /// Move along the wheel with the finger still down, without saying anything.
  ///
  /// Naming every passage the finger crosses would stutter fourteen clips across one
  /// drag. The room stays quiet while they are choosing and speaks where they land.
  void apontarPassagem(int index) {
    if (state.stage != SalaStage.escolha) return;
    if (state.needsPerson || state.offline) return;
    final roda = state.naRoda;
    if (roda == null || roda.isEmpty) return;
    final at = index.clamp(0, roda.length - 1);
    final landing = _nearestOfertavel(roda, at, from: state.aOferecer);
    if (landing == null) return;
    if (landing == state.aOferecer && state.voice == VoiceState.invite) return;
    // Not `_cancelTimers()`: it bumps the epoch and clears every timer in the room.
    // Cutting the line short is enough, and `_dizerAOferecida` checks for itself that the
    // finger has not moved on.
    _silenceTheRoom();
    state = state.copyWith(aOferecer: landing, voice: VoiceState.invite);
  }

  /// The nearest spoke to [target] the wheel can land on, walking from [from] toward
  /// [target] rather than jumping straight there. A refused spoke is still on the ruler
  /// (ADR 0040: dimmed, never hidden) but is not a stop: VoiceOver's one-step increase
  /// landing on one used to move nothing at all, stuck there for good.
  int? _nearestOfertavel(List<Passagem> roda, int target, {required int from}) {
    if (_isOfertavel(roda[target])) return target;
    final step = target >= from ? 1 : -1;
    for (var at = target; at >= 0 && at < roda.length; at += step) {
      if (_isOfertavel(roda[at])) return at;
    }
    return null;
  }

  /// Say where the finger landed.
  void dizerAPassagem() {
    if (state.stage != SalaStage.escolha) return;
    if (state.needsPerson || state.offline) return;
    if (state.naRoda?.isEmpty ?? true) return;
    _silenceTheRoom();
    unawaited(_dizerAOferecida());
  }

  Future<void> _dizerAOferecida() async {
    final passagem = state.oferecida;
    if (passagem == null) return;
    final epoch = _epoch;
    final aimed = state.aOferecer;
    bool moved() => epoch != _epoch || state.aOferecer != aimed;
    await _readyToSpeak(passagem.audioUrl, '');
    if (moved()) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    try {
      final spoke = await _speak(passagem.audioUrl, '');
      if (moved()) return;
      // A wheel that has gone silent looks to the team exactly like a wheel that has
      // stopped, and there is no written word here to tell them apart.
      if (!spoke) return _registerUnplayableTurn();
      _unplayableTurns = 0;
      state = state.copyWith(voice: VoiceState.invite);
    } on Exception catch (error) {
      if (moved()) return;
      _handleRoomFailure(error);
    }
  }

  void entrarNaOferecida() {
    final passagem = state.oferecida;
    if (passagem == null || state.voice != VoiceState.invite) return;
    _wheelPrefetch++;
    // Acima dos dois ramos: o panorama não passa pelo _clearAll do goConversa, e a
    // linha que a roda acabou de oferecer seguia soando por cima da espera dele.
    _silenceTheRoom();
    if (passagem.isPanorama) {
      unawaited(_entrarNoPanorama());
      return;
    }
    unawaited(goConversa(pericope: passagem.pericope));
  }

  /// Enter the panorama from its own spoke on the wheel, instead of falling into a
  /// passage. It has no foreseen end, and nothing here schedules one: the team leaves it
  /// the same way it leaves any session, by turning the wheel to a passage.
  ///
  /// Asked for by `panoramaPericope`, the same alias `openConvite` already asks for it
  /// by — not by whatever id the wheel happens to label the spoke with — and the session
  /// is reused rather than asked for again on every tap, for the reason `openConvite`'s
  /// own guard gives: a retried touch would otherwise mint one abandoned panorama session
  /// per attempt.
  Future<void> _entrarNoPanorama() async {
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    final reach = await _network.reachRoom();
    if (epoch != _epoch) return;
    if (reach != RoomReach.fine) {
      _goOffline(reach);
      return;
    }
    _watchBusyState();
    try {
      final created = _panoramaSessionId == null
          ? await _room.createSession(
              pericope: panoramaPericope,
              language: _lingua,
            )
          : null;
      if (epoch != _epoch) return;
      // Which passage a session is for is the room's to say, and the answer carries it —
      // the same swap openConvite already honours. A team touching this spoke while the
      // room decides otherwise lands where the room answered, rather than being left on
      // the wheel mid an opening turn nothing here is set up to answer.
      final given = created?.pericope;
      if (given != null && !isThePanorama(given)) {
        unawaited(goConversa(pericope: given, opened: created));
        return;
      }
      final panorama = _panoramaSessionId ?? created!.sessionId;
      _panoramaSessionId = panorama;
      final turn = await _room.openSession(
        panorama,
        turnId: _openTurnId ??= _stamp(),
      );
      if (epoch != _epoch) return;
      await _readyToSpeak(turn.audioUrl, turn.fixedLine);
      if (epoch != _epoch) return;
      state = state.copyWith(voice: VoiceState.speaking);
      _watchBusyState();
      final spoke = await _speak(turn.audioUrl, turn.fixedLine);
      if (epoch != _epoch) return;
      if (!spoke) return _registerUnplayableTurn();
      _unplayableTurns = 0;
      _openTurnId = null;
      state = state.copyWith(voice: VoiceState.invite);
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  /// Leave a passage part-way and go pick another one.
  ///
  /// There was no way out at all: a team that entered the wrong passage was held there
  /// until it was checked, or had to have the app killed. The passage was never finished,
  /// so it stays in the wheel, and the upload queue keeps whatever it was already holding.
  void leaveThePassage() {
    _clearAll();
    _dropThePendingTake();
    _forgetThePassage();
    state = const SalaSessionState();
    unawaited(abrirEscolha());
  }

  void _leaveTheDeadPassage() {
    final pericope = _emCurso;
    if (pericope == null) {
      // Nothing here is a passage — the wheel itself failing to reload after
      // an earlier departure, or a calibration turn with no passage entered
      // yet. Leaving loops back into exactly this failure with nowhere new to
      // land, so this is where the old, bounded halt still belongs.
      _haltForAPerson(sessionIsGone: true);
      return;
    }
    unawaited(_mindingThePlace(() => _emAberto.forget(_book, pericope)));
    leaveThePassage();
  }

  bool _wrongLanguage(ResumePoint? point) {
    final language = point?.language;
    return language != null && language != _lingua;
  }

  /// Everything of the session before this one stays behind.
  ///
  /// Only what the book knows crosses over — the wheel, the passages started, the ones
  /// finished, the one being offered — and entering the passage says the rest again.
  /// Built from an empty state rather than cleared field by field, so a fact the session
  /// gains tomorrow is born clean here without anybody remembering this branch; the
  /// counters and latches with no home in the state go through [_forgetThePassage],
  /// which is already where they live.
  void _startTheSessionClean(String? pericope) {
    final livro = state;
    _dropThePendingTake();
    _forgetThePassage();
    _emCurso = pericope;
    state = SalaSessionState(
      stage: SalaStage.conversa,
      voice: VoiceState.thinking,
      naRoda: livro.naRoda,
      comecadas: livro.comecadas,
      feitas: livro.feitas,
      aOferecer: livro.aOferecer,
    );
    _stringTheNecklaceEarly(pericope);
  }

  /// Enter a passage, resuming the session this tablet left in it when there is one.
  ///
  /// `fresh` skips the resume, which is how the 404 path starts over: retrying without it
  /// looked the session up again and recursed forever.
  ///
  /// `opened` is a session the room already made for this passage, entered as it came
  /// back rather than asked for again.
  Future<void> goConversa({
    String? pericope,
    bool fresh = false,
    SessionSnapshot? opened,
  }) async {
    _clearAll();
    _haltedResuming = false;
    _emCurso = pericope;
    final epoch = _epoch;
    state = state.copyWith(
      stage: SalaStage.conversa,
      voice: VoiceState.thinking,
      peerCue: false,
      contasEnfiadas: true,
    );
    _stringTheNecklaceEarly(pericope);
    _watchBusyState();
    final openingClock = TurnClock();
    _pendingClock = openingClock;
    final reach = await _network.reachRoom();
    if (epoch != _epoch) return;
    openingClock.mark('health');
    if (reach != RoomReach.fine) {
      _goOffline(reach);
      return;
    }
    // Re-armed, not armed once: the ceiling is meant to say "nothing has happened for two
    // minutes", and a single arming over reach + create + open made it say "the whole
    // chain took two minutes" — which a slow but perfectly successful panorama does.
    _watchBusyState();
    // Only the passages the wheel already said have work waiting are looked up on disk,
    // so entering a fresh one through the wheel costs no read at all. A door the room
    // opened has no wheel behind it — the list is still empty at the invitation — so the
    // row is looked up there whatever the list says (ADR 0033).
    final stored =
        !fresh &&
            pericope != null &&
            (opened != null || state.comecadas.contains(pericope))
        ? await _emAberto.of(_book, pericope)
        : null;
    if (epoch != _epoch) return;
    final waiting = _wrongLanguage(stored) ? null : stored;
    var reachedTheOpeningTurn = false;
    try {
      final resumed = waiting != null;
      final created = resumed
          ? null
          : opened ??
                await _room.createSession(
                  pericope: pericope,
                  afterSession: _panoramaSessionId,
                  language: _lingua,
                );
      if (!resumed && opened == null) openingClock.mark('session');
      final sessionId = waiting?.sessionId ?? created!.sessionId;
      if (epoch != _epoch) return;
      // The passage opened for real, whether created fresh or resumed: the team has left
      // the Choice, and whatever visit was refusing passages there is over. A stumble
      // past this point — a session gone mid-open, a fresh retry the room also refuses —
      // is this passage's own new refusal, not the last visit's.
      if (!resumed) _startTheSessionClean(pericope);
      state = state.copyWith(
        sessionId: sessionId,
        coverage: created?.coverage,
        refusedThisVisit: const {},
      );
      _sessionSavedAt = resumed ? waiting.savedAt : DateTime.now();
      _sessionLanguage = resumed ? waiting.language : _lingua;
      if (pericope != null && !resumed) {
        unawaited(
          _mindingThePlace(
            () => _emAberto.remember(
              _book,
              pericope,
              ResumePoint(
                sessionId: sessionId,
                stage: SalaStage.conversa,
                savedAt: _sessionSavedAt,
                language: _sessionLanguage,
              ),
            ),
          ),
        );
      }
      unawaited(_pullInbox());
      _watchBusyState();
      if (resumed) {
        final onde = await _backToWhereTheyStopped(waiting, epoch);
        if (epoch != _epoch) return;
        if (onde == _Resume.halted || onde == _Resume.abandoned) return;
        if (onde == _Resume.landed) {
          final snapshot = await _room.fetchState(sessionId);
          if (epoch != _epoch) return;
          state = state.copyWith(
            coverage: snapshot.coverage,
            warning: snapshot.halt == HaltKind.warning,
          );
          if (state.warning) _watchTheHalt();
          if (waiting.stage == SalaStage.retro) {
            _pickTheTellingBackUp(snapshot.backTranslation);
          } else {
            _keepTheStretchesAlreadyTold(snapshot.backTranslation);
          }
          // The snapshot was fetched here and its halt never read, so a team reopening
          // into a room the server had already stopped met every gesture wide open.
          //
          // After the telling-back is picked up, not before, so that the passage the team
          // comes back to is the one they left: a person resolving the halt finds them in
          // their retro rather than dropped back into the rehearsal.
          if (snapshot.needsPerson) _haltForAPerson(read: true);
          return;
        }
        if (waiting.stage == SalaStage.retro) {
          final told = (await _room.fetchState(sessionId)).backTranslation;
          if (epoch != _epoch) return;
          // Only when there is a telling-back to land on. A checked answer carrying no
          // stretch contradicts itself — the check is about what was told — and there is
          // no rehearsal here to land it on either, so this door declines it: landing it
          // left the room standing in the conversa until the watchdog called a person two
          // minutes later. It falls through to the turn instead, which is the door every
          // other empty answer takes: closing would call a passage the team never
          // approved its final draft.
          //
          // Reached only when the room holds no rehearsal of its own to hand back, which
          // is the one way past this door now that a resume fetches the parts.
          if (told.checked && !told.nothingTold) {
            _pickTheTellingBackUp(told);
            return;
          }
        }
      }
      // Re-opening carries the coverage back with it, so the necklace fills itself.
      reachedTheOpeningTurn = true;
      final opening = await _askForTheOpening(sessionId, epoch);
      openingClock.mark('open');
      await _voiceTurn(
        opening,
        epoch,
        onSoundStart: () => openingClock.mark('sound'),
      );
    } on SessionGone {
      if (epoch != _epoch) return;
      if (pericope != null) {
        unawaited(_mindingThePlace(() => _emAberto.forget(_book, pericope)));
      }
      if (fresh) {
        // Already the clean attempt, and the room still does not know a session it was asked
        // about: the panorama this one opened after, or the one it just opened. Retrying
        // again is the loop this guard exists to stop.
        leaveThePassage();
        return;
      }
      // The tablet remembered a session the server has forgotten. Start clean, once.
      unawaited(goConversa(pericope: pericope, fresh: true));
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      if (waiting != null && error is RoomBroke) {
        _resumeFailures++;
        if (_resumeFailures >= _resumeFailuresBeforeForgetting) {
          _resumeFailures = 0;
          unawaited(_mindingThePlace(() => _emAberto.forget(_book, pericope!)));
        }
      }
      // A resume keeps the three-strike ladder above (waiting != null): the server is
      // being asked to hand back work it already holds, not to open a fresh turn. A
      // session born clean is the turn call openConvite and its kin already are — and so
      // is the opening turn a resume with nothing to restore falls through to, once it
      // gets there: the door is `_askForTheOpening`, the same one every other empty
      // resume takes.
      _handleRoomFailure(
        error,
        turnCall: reachedTheOpeningTurn || waiting == null,
      );
    }
  }

  Future<TurnResult> _askForTheOpening(String sessionId, int epoch) async {
    _openingOwed = true;
    final turnId = _openTurnId ??= _stamp();
    while (true) {
      try {
        return await _room.openSession(sessionId, turnId: turnId);
      } on RoomSlow {
        if (epoch != _epoch) rethrow;
        if (_slowAnswers + 1 >= _slowAnswersBeforeGivingUp) rethrow;
        _slowAnswers++;
        _calmTurns = 0;
        _sayImThinking();
        _watchBusyState();
      }
    }
  }

  Future<void> _askForTheOpeningAgain() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final epoch = _epoch;
    _sayImThinking();
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    try {
      await _voiceTurn(await _askForTheOpening(sessionId, epoch), epoch);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  void _stringTheNecklaceEarly(String? pericope) {
    if (pericope == null) return;
    for (final passagem in state.naRoda ?? const <Passagem>[]) {
      if (passagem.pericope == pericope && passagem.beads > 0) {
        state = state.copyWith(
          coverage: Coverage(
            engaged: 0,
            surfaced: 0,
            total: passagem.beads,
            absenceIndex: passagem.absenceIndex,
          ),
        );
        return;
      }
    }
  }

  /// Write down where they are, so leaving lands them back here rather than at the start.
  void _rememberWhereTheyAre(SalaStage stage) {
    if (_gone) return;
    final pericope = _emCurso;
    final sessionId = state.sessionId;
    if (pericope == null || sessionId == null) return;
    unawaited(
      _mindingThePlace(
        () => _emAberto.remember(
          _book,
          pericope,
          ResumePoint(
            sessionId: sessionId,
            stage: stage,
            takes: state.keptTakes,
            savedAt: _sessionSavedAt,
            language: _sessionLanguage,
            partBeingRecordedAgain: state.parteARegravar,
          ),
        ),
      ),
    );
  }

  /// Put the team back on the stage they left, fetching the rehearsal when it is gone.
  ///
  /// A restore, a reinstall or another tablet leaves the row naming files that are not
  /// here. The rehearsal is not lost: the room is holding it, and the team comes back to
  /// the station they left with the room's own parts under them.
  Future<_Resume> _backToWhereTheyStopped(
    ResumePoint waiting,
    int epoch,
  ) async {
    if (waiting.stage == SalaStage.conversa || waiting.takes.isEmpty) {
      return _Resume.nothingToRestore;
    }
    final here = [
      for (final take in waiting.takes)
        if (await File(take.path).exists()) take,
    ];
    if (epoch != _epoch || _gone) return _Resume.abandoned;
    final faltavam = here.length != waiting.takes.length;
    final takes = faltavam ? await _asPartesDaSala(waiting, here, epoch) : here;
    if (epoch != _epoch || _gone) return _Resume.abandoned;
    if (takes == null) {
      _haltedResuming = true;
      _haltForAPerson();
      return _Resume.halted;
    }
    // A room holding no rehearsal is not a rehearsal to come back to, and it is not a
    // failure either: the conversa is where a passage with nothing behind it starts.
    if (takes.isEmpty) return _Resume.nothingToRestore;
    // Before the landing, while the room still says it is thinking. Measuring waits on the
    // player, and landed first the team is invited to tap over a rehearsal whose parts
    // have no end yet.
    if (faltavam) await _medirAsPartes(takes, epoch);
    if (epoch != _epoch || _gone) return _Resume.abandoned;
    state = state.copyWith(
      stage: SalaStage.ensaio,
      ensaio: EnsaioStatus.idle,
      voice: VoiceState.invite,
      keptTakes: takes,
      // Counted among the rehearsal's own parts — a row read off the tablet can also
      // carry a correction's own take, kept beside the parts but not one of them.
      takes: takes.where((take) => KeptScope.isParte(take.scopeId)).length,
      parteARegravar: waiting.partBeingRecordedAgain,
    );
    if (faltavam) {
      state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
      // The row named files that are not here any more. Rewritten only now, and only with
      // the recordings the room gave: a row rewritten without them makes the next opening
      // find nothing to restore, and the rehearsal the room is holding would be out of
      // the team's reach for good.
      _rememberWhereTheyAre(waiting.stage);
    }
    unawaited(_countUnsent());
    return _Resume.landed;
  }

  /// The room's current parts, kept on a tablet that no longer holds them.
  ///
  /// The current parts are the newest rehearsal recording under each number, in the order
  /// the room lists them — the server's own rule, so a part recorded again is the one the
  /// team gets back (ADR 0020). A telling-back is never one of them: it is the team
  /// explaining the story, not the story.
  ///
  /// They are numbered by their place in this row rather than by the number the room
  /// holds. The two agree for every rehearsal this tablet sent up, and where they cannot
  /// — a recording the room does not number — the place is what a part is addressed by
  /// everywhere else: a stretch sits on it there, and recording it again finds it there.
  ///
  /// A file still on the tablet under a current part's name is kept as it is: it is the
  /// team's own recording, and fetching a copy over the room's link would spend their
  /// network on what they already have.
  ///
  /// Null when the room could not hand the rehearsal over — the listing, one part's audio
  /// or the disk. Nothing is written for it: the resume point stays exactly as it was and
  /// the next opening tries again.
  ///
  /// Except for a room that has no such session any more. This is the first call that
  /// names the remembered session on a resume, so the answer that retires a session
  /// arrives here now, and swallowed it would make every opening ask a dead session for a
  /// rehearsal and call a person who has nothing to resolve. It goes to the handler that
  /// already starts the passage clean.
  Future<List<KeptTake>?> _asPartesDaSala(
    ResumePoint waiting,
    List<KeptTake> aqui,
    int epoch,
  ) async {
    final List<TakeView> guardadas;
    try {
      // Armed per step, not once around the whole fetch: the ceiling is what a single
      // wait is allowed, and a listing plus a part plus a measurement counted as one wait
      // calls a person on a link that is slow but working.
      _watchBusyState();
      guardadas = await _room.takesOf(waiting.sessionId);
    } on SessionGone {
      rethrow;
    } on Exception {
      return null;
    }
    if (epoch != _epoch || _gone) return const [];
    // Keyed by the room's number, which keeps the first place each number appears in and
    // the last recording made under it.
    final correntes = <int?, TakeView>{};
    for (final guardada in guardadas) {
      if (guardada.kind != 'ensaio') continue;
      correntes[guardada.ordinal] = guardada;
    }
    final partes = <KeptTake>[];
    for (final corrente in correntes.values) {
      final escopo = KeptScope.parte(partes.length + 1);
      final passada = corrente.pass ?? 1;
      final nossa = aqui.where((take) => take.takeId == corrente.takeId);
      if (nossa.isNotEmpty) {
        partes.add(
          KeptTake(
            scopeId: escopo,
            path: nossa.first.path,
            takeId: corrente.takeId,
            pass: passada,
          ),
        );
        continue;
      }
      final String arquivo;
      try {
        _watchBusyState();
        final bytes = await _room.fetchClip(
          RoomRepository.takeAudioUrl(waiting.sessionId, corrente.takeId),
        );
        if (bytes.isEmpty) return null;
        arquivo = await _recorder.keepBytes(
          bytes,
          '$escopo-${corrente.takeId}',
        );
      } on Exception {
        return null;
      }
      if (epoch != _epoch || _gone) return const [];
      partes.add(
        KeptTake(
          scopeId: escopo,
          path: arquivo,
          takeId: corrente.takeId,
          pass: passada,
        ),
      );
    }
    return partes;
  }

  /// How long each part turned out to be, so the room knows where each part ends.
  ///
  /// A part nobody can measure ends the ruler rather than lengthening it by a guess, which
  /// is the ruler's rule everywhere, and it is not a reason to stop the team.
  Future<void> _medirAsPartes(List<KeptTake> partes, int epoch) async {
    for (final parte in partes) {
      if (_tamanhoDaParteMs.containsKey(parte.path)) continue;
      _watchBusyState();
      final quanto = await _playback.howLong(parte.path);
      if (epoch != _epoch || _gone) return;
      if (quanto == null) continue;
      _marcarOFimDaParte(parte.path, quanto.inMilliseconds);
    }
  }

  /// Every reopening landed on the rehearsal, so a team that had stopped part-way through
  /// telling it back recorded the whole passage a second time and the session ended
  /// holding two of everything. A room holding no stretch yet is the same team at the
  /// same station: it comes back to the start of the untold ground, with the circle ready
  /// to tell, and not to a rehearsal it has already recorded.
  void _pickTheTellingBackUp(BackTranslationProgress told) {
    state = state.copyWith(
      stage: SalaStage.retro,
      voice: told.checked ? VoiceState.done : VoiceState.invite,
      btPhase: told.checked ? BtPhase.conferida : BtPhase.playing,
      btTrechos: _trechosFrom(told.segments),
    );
    final sessionId = state.sessionId;
    if (sessionId != null) {
      unawaited(_porCadaTrechoNaSuaParte(sessionId, told.segments, _epoch));
    }
    if (told.checked) return;
    unawaited(_playFromTheUntoldGround(_epoch));
  }

  /// A rehearsal picked back up remembers what of it was already told back.
  ///
  /// A team sent back to the rehearsal to record the end of the story leaves its resume
  /// point on the rehearsal, and the stretches it told stay the session's. Landing here
  /// without them, the next telling-back began at nought and sent the room every stretch
  /// a second time — the duplication the way back to the rehearsal exists to avoid, one
  /// leave-and-return later.
  void _keepTheStretchesAlreadyTold(BackTranslationProgress told) {
    if (told.nothingTold) return;
    state = state.copyWith(btTrechos: _trechosFrom(told.segments));
  }

  void conversaTap() {
    if (state.stage != SalaStage.conversa) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.playingReplyId != null) return;
    if (state.noteMode) {
      _noteTap();
      return;
    }
    switch (state.voice) {
      case VoiceState.invite:
      case VoiceState.listening:
      case VoiceState.done:
        _actOnConversaTap();
      case VoiceState.thinking:
      case VoiceState.speaking:
      case VoiceState.needsPerson:
      case VoiceState.offline:
      case VoiceState.blocked:
        break;
    }
  }

  void _actOnConversaTap() {
    if (_recordingStarting) return;
    if (_openingOwed) {
      unawaited(_askForTheOpeningAgain());
      return;
    }
    final isRecording = state.voice == VoiceState.listening;
    final elapsed = _listeningSince == null
        ? Duration.zero
        : DateTime.now().difference(_listeningSince!);
    switch (_captureGuard.decide(isRecording: isRecording, elapsed: elapsed)) {
      case TapDecision.start:
        _startListening('conversa_${_stamp()}');
      case TapDecision.stop:
        unawaited(_finishListening());
      case TapDecision.ignore:
        break;
    }
  }

  void _startListening(String fileName) {
    _silenceTheRoom();
    _recordingStarting = true;
    _listeningSince = DateTime.now();
    _keepTheConnectionWarm();
    // The line is kept, not dropped. `canHearAgain` already hides the button for every
    // voice but `invite`, so it is gone while the microphone is open either way — and
    // forgetting it here meant that when the room could only answer with a canned line,
    // the team had nothing at all to hear again.
    state = state.copyWith(voice: VoiceState.listening, peerCue: false);
    unawaited(_recordOrBlock(fileName));
  }

  bool _hasAudio(String path) =>
      File(path).existsSync() && File(path).lengthSync() > 0;

  void _keepTheConnectionWarm() {
    unawaited(_network.reachRoom());
    final every = ref.read(connectionRewarmIntervalProvider);
    if (every == null) return;
    _after('warm', every, () {
      if (state.voice == VoiceState.listening) _keepTheConnectionWarm();
    });
  }

  Future<void> _finishListening() async {
    final epoch = _epoch;
    final clock = TurnClock()..mark('stop');
    final path = await _recorder.stop();
    clock.mark('recorder');
    if (epoch != _epoch) return;
    final sessionId = state.sessionId;
    final elapsed = _listeningSince == null
        ? Duration.zero
        : DateTime.now().difference(_listeningSince!);
    final bytes = path == null
        ? 0
        : (File(path).existsSync() ? File(path).lengthSync() : 0);
    if (path == null ||
        !_captureGuard.accepts(duration: elapsed, bytes: bytes)) {
      // A take the guard would not have armed in the first place — too short, or too
      // light to be a real recording. Reading that as an ordinary return to the invite
      // is the same silence a phantom tap always deserved, never a fail-safe line.
      if (path != null) unawaited(_recorder.delete(path));
      state = state.copyWith(voice: VoiceState.invite);
      return;
    }
    if (sessionId == null) {
      state = state.copyWith(voice: VoiceState.invite);
      _haltForAPerson(sessionIsGone: true);
      unawaited(_recorder.delete(path));
      return;
    }
    _sayImThinking();
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    try {
      final clientTiming = _pendingClock?.clientTiming(_clockSegments);
      _pendingClock = clock;
      final turn = await _sendTheTake(
        sessionId,
        File(path),
        epoch,
        clientTiming: clientTiming,
      );
      await _voiceTurn(
        turn,
        epoch,
        clock: clock,
        onSoundStart: () => clock.mark('sound'),
      );
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  Future<TurnResult> _sendTheTake(
    String sessionId,
    File take,
    int epoch, {
    String? clientTiming,
  }) async {
    final turnId = _stamp();
    final window = ref.read(busyStateCeilingProvider);
    final backoff = ref.read(roomRetryBackoffProvider);
    final margin = ref.read(resendMarginProvider);
    final waited = ref.read(turnElapsedSourceProvider)();
    var resends = 0;
    Duration? timeout;
    while (true) {
      try {
        return await _room.sendTurn(
          sessionId,
          take,
          turnId: turnId,
          clientTiming: clientTiming,
          timeout: timeout,
        );
      } on Exception catch (error) {
        if (error is! RoomUnavailable && error is! RoomSlow) rethrow;
        if (window == null) rethrow;
        if (epoch != _epoch) rethrow;
        // A slow room answered, so it is there. A send that never reached it may have
        // lost a moment of the network or all of it, and only the network can say which:
        // with none at all this failed in milliseconds and was paused and resent for the
        // whole wait while the team watched thinking, where it had always gone offline
        // at once. Asked before the window is read, so the question's own seconds are
        // spent like any other.
        if (error is RoomUnavailable &&
            await _network.reachRoom() != RoomReach.fine) {
          rethrow;
        }
        final step = resends < backoff.length ? resends : backoff.length - 1;
        final pause = backoff[step];
        if (window - waited() - pause - margin < margin) rethrow;
        resends++;
        await Future<void>.delayed(pause);
        if (epoch != _epoch) rethrow;
        timeout = window - waited() - margin;
      }
    }
  }

  void _sayImThinking() {
    final line = rotated(instantAckLines, _ackSpoken++);
    unawaited(_voice.playAsset(fixedLineAsset(line, _lingua)));
  }

  Future<void> _pullInbox() async {
    final fetched = await _inbox.fetchReplies();
    if (fetched == null) return;
    if (_gone) return;
    final known = {for (final reply in state.replies) reply.id: reply};
    // The desk does re-send audio_url for a question_id it already served: a reply the
    // facilitator records again supersedes the first under a new content-hashed key and
    // comes back unheard, while the old address stops answering. Keeping the first
    // address seen played a 404 and marked the new reply heard without a sound.
    final merged = [
      for (final reply in fetched)
        if (known[reply.id] case final kept?
            when kept.audioUrl == reply.audioUrl)
          kept
        else
          reply,
    ];
    if (_sameReplies(merged, state.replies) && !state.questionPending) return;
    state = state.copyWith(
      replies: merged,
      questionPending: merged.isEmpty ? null : false,
    );
  }

  bool _sameReplies(List<HandReply> a, List<HandReply> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].audioUrl != b[i].audioUrl) return false;
    }
    return true;
  }

  void handTap() {
    // The hand lives on the convite and the conversa, but the outgoing screen stays
    // hit-testable for the 400 ms the switcher takes, so a finger already travelling
    // lands here from the next stage — and starts a question recording no screen shows
    // and no gesture stops.
    if (state.stage != SalaStage.conversa && state.stage != SalaStage.convite) {
      return;
    }
    if (state.stage == SalaStage.convite && _panoramaSessionId == null) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.needsPerson) return;
    if (state.playingReplyId != null) return;
    final unheard = state.oldestUnheardReply;
    if (unheard != null) {
      state = state.copyWith(playingReplyId: unheard.id);
      unawaited(_playReply(unheard));
      return;
    }
    if (state.noteMode) {
      _cancelQuestion();
      return;
    }
    // Only an idle voice is worth coming back to: a hand armed while the facilitator
    // was mid-sentence would otherwise write `speaking` back over a room where
    // nothing plays, and a circle that breaks on `speaking` stays dead until a person.
    _voiceBeforeQuestion = state.voice == VoiceState.done
        ? VoiceState.done
        : VoiceState.invite;
    state = state.copyWith(noteMode: true);
  }

  /// The circle's half of a question: it opens the microphone once the hand has armed
  /// the note, and closes and sends it on the touch after that.
  ///
  /// Splitting this off the hand is what keeps a question from ever starting under the
  /// facilitator's own voice — arming and recording used to be the same touch, so the
  /// first tap was already capturing whatever the facilitator was mid-sentence saying.
  void _noteTap() {
    switch (state.voice) {
      case VoiceState.invite:
      case VoiceState.done:
        _startListening('pergunta_${_stamp()}');
      case VoiceState.listening:
        _sendQuestion();
      case VoiceState.thinking:
      case VoiceState.speaking:
      case VoiceState.needsPerson:
      case VoiceState.offline:
      case VoiceState.blocked:
        break;
    }
  }

  /// Play the facilitator's answer, and let it go only once it has been heard.
  ///
  /// A reply is marked heard when the player reported the whole clip. A clip that cannot
  /// be decoded, is cut short, or never arrives stays unheard.
  ///
  /// It is offered again on the next touch of the hand, and the second failure at the
  /// same address sets it aside on the tablet: it stops counting as unheard, so the hand
  /// plays the next reply or arms a question. A clip that never decodes is served from
  /// the tablet's copy every time and would otherwise hold the gesture until the
  /// facilitator records it again. Nothing is marked, and the desk keeps showing the
  /// reply as not heard. The inbox is read again on the failure, as it is after a
  /// refused mark, and a reply recorded again arrives at its new address with no
  /// failures, which is what lifts the set-aside.
  ///
  /// A room that cannot serve the clip is one more way for an answer not to play, and it is
  /// treated the same way — never through `_handleRoomFailure`. The hand is a side
  /// channel: a halt raised over a reply would take the circle along with it.
  ///
  /// The playing mark is given back on every way out. `_markHeard` is what clears it when
  /// the reply sounded; a reply that did not, or that outlived its epoch, clears it here,
  /// or the hand, the circle and the convite all return early on it for good.
  Future<void> _playReply(HandReply reply) async {
    final epoch = _epoch;
    bool sounded;
    try {
      sounded = await _voice.play(reply.audioUrl);
    } on Exception {
      sounded = false;
    }
    final current =
        epoch == _epoch &&
        !state.replies.any(
          (kept) => kept.id == reply.id && kept.audioUrl != reply.audioUrl,
        );
    if (sounded && current) {
      unawaited(_markHeard(reply.id, audioUrl: reply.audioUrl));
      return;
    }
    if (!_gone && state.playingReplyId == reply.id) {
      state = state.copyWith(clearPlayingReply: true);
    }
    if (current) {
      state = state.copyWith(replies: _unsounded(reply));
      unawaited(_pullInbox());
    }
  }

  List<HandReply> _unsounded(HandReply reply) => [
    for (final kept in state.replies)
      if (kept.id == reply.id && kept.audioUrl == reply.audioUrl)
        kept.asUnsounded()
      else
        kept,
  ];

  /// A reply is heard when the desk agrees, and not before.
  ///
  /// The mark was made on the tablet whatever the desk answered, and it survives only as
  /// long as the screen does: rebuilt state reads the reply back from the desk, which
  /// never learned, and the team is played the same answer again. Leaving it unheard is
  /// the honest state — it is offered again, which is a small harm and self-correcting.
  ///
  /// No retry. The precedent for a call that must land is the one that asks for a person,
  /// and it retries because nobody comes if it is lost. Nothing is lost here: the reply
  /// stays in the desk's list and the next tap marks it again. An unbounded retry on
  /// bookkeeping buys nothing and is not free.
  ///
  /// The mark and the gesture move together, and the mark is taken back if the desk
  /// disagrees. Releasing the gesture first and marking afterwards opened a window as long
  /// as the request: the hand was free again while the reply still read as unheard, so a
  /// second touch played the same answer to the team and sent a second mark. That is the
  /// replay this whole change exists to stop, through a door of its own making.
  ///
  /// The other way to close it was to hold the gesture until the desk answered, and it
  /// costs more than it saves: up to the full timeout with the hand dead, and the hand is
  /// the team's only one — they could not even raise a question meanwhile. This way the
  /// room is briefly optimistic, for as long as one request, and corrects itself. That is
  /// a different animal from the optimism this slice removes, which outlived the request
  /// and died only with the screen, leaving the desk to contradict it on the next start.
  ///
  /// A refusal also pulls the inbox. The one refusal the desk makes on purpose is that the
  /// reply moved on: the facilitator recorded again while this one played, and the address
  /// the tablet holds has stopped answering. The inbox is otherwise read thirty seconds
  /// after a turn, and not at all while the room sits on the convite, so without this pull
  /// the hand kept offering a clip that sounds nothing and marks nothing. The answer is a
  /// bool that cannot tell that refusal from an outage, so every refusal pulls; a pull is
  /// one GET, and after an outage it changes nothing.
  Future<void> _markHeard(String replyId, {required String audioUrl}) async {
    final epoch = _epoch;
    state = state.copyWith(
      replies: _replies(replyId, heard: true),
      clearPlayingReply: true,
    );
    if (await _inbox.markHeard(replyId, audioUrl: audioUrl)) return;
    if (_gone || epoch != _epoch) return;
    state = state.copyWith(replies: _replies(replyId, heard: false));
    unawaited(_pullInbox());
  }

  List<HandReply> _replies(String replyId, {required bool heard}) => [
    for (final reply in state.replies)
      if (reply.id != replyId)
        reply
      else if (heard)
        reply.asHeard()
      else
        HandReply(id: reply.id, audioUrl: reply.audioUrl),
  ];

  void _cancelQuestion() {
    unawaited(_recorder.discard());
    state = state.copyWith(noteMode: false, voice: _voiceBeforeQuestion);
  }

  void _sendQuestion() {
    if (!state.noteMode) return;
    state = state.copyWith(noteMode: false, voice: VoiceState.thinking);
    _watchBusyState();
    unawaited(_deliverQuestion());
  }

  Future<void> _deliverQuestion() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final sessionId = state.stage == SalaStage.convite
        ? _panoramaSessionId
        : state.sessionId;
    if (path == null || !_hasAudio(path) || sessionId == null) {
      // The team raised their hand, spoke a question, and nothing came back from the
      // recorder. Returning to the invite in silence is the room forgetting they asked.
      state = state.copyWith(voice: _voiceBeforeQuestion, noteMode: false);
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    try {
      await _inbox.sendQuestion(sessionId, File(path));
      if (epoch != _epoch) return;
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
      return;
    }
    unawaited(_recorder.delete(path));
    state = state.copyWith(
      handAck: true,
      questionPending: true,
      voice: _voiceBeforeQuestion,
    );
    _watchBusyState();
    _after('ack', const Duration(milliseconds: 3200), () {
      state = state.copyWith(handAck: false);
    });
  }

  void devRecomecarPassagem() {
    if (!Env.devPularFases) return;
    final pericope = _emCurso;
    if (pericope == null) return;
    // The one discarded erasure that stays discarded: this is behind `devPularFases`, on
    // no team's path, and the entry it drops is rewritten by the fresh entry two lines
    // down. There is nobody here to speak to.
    unawaited(_emAberto.forget(_book, pericope).catchError((_) {}));
    unawaited(goConversa(pericope: pericope, fresh: true));
  }

  void devTrocarIdioma() {
    if (!Env.devPularFases) return;
    final knob = ref.read(devLanguageProvider.notifier);
    knob.choose(knob.next(_lingua));
    if (state.stage == SalaStage.convite) {
      if (_panoramaSessionId != null) unawaited(_reabrirPanoramaNaLingua());
      return;
    }
    _startOver();
  }

  Future<void> _reabrirPanoramaNaLingua() async {
    _clearAll();
    _conviteOpened = true;
    _panoramaSessionId = null;
    state = state.copyWith(
      conviteStep: ConviteStep.boasVindas,
      voice: VoiceState.thinking,
      noteMode: false,
    );
    _watchBusyState();
    final epoch = _epoch;
    final reach = await _network.reachRoom();
    if (epoch != _epoch) return;
    if (reach != RoomReach.fine) {
      _conviteOpened = false;
      _goOffline(reach);
      return;
    }
    _watchBusyState();
    try {
      final created = await _room.createSession(
        pericope: panoramaPericope,
        language: _lingua,
      );
      if (epoch != _epoch) return;
      _conviteOpened = false;
      if (!isThePanorama(created.pericope)) {
        state = state.copyWith(voice: VoiceState.invite);
        return;
      }
      _panoramaSessionId = created.sessionId;
      unawaited(openConvite());
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _conviteOpened = false;
      _handleRoomFailure(error, turnCall: true);
    }
  }

  void goEnsaio() {
    _rememberWhereTheyAre(SalaStage.ensaio);
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      peerCue: false,
    );
  }

  void playTheRehearsal() {
    if (state.playPing) {
      _depoisDaPausa = null;
      _holdClip();
      state = state.copyWith(playPing: false, takePaused: true);
      return;
    }
    if (state.takePaused) {
      final seguir = _depoisDaPausa;
      _depoisDaPausa = null;
      state = state.copyWith(playPing: true, takePaused: false);
      if (seguir != null) {
        seguir();
        return;
      }
      _letTheClipRun();
      return;
    }
    if (!state.canPlayTheRehearsal) return;
    state = state.copyWith(playPing: true, takePaused: false);
    _ensaioATocar = _oEnsaioAteAqui();
    _tocarDoEnsaio(0);
  }

  void _tocarDoEnsaio(int onde) {
    void acabou() {
      state = state.copyWith(
        playPing: false,
        takePaused: false,
        clearParteDoEnsaioTocando: true,
      );
    }

    void aProxima() {
      if (state.takePaused) {
        _depoisDaPausa = () => _tocarDoEnsaio(onde + 1);
        return;
      }
      if (!state.playPing) return;
      _tocarDoEnsaio(onde + 1);
    }

    if (onde >= _ensaioATocar.length) {
      acabou();
      return;
    }
    final (path, trecho, parte) = _ensaioATocar[onde];
    state = state.copyWith(parteDoEnsaioTocando: parte);
    if (trecho == null) {
      _play(path, onComplete: aProxima, onFailed: acabou);
      return;
    }
    _clipHeld = false;
    _onPlaybackComplete = aProxima;
    _onPlaybackFailed = acabou;
    _listenForTheEnd();
    unawaited(_playback.playRange(path, trecho.$1, trecho.$2));
    _watchPlayback(clipStillOpening: true);
  }

  /// A tap on one bead: that part alone, from its start, stopping at its own end.
  ///
  /// Tapping the part already sounding toggles pause the same way the play/pause circle
  /// does — [playTheRehearsal] already carries that logic, and duplicating it here would
  /// drift from it the first time either one changed. Tapping a different part stops
  /// whatever is in the air and starts this one instead of resuming it.
  ///
  /// A dimmed bead — one of the others while a record-again sent by a finding stands open,
  /// not yet recorded — does not apply, so a tap on it does nothing (ADR 0040). Once that
  /// recording is pending (waiting for the green check), every bead plays as usual: the
  /// team can hear what they recorded before deciding to keep it.
  void tocarAParte(int indice) {
    if (state.stage != SalaStage.ensaio) return;
    if (state.needsPerson) return;
    if (state.ensaio == EnsaioStatus.recording) return;
    if (indice < 0 || indice >= state.partes.length) return;
    if (state.beadIsDimmed(indice)) return;
    if (indice == state.parteDoEnsaioTocando) {
      playTheRehearsal();
      return;
    }
    _silenceTheRoom();
    _ensaioATocar = [
      for (final clip in _clipesDaParte(indice)) (clip.$1, clip.$2, indice),
    ];
    state = state.copyWith(
      playPing: true,
      takePaused: false,
      parteDoEnsaioTocando: indice,
    );
    _tocarDoEnsaio(0);
  }

  List<(String, (Duration, Duration)?, int)> _oEnsaioAteAqui() {
    final partes = state.partes;
    final pendente = _pendingTakePath;
    final regravada = state.parteARegravar;
    final noLugar =
        pendente != null && regravada != null && regravada < partes.length;
    return [
      for (var parte = 0; parte < partes.length; parte++)
        for (final clip in _clipesDaParte(parte)) (clip.$1, clip.$2, parte),
      if (pendente != null && !noLugar) (pendente, null, partes.length),
    ];
  }

  /// What plays for one part of the rehearsal: the pending take standing in its place when
  /// this is the part the team came back to record again, or its own recording and the
  /// stretches told back over it otherwise.
  List<(String, (Duration, Duration)?)> _clipesDaParte(int parte) {
    final pendente = _pendingTakePath;
    if (pendente != null && state.parteARegravar == parte) {
      return [(pendente, null)];
    }
    return _oQueTocaDaParte(parte);
  }

  List<(String, (Duration, Duration)?)> _oQueTocaDaParte(int parte) {
    // The retro's own stretches, once it has any, are the passage: a correction lives in
    // one of them and nowhere among the raw parts, so hearing the passage means hearing
    // them, in the order the necklace already holds them.
    final trechos = [
      for (final trecho in state.btTrechos)
        if (trecho.parte == parte) trecho,
    ];
    if (trechos.isEmpty) return [(state.partes[parte].path, null)];
    return [
      for (final trecho in trechos)
        if (_ondeTocar(trecho) case (final path, final from, final to))
          (path, (from, to)),
    ];
  }

  void ensaioTap() {
    if (state.needsPerson || state.playPing) return;
    switch (state.ensaio) {
      case EnsaioStatus.idle:
      case EnsaioStatus.recorded:
        _silenceTheRoom();
        state = state.copyWith(ensaio: EnsaioStatus.recording);
        unawaited(_recordOrBlock('ensaio_tomada_${_stamp()}'));
      case EnsaioStatus.recording:
        unawaited(_finishTake());
    }
  }

  EnsaioStatus get _semGravacaoAberta =>
      _pendingTakePath == null ? EnsaioStatus.idle : EnsaioStatus.recorded;

  /// The part is only pending once the recorder has handed the file back.
  ///
  /// Flipping to `recorded` first lit the check while `stop()` was still writing, and a
  /// quick check found no path and dropped the take without a word. Staying in
  /// `recording` for those few frames is also the truer thing to show.
  Future<void> _finishTake() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    if (path == null || !_hasAudio(path)) {
      // Nothing came back. A check over a take that does not exist let a team confirm a
      // rehearsal into nothing — no bead appeared, and the way to the retro never opened.
      state = state.copyWith(ensaio: _semGravacaoAberta);
      _haltForAPerson();
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    final substituida = _pendingTakePath;
    _pendingTakePath = path;
    if (substituida != null) unawaited(_recorder.delete(substituida));
    state = state.copyWith(
      ensaio: EnsaioStatus.recorded,
      playPing: false,
      takePaused: false,
    );
  }

  void takeKeep() {
    _silenceTheRoom();
    final path = _pendingTakePath;
    _pendingTakePath = null;
    if (path == null) {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      return;
    }
    final regravada = state.parteARegravar;
    state = state.copyWith(clearParteARegravar: true);
    if (regravada != null && regravada < state.partes.length) {
      _aParteVoltaAoSeuLugar(regravada, path);
      return;
    }
    // Counted among the rehearsal's own parts, never among the corrections a trecho may
    // already have picked up in this same ensaio — those live in keptTakes too, but are
    // not parts of the rehearsal in their own right.
    final parte = state.partes.length + 1;
    final escopo = KeptScope.parte(parte);
    final nova = KeptTake(scopeId: escopo, path: path);
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [...state.keptTakes, nova],
      takes: parte,
    );
    unawaited(
      _guard(
        path,
        kind: 'ensaio',
        scope: escopo,
        passNumber: nova.pass,
        chunkIndex: parte,
      ),
    );
    _rememberWhereTheyAre(SalaStage.ensaio);
  }

  /// The recording the team just made takes the place of the part it was made for.
  ///
  /// The same scope and the same number, because a stretch addresses its part by where
  /// the part sits in the row: a part that moved would take the whole rehearsal with it.
  /// What changes is the file, and with it the name — null until the upload lands — and
  /// the listening, which is kept by file and so starts over with nothing to clear.
  ///
  /// The stretches told over the recording this one replaces go with it. Left standing,
  /// they would stand over ground nobody has explained yet and the next telling-back would
  /// step over a part the team has not heard. They leave as untold ground and not as
  /// drained beads: a drained bead means waiting to be mended, and this ground is waiting
  /// to be told.
  ///
  /// The recording goes up under the count after the one the part it replaces went up
  /// with. Under the same count the room has only arrival to choose between the two, and
  /// the upload of the recording the team abandoned can be the one that lands last.
  ///
  /// The part's own recording is left on the tablet. Nothing points at it any more, and
  /// deleting audio a team recorded is not a thing this room does quietly.
  void _aParteVoltaAoSeuLugar(int parte, String path) {
    // Scope and number are counted from the same place, because they are the same fact
    // said twice and the room is sent both. Read apart — the scope off the take, the
    // number off the row — a row the two disagree about would send a recording up under
    // one part's name and another part's number.
    final numero = parte + 1;
    final escopo = KeptScope.parte(numero);
    final passada = state.partes[parte].pass + 1;
    final trechos = [
      for (final trecho in state.btTrechos)
        if (trecho.parte != parte) trecho,
    ];
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [
        for (final take in state.keptTakes)
          if (take.scopeId == escopo)
            KeptTake(scopeId: escopo, path: path, pass: passada)
          else
            take,
      ],
      btTrechos: trechos,
    );
    unawaited(_medirAParteRegravada(path, _epoch));
    unawaited(
      _guard(
        path,
        kind: 'ensaio',
        scope: escopo,
        passNumber: passada,
        chunkIndex: numero,
      ),
    );
    _rememberWhereTheyAre(SalaStage.ensaio);
  }

  /// The parts end where they now do, and this part is a file of its own length. Measured
  /// here rather than left to the next playthrough, because the part must not go on being
  /// read at the length of the recording it replaces.
  Future<void> _medirAParteRegravada(String arquivo, int epoch) async {
    final quanto = await _playback.howLong(arquivo);
    if (quanto == null || epoch != _epoch || _gone) return;
    _marcarOFimDaParte(arquivo, quanto.inMilliseconds);
    state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
  }

  /// Throw away a take that was recorded and never kept.
  ///
  /// Leaving a passage used to abandon the file instead: not deleted, so it stayed on the
  /// tablet forever, and not queued, so nothing would ever send it. An orphan is the one
  /// outcome that is neither of the two things the team asked for.
  void _dropThePendingTake() {
    final path = _pendingTakePath;
    if (path == null) return;
    _pendingTakePath = null;
    unawaited(_recorder.delete(path));
  }

  /// The rehearsal recordings still waiting for the room to name them, by the row that
  /// carries each one.
  ///
  /// A row that did not land on the flush its keep ran — refused, or held behind an
  /// earlier recording of its own part — lands on a later one, and the take has to learn
  /// its name then. Kept by row and not by scope, for the reason `takeIdOf` gives.
  final Map<String, String> _semNome = {};

  Future<void> _guard(
    String path, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    if (_gone) return;
    final queue = _takes;
    final sessionId = state.sessionId;
    final audio = File(path);
    if (!await audio.exists()) return;
    if (sessionId == null) {
      // The room lost the session — a 404 clears it — and a take has nowhere to go
      // without one. The bead had already been filled by `takeKeep`, so this returned in
      // silence and the recording read as delivered.
      _sayARecordingIsStranded();
      return;
    }
    final PendingTake linha;
    try {
      linha = await queue.enqueue(
        audio,
        sessionId: sessionId,
        kind: kind,
        scope: scope,
        passNumber: passNumber,
        chunkIndex: chunkIndex,
      );
    } on Object {
      // A full disk throws here, on the copy or on the manifest write. It used to be an
      // unhandled async error behind an `unawaited`: the screen kept its beads and the
      // room went on as if the recording were queued.
      _sayARecordingIsStranded();
      return;
    }
    if (kind == 'ensaio') _semNome[linha.id] = path;
    if (kind == 'retro') _traducaoNaFila[path] = linha;
    await _countUnsent();
    await queue.flush();
    await _countUnsent();
    await _adoptTheNames(queue);
  }

  /// Take a guarded translation off the outbox, for a path the room will never send
  /// as a whole-passage take: one recorded over after a refusal, or one told again
  /// that has since landed by its own door.
  Future<void> _retirarDaFilaSeGuardada(String path) async {
    final linha = _traducaoNaFila.remove(path);
    if (linha == null) return;
    try {
      await _takes.withdraw(linha);
    } on Object catch (error) {
      // Nothing here is stuck: a manifest write that failed leaves the row pending
      // and it still goes up, an upload the team never asked twice for but Henok
      // accepted; a delete that failed after the write leaves only an orphaned copy
      // behind. Neither is the silence `_sayARecordingIsStranded` speaks for, so this
      // is logged and dropped the way `_porCadaTrechoNaSuaParte`'s own read failure
      // already is.
      debugPrint(
        'Uma tradução guardada não pôde ser retirada da fila ($path): $error',
      );
      return;
    }
    await _countUnsent();
  }

  /// Take back the names the room gave the rehearsal recordings this tablet made.
  ///
  /// A told-back stretch is a slice of one recording and says which, and this is the only
  /// moment those names are said for recordings this tablet made. A rehearsal whose files
  /// are not here any more is fetched back from the room, and those parts arrive already
  /// named by it, so there is nothing to adopt for them.
  ///
  /// Every flush, not only the one the keep ran: a recording the room refused, or one
  /// held behind an earlier recording of its own part, lands later, and a part still
  /// nameless sends every stretch told over it up as a telling of the whole passage.
  ///
  /// The name goes to the file it was given for, never to every take of the scope: a part
  /// recorded again shares its scope with the recording it replaced, and the row is what
  /// tells the two apart.
  Future<void> _adoptTheNames(TakeUploadQueue queue) async {
    for (final linha in _semNome.keys.toList()) {
      final id = await queue.takeIdOf(linha);
      if (_gone) return;
      if (id == null) continue;
      final arquivo = _semNome.remove(linha);
      state = state.copyWith(
        keptTakes: [
          for (final take in state.keptTakes)
            if (take.path == arquivo) take.withTakeId(id) else take,
        ],
      );
    }
  }

  Future<void> refreshUnsent() => _countUnsent();

  Future<void> _recordOrBlock(String fileName) async {
    final epoch = _epoch;
    final start = ++_starts;
    final openedAsAChunkCapture = state.btPhase == BtPhase.capturing;
    final draft =
        state.ensaio == EnsaioStatus.recording || openedAsAChunkCapture;
    _micWatch ??= _recorder.interrupted.listen(_theMicrophoneChangedHands);
    final capture = await _recorder.start(fileName, draft: draft);
    if (_gone) return;
    // The answer can arrive a minute late — `hasPermission` waits up to sixty seconds for
    // the platform — by which time the team may be on another stage entirely, with a
    // microphone of its own still opening. Cleared under the guard, never above it: a
    // start coming back from a passage already left let the next passage's second tap
    // through, onto a recorder that had not opened.
    if (epoch != _epoch) {
      if (start == _starts && capture == Capture.started) {
        _recordingStarting = false;
        unawaited(_recorder.discard());
      }
      return;
    }
    _recordingStarting = false;
    switch (capture) {
      case Capture.started:
        _captureFails = 0;
        // A halt landing while this start was still in the air ran its own discard
        // early, on a recorder that had not opened yet, and left the phase in
        // `playing`. The recorder only just answered, and nothing else will ever
        // close it. `btPhase` only means anything for a chunk capture — checked here
        // too, or every ordinary start outside the retro would read as one discarded.
        if (openedAsAChunkCapture && state.btPhase != BtPhase.capturing) {
          unawaited(_recorder.discard());
        }
        return;
      case Capture.denied:
        // Unwound as well: the gate replaces the screen, but the state underneath it is
        // what the team comes back to, and it said the room was recording.
        _undoTheListening();
        ref.read(micPermissionProvider.notifier).refuse();
      case Capture.failed:
        _theRecorderNeverStarted();
    }
  }

  void _theMicrophoneChangedHands(bool taken) {
    state = state.copyWith(micTaken: taken);
  }

  /// Put back whatever the caller set before it asked for a microphone.
  void _undoTheListening() {
    final capturing = state.btPhase == BtPhase.capturing;
    state = state.copyWith(
      ensaio: _semGravacaoAberta,
      noteMode: false,
      btPhase: capturing ? BtPhase.playing : state.btPhase,
      voice: state.canResolveWithPerson ? null : VoiceState.invite,
    );
    // The retro's clip was paused for the telling-back that never started. Its sibling
    // `_finishChunkCapture` resumes it; this path left it frozen with the halo running.
    if (capturing) state = state.copyWith(btClipRodando: false);
  }

  /// The screen already said the room was listening, and it was not.
  ///
  /// Every caller sets its own state before this runs, so a recorder that never started
  /// left the circle gathering over a microphone that was off. The team performs the
  /// whole passage into it and loses it.
  void _theRecorderNeverStarted() {
    _undoTheListening();
    _captureFails++;
    if (_captureFails >= _captureFailsBeforeAPerson) _haltForAPerson();
  }

  /// Which recount is the newest one asked for.
  ///
  /// Six things ask for the count and four of them do not wait, so two recounts can be
  /// reading the disk at once. Whichever published last used to win whatever it had read,
  /// which let a reading taken before the queue drained overwrite one taken after it: the
  /// team was shown recordings still waiting that had already gone.
  ///
  /// The problem here is ordering a result, not overlapping a run, and this orders the
  /// result. Serialising was the other shape on offer — the upload queue holds a flag
  /// against two flushes overlapping and a chained future against manifest writes landing
  /// out of order — and neither fits. A flag that skips a recount because one is already
  /// running drops the very trigger that knew the disk had just changed, and a count
  /// frozen at a stale value looks exactly like an app with nothing left to send. A chain
  /// makes every trigger in a burst read the disk again in turn to produce a number only
  /// the last of them will ever show. Taking a number on the way in and publishing only
  /// while it is still the newest lets all six triggers run and lets the stale readings
  /// fall on the floor.
  ///
  /// This is not the epoch guard below it and does not replace it. That one is about a
  /// session that has ended publishing over the one that replaced it — a different
  /// question, and still asked.
  int _newestCount = 0;

  Future<void> _countUnsent() async {
    if (_gone) return;
    final epoch = _epoch;
    final counting = ++_newestCount;
    final queue = _takes;
    final sessionId = state.sessionId;
    // Whether a recording is stuck is not a question about the session in progress, and
    // asking it only when one existed meant the check at the first frame — the moment a
    // facilitator is standing there and could act — did nothing at all.
    final tally = await queue.tally(sessionId: sessionId);
    if (_gone) return;
    if (tally.stranded && epoch == _epoch) _sayARecordingIsStranded();
    if (epoch != _epoch) return;
    if (sessionId == null) return;
    if (_gone || epoch != _epoch || counting != _newestCount) return;
    state = state.copyWith(
      unsentTakes: tally.unsentTakes,
      unsentChunks: tally.unsentChunks,
      unsentTakeScopes: tally.unsentTakeScopes,
    );
  }

  /// Mind the team's place on disk, and say so when the disk will not take it.
  ///
  /// This tablet is the only thing that knows which session belongs to which passage —
  /// `ir_sessions` carries no device — so a write that fails and is thrown away loses the
  /// team's place with nothing left to recover it from and no sign anything went wrong.
  /// It is the same disk, and the same silence, the upload queue used to have when it
  /// could not store audio, so it borrows that voice instead of inventing a second one.
  ///
  /// An erasure that fails is spoken too. It leaves a stale entry, which is a different
  /// harm from losing the place and not a smaller one: the wheel goes on offering a
  /// passage the team already closed, and walking back into it resumes a session the
  /// server has forgotten. Nothing else in the room ever notices that entry, so if this
  /// does not say it, no one does.
  Future<void> _mindingThePlace(Future<void> Function() write) async {
    try {
      await write();
    } on Object {
      _sayARecordingIsStranded();
    }
  }

  void _sayARecordingIsStranded() {
    if (_strandedSpoken || _gone) return;
    _strandedSpoken = true;
    unawaited(_voice.playAsset(strandedTakeAsset(_lingua)));
  }

  void startRetro() {
    if (state.stage == SalaStage.ensaio && state.ensaio != EnsaioStatus.idle) {
      return;
    }
    // Before the write, not after: the mark belongs to the Rehearsal alone, and a row
    // saved for the retro must never carry one to restore.
    _clearAll();
    _rememberWhereTheyAre(SalaStage.retro);
    state = state.copyWith(
      stage: SalaStage.retro,
      voice: VoiceState.invite,
      btPhase: BtPhase.playing,
      btChunkFailures: const [],
      btClipEnded: false,
      btPass: 1,
      peerCue: false,
    );
    _descartarATraducaoPendente();
    unawaited(_playFromTheUntoldGround(_epoch));
  }

  /// How far into this recording the stretches somebody has explained reach.
  ///
  /// Not [_ondeParouNesteArquivo]: that one moves the cursor and counts every stretch,
  /// including a half born of a division that nobody has told back yet — which is right
  /// for the cursor, since that half is reached by the finding that names it, and wrong
  /// for stepping over a part, which must not skip ground still waiting for its telling.
  Duration _chaoExplicadoDe(int parte) {
    var ate = Duration.zero;
    for (final trecho in state.btTrechos) {
      if (trecho.parte == parte && trecho.contado && trecho.lugarTo > ate) {
        ate = trecho.lugarTo;
      }
    }
    return ate;
  }

  /// Play the rehearsal from the first ground nobody has told back yet.
  ///
  /// A retro entered over stretches already told — a team that went back to record the
  /// end of the story, or picked the passage up again — used to start over: the stretches
  /// were forgotten here, the clip played from nought, and every cut sent the room one
  /// more stretch over ground it already held, so the analyst read the passage twice. The
  /// stretches stay, and the parts they cover whole are stepped over — all but the last,
  /// which is played with the cursor at the end of its told ground when there is nothing
  /// left to tell, so the clip still reaches its end and the advance disc still lights.
  ///
  /// A part is covered whole when the told ground reaches its length, measured without
  /// playing it. A part that cannot be measured is not stepped over — it is put in the
  /// air like any other part picked back up, at the cursor its told ground leaves, so the
  /// team hears whatever of it is still untold and nothing that is not.
  ///
  /// The parts stepped over are reported as heard. The room's gate wants evidence that
  /// the rehearsal was heard end to end before it reads the passage, and the team did hear
  /// these parts, when it told them back — in the round before this one. Reported as this
  /// round's listening alone, the gate would refuse a passage whose every stretch is told,
  /// and the only way through it would be hearing the whole story again, which is the
  /// "the old ones come back" this path exists to avoid. The gate does not know the rounds
  /// apart, so this client tells it a truth about the rehearsal rather than about the
  /// round; whoever changes the gate needs to know this client leans on it that way.
  Future<void> _playFromTheUntoldGround(int epoch) async {
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _parteJaTocou = false;
    _tamanhoDaParteMs.clear();
    _pousadaNaParteApontadaPelaRecusa = false;
    _cabecaForaDoPlayer = null;
    _escuta.esquecerTudo();
    _desdeMs = 0;
    state = state.copyWith(
      clearFindingSegment: true,
      btTrechoTocando: false,
      btParteFronteira: false,
      btClipRodando: false,
      btFimDasPartesMs: const [],
      btParteNoArMs: 0,
      btOuvidoMs: 0,
    );
    final partes = state.partes;
    if (partes.isEmpty) {
      // No rehearsal to tell back is not a rehearsal that finished playing. Calling it
      // one would open the check over an empty back translation.
      _haltForAPerson();
      return;
    }
    // Measuring waits on the player, and the screen it waits under is the retro with its
    // buttons up: a cut landing inside the wait opened the microphone over a clip about to
    // start, with the cursor at nought. Busy is the honest state for it.
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    await _medirAsPartes(partes, epoch);
    if (epoch != _epoch || _gone) return;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      // Only out of the wait this method itself opened. A halt raised while the player was
      // measuring is the room's state now, and the invite put back over it let a blocked
      // room out of a halt nobody at the desk had attended.
      voice: state.voice == VoiceState.thinking
          ? VoiceState.invite
          : state.voice,
      btFimDasPartesMs: _fimDaParteMs,
    );
    // The row is read again: this runs unawaited, and a part that left it while the player
    // measured would be indexed out of a list that no longer holds it. A row that emptied
    // meanwhile is the same room as one that arrived empty, and gets the same answer.
    final medidas = state.partes;
    if (medidas.isEmpty) {
      _haltForAPerson();
      return;
    }
    // How long each part is was answered above, for every part at once: read one part at a
    // time as this walked, nothing past the first part still to be told could be measured.
    var parte = 0;
    while (parte < medidas.length - 1) {
      final contadaAte = _chaoExplicadoDe(parte);
      if (contadaAte == Duration.zero) break;
      final medido = _tamanhoDaParteMs[medidas[parte].path];
      if (medido == null ||
          (contadaAte + folgaDoFimDaParte).inMilliseconds < medido) {
        break;
      }
      _escuta.inteira(medidas[parte].path, medido);
      parte++;
    }
    // A blocking halt withholds the sound and nothing else: putting a part in
    // the air here would silence the room on the way, cutting off the one call for a
    // person, which is said once. Which part, and what the team already heard of the ones
    // before it, are answered either way — a halt that skipped them would report none of
    // the rehearsal as heard and land the team back on its first part.
    if (state.needsPerson) {
      _parteTocando = parte;
      return;
    }
    _tocarParteDaRetro(parte);
  }

  /// Where each part ends along the rehearsal, the parts glued end to end in the order they
  /// were recorded, up to the first one nobody has measured yet.
  List<int> get _fimDaParteMs {
    final fins = <int>[];
    var ate = 0;
    for (final parte in state.partes) {
      final quanto = _tamanhoDaParteMs[parte.path];
      if (quanto == null) break;
      fins.add(ate += quanto);
    }
    return fins;
  }

  /// Where [parte] begins along the rehearsal: what the parts before it add up to, as far as
  /// they have been measured. A part nobody has measured adds nothing, so this cannot
  /// overrun the way reading the ruler by index did.
  int _inicioDaParteMs(int parte) {
    final partes = state.partes;
    var ate = 0;
    for (var antes = 0; antes < parte && antes < partes.length; antes++) {
      ate += _tamanhoDaParteMs[partes[antes].path] ?? 0;
    }
    return ate;
  }

  /// Where a position inside the part in the air sits along the parts glued end to end:
  /// the only place the offset is added.
  int _pontoNoColar(int local) => _inicioDaParteMs(_parteTocando) + local;

  /// Write down how long [arquivo] turned out to be, once it has measured itself.
  ///
  /// A nought is the player with nothing to say about the file, never a part of no length:
  /// written to the ruler it squeezes that part to nothing instead of ending the ruler
  /// there, which is the one thing the ruler promises not to do.
  void _marcarOFimDaParte(String arquivo, int medido) {
    if (medido <= 0) return;
    _tamanhoDaParteMs[arquivo] = medido;
  }

  /// How far into this recording the telling-back already got.
  ///
  /// The cursor belongs to the file in the air, not to the passage: crossing into a part
  /// starts it at that part's beginning, and a part picked back up starts it after the
  /// last stretch told out of it.
  Duration _ondeParouNesteArquivo(int parte) {
    var ate = Duration.zero;
    for (final trecho in state.btTrechos) {
      if (trecho.parte == parte && trecho.lugarTo > ate) ate = trecho.lugarTo;
    }
    return ate;
  }

  void _seguirOClipe() {
    _desdeMs = _playback.position.inMilliseconds;
    final arquivo = _parteNoAr?.path;
    if (arquivo != null) {
      _escuta.abrir(arquivo, _playback.position.inMilliseconds);
    }
    state = state.copyWith(btClipRodando: true);
    _letTheClipRun();
  }

  /// Stop the rehearsal and write down how far it got.
  ///
  /// [ate] is the true end of a part, which the part's own duration knows better than the
  /// player's position at the moment it finished. Both it and the player's answer are
  /// positions inside the file in the air: the ledger is never handed a place along the rehearsal.
  void _pararOClipe({int? ate}) {
    _holdClip();
    _anotarOQueFoiOuvido(ate: ate);
  }

  /// Write down how far the rehearsal got, and close the span the ledger has open on the
  /// part in the air. Shared by a hold and by the one silence, so a transition closes a
  /// span exactly the way a hold does.
  void _anotarOQueFoiOuvido({int? ate}) {
    var ondeParou = state.btOuvidoMs;
    if (state.btClipRodando) {
      final fim = ate ?? _playback.position.inMilliseconds;
      final arquivo = _parteNoAr?.path;
      if (arquivo != null) _escuta.fechar(arquivo, fim);
      ondeParou = _pontoNoColar(fim > _desdeMs ? fim : _desdeMs);
    }
    state = state.copyWith(btClipRodando: false, btOuvidoMs: ondeParou);
  }

  void _medirAParteNoAr() {
    if (state.stage != SalaStage.retro) return;
    if (!state.btClipRodando) return;
    final medida = _playback.playingLength;
    if (medida == null) return;
    state = state.copyWith(btParteNoArMs: medida.inMilliseconds);
  }

  /// Put a part in the air, at the cursor it already has.
  ///
  /// The sound starts where the telling-back stopped inside this file, so a part picked
  /// back up does not make the team sit through the ground they told in the round before.
  /// It used to start at nought with the cursor already ahead of it, and everything the
  /// team could do in that stretch was refused: the scissors read a playhead behind the
  /// cursor and said nothing.
  ///
  /// A part nobody has told back has its cursor at nought, so this is the ordinary start
  /// for every part of a rehearsal being told back for the first time.
  ///
  /// What is reported as heard is **not** moved with it: the heard span still opens at the
  /// part's own nought. The room's gate asks of each part what the team has heard of *that
  /// part*, across every round — it wants a cover from nought to the end of that part, it
  /// refuses a part reported empty, and it keeps only the last report sent, so nothing an
  /// earlier round said is still standing. The ground this part was told back on *was*
  /// heard, in the round that told it; this is the same truth [_playFromTheUntoldGround]
  /// tells about the parts it steps over, and the app is the only one who can tell it.
  /// Opening at the cursor left the picked-up part's own beginning uncovered and the
  /// finish was refused.
  ///
  /// [doComeco] sounds it from its own nought instead, for the one gesture whose whole
  /// subject is hearing rather than telling. The **Cursor** does not move with it: it is
  /// where the next cut begins, and a cut is about telling. Taken back to nought with the
  /// playhead, the first cut after the landing would hand the room the ground the team
  /// already told as one new stretch — their own telling, given back a second time, which
  /// is the failure [_walkTheCursorBack] exists to undo.
  ///
  /// [semChaoTraduzido] moves the cursor to that same nought instead of reading it off the
  /// told ground: the landing on an untold part has none, whether a fresh recording, whose
  /// file nothing has told yet, or a part whose surviving stretches still name the take it
  /// replaced. Only this landing sets it; every other caller reads the natural cursor.
  void _tocarParteDaRetro(
    int parte, {
    bool doComeco = false,
    bool semChaoTraduzido = false,
    bool noCursor = false,
    Duration? desde,
  }) {
    // Every way a part goes in the air passes here — the crossing at a boundary, the
    // last listening of a checked passage, the next part, the landing on one nobody
    // heard — and none of them may start it under the line the Guide is still saying.
    _silenceTheRoom();
    _cabecaForaDoPlayer = null;
    _parteTocando = parte;
    if (!noCursor) {
      _trechoStart = semChaoTraduzido
          ? Duration.zero
          : _ondeParouNesteArquivo(parte);
    }
    _trechoEnd = _trechoStart;
    final de = desde ?? (doComeco ? Duration.zero : _trechoStart);
    _desdeMs = de.inMilliseconds;
    _escuta.abrir(state.partes[parte].path, 0);
    state = state.copyWith(
      btParteFronteira: false,
      // A part going in the air is by definition a clip that has not ended. It never had
      // to be said while the only part put in the air after the mark was set was none:
      // landing on a part the room says nobody heard is the first, and it left the finish
      // lit over a part still playing — the same refusal, pressed again, for ever — and
      // the circle dead, because holding the clip and letting it go reads the mark and
      // refuses to start anything.
      btClipEnded: false,
      btClipRodando: true,
      btOuvidoMs: _pontoNoColar(0),
      btParteNoArMs: 0,
      btOuvidoAlemDoCursor: false,
    );
    _parteJaTocou = true;
    // The deadline is armed once this clip's own `openings` event lands, never here:
    // `_playback.position` still answers for whatever clip was in the air before this
    // one, and a deadline read from it counts against a cursor that is not its own.
    _play(
      state.partes[parte].path,
      from: de,
      onComplete: _fimDeParte,
      onFailed: () {
        // Back to the rehearsal is the answer while there is still passage left to tell
        // back. On a checked passage it is not: the telling-back is over, and dropping
        // the team into the rehearsal takes them out of a passage the room already
        // checked, where the gesture in front of them is recording the whole thing again
        // over their own work. The halt the caller raises is what reaches a person.
        //
        // The clip goes down on the way past, because the room stays on this screen: the
        // other way out left it by leaving. A part that never sounded, still marked as
        // running, greets the team with a pause glyph when the halt is lifted, and their
        // first press is spent stopping it — against a dead player's position.
        if (state.btPhase == BtPhase.conferida) {
          state = state.copyWith(btClipRodando: false);
          return;
        }
        // Never running, so nothing of it was heard: the span the room opened for this
        // part is dropped rather than closed, or a part the player refused to open
        // would travel to the room reported as listened to from its own beginning.
        state = state.copyWith(btClipRodando: false);
        _silenceTheRoom();
        state = state.copyWith(
          stage: SalaStage.ensaio,
          ensaio: EnsaioStatus.idle,
          btPhase: BtPhase.playing,
        );
      },
    );
  }

  void _fimDeParte() {
    // The part's own length, not where the player says it stopped. A position read at the
    // moment a clip finishes can come back as nought, and every offset after it — every
    // stretch the team tells back, and the length this part is measured against — was
    // measured from there. A three-part rehearsal reported itself as one part long.
    final medido =
        _playback.playingLength?.inMilliseconds ??
        _playback.position.inMilliseconds;
    final arquivo = _parteNoAr?.path;
    // And never a nought, on either of them. A part is never nought milliseconds long, so
    // a nought here is the player with nothing to say about the clip that just ended. The
    // ledger's copy is the `clip_duration_ms` the report carries, which is what the room
    // reads to decide this very refusal: a part the team heard whole, reported as nought
    // milliseconds long, is the same verdict refused again.
    if (arquivo != null && medido > 0) _escuta.medida(arquivo, medido);
    if (arquivo != null) _marcarOFimDaParte(arquivo, medido);
    _pararOClipe(ate: medido);
    // Whether the rehearsal has played through, which is what the finish waits on, and
    // whether every part has an end on the ruler, which is the ruler's business: one question
    // each. They were one line while the ruler could only fill in order, so the last part
    // ending and the ruler being complete were the same instant. A landing jumps over a
    // part, and a part nothing could measure then held the boundary open past the end of
    // the row: the room offered a crossing into a part that is not there.
    final ultima = _parteTocando >= state.partes.length - 1;
    final pousada = _pousadaNaParteApontadaPelaRecusa;
    _pousadaNaParteApontadaPelaRecusa = false;
    state = state.copyWith(
      btClipEnded: ultima || pousada,
      btParteFronteira: !ultima,
      btFimDasPartesMs: _fimDaParteMs,
      btParteNoArMs: 0,
    );
  }

  /// Listen to the rehearsal, hold it, or cross into the next part; once a stretch is
  /// cut, or named by the verdict, hear that stretch again, and once its translation is
  /// pending, hear the translation.
  ///
  /// One gesture with one meaning. It used to share the circle with cutting a stretch and
  /// opening the microphone, which is why the room could only guess how much had been
  /// heard.
  void ouvirGravacao() {
    if (state.stage != SalaStage.retro) return;
    final conferida = state.btPhase == BtPhase.conferida;
    if (state.btPhase != BtPhase.playing && !conferida) return;
    if (state.needsPerson || state.offline) return;
    if (state.btTrechoTocando) {
      _holdClip();
      state = state.copyWith(btTrechoTocando: false, btTrechoPausada: true);
      return;
    }
    if (state.btTrechoPausada) {
      state = state.copyWith(btTrechoTocando: true, btTrechoPausada: false);
      _letTheClipRun();
      return;
    }
    if (state.btRetroTocando) {
      _holdClip();
      state = state.copyWith(btRetroTocando: false, btRetroPausada: true);
      return;
    }
    if (state.btRetroPausada) {
      state = state.copyWith(btRetroTocando: true, btRetroPausada: false);
      _letTheClipRun();
      return;
    }
    if (state.btClipRodando) {
      _pararOClipe();
      return;
    }
    final pendente = state.btTraducaoPendente;
    if (!conferida && pendente != null) {
      _tirarAParteDoPlayer();
      state = state.copyWith(btRetroTocando: true);
      _play(
        pendente,
        onComplete: _calarOQueSeOuvia,
        onFailed: _calarOQueSeOuvia,
      );
      return;
    }
    final traduzidoDeNovo = _trechoTraduzidoDeNovo;
    if (!conferida && traduzidoDeNovo != null) {
      _silenceTheRoom();
      _leadThemToTheTrecho(traduzidoDeNovo);
      return;
    }
    if (!conferida && state.btCortado) {
      _ouvirOTrechoCortado();
      return;
    }
    if (state.btParteFronteira) {
      // From that part's own beginning on a checked passage. The cursor is where the next
      // cut starts, and a cut is about telling: on a passage told back whole every part's
      // cursor sits at its own end, so crossing at the cursor opened silence and the last
      // listening was the first part and then two dead presses.
      _tocarParteDaRetro(_parteTocando + 1, doComeco: conferida);
      return;
    }
    // The last listening the clean verdict invites, which is the whole rehearsal from its
    // own beginning. Read off what is in the air rather than off the clip having ended:
    // a session resumed already checked has put no part in the air at all, and telling
    // the player to carry on there lights the halo over silence. A part held mid-listen
    // still has its length written down, so holding and letting go carries on as it does
    // everywhere else.
    if (conferida && state.btParteNoArMs == 0) {
      // A passage picked back up without its recordings on the tablet has nothing to put
      // in the air, and asking for the first of an empty row takes the room down under
      // the team.
      if (state.partes.isEmpty) return;
      _tocarParteDaRetro(0, doComeco: true);
      return;
    }
    if (state.btClipEnded) return;
    final cabeca = _cabecaForaDoPlayer;
    if (cabeca != null) {
      _tocarParteDaRetro(_parteTocando, noCursor: true, desde: cabeca);
      return;
    }
    _seguirOClipe();
  }

  void ouvirOTrechoContado(int indice) {
    if (state.stage != SalaStage.retro || state.btPhase != BtPhase.playing) {
      return;
    }
    if (state.needsPerson || state.offline) return;
    if (indice < 0 || indice >= state.btTrechos.length) return;
    final trecho = state.btTrechos[indice];
    if (!trecho.contado) return;
    final traducao = trecho.retroPath;
    final materna = _ondeTocar(trecho);
    if (traducao == null && materna == null) return;
    _tirarAParteDoPlayer();
    state = state.copyWith(
      btContaEscolhida: indice,
      btRetroTocando: traducao != null,
      btTrechoTocando: traducao == null,
    );
    if (traducao != null) {
      _play(
        traducao,
        onComplete: _calarOQueSeOuvia,
        onFailed: _calarOQueSeOuvia,
      );
      return;
    }
    _clipHeld = false;
    _onPlaybackComplete = _calarOQueSeOuvia;
    _onPlaybackFailed = _calarOQueSeOuvia;
    _listenForTheEnd();
    unawaited(_playback.playRange(materna!.$1, materna.$2, materna.$3));
    _watchPlayback(clipStillOpening: true);
  }

  void ouvirOTrechoPendente() {
    if (state.btContaEscolhida != null) {
      _silenceTheRoom();
      return;
    }
    ouvirGravacao();
  }

  void _tirarAParteDoPlayer() {
    _silenceTheRoom();
    _cabecaForaDoPlayer ??= Duration(
      milliseconds: state.btOuvidoMs - _inicioDaParteMs(_parteTocando),
    );
  }

  void _calarOQueSeOuvia() {
    unawaited(_playback.stop());
    state = state.copyWith(
      btTrechoTocando: false,
      btTrechoPausada: false,
      btRetroTocando: false,
      btRetroPausada: false,
      clearContaEscolhida: true,
    );
  }

  void _ouvirOTrechoCortado() {
    final parte = _parteNoAr;
    if (parte == null) return;
    _silenceTheRoom();
    state = state.copyWith(btTrechoTocando: true);
    _onPlaybackComplete = _quietTheStretch;
    _onPlaybackFailed = _quietTheStretch;
    _clipHeld = false;
    _listenForTheEnd();
    unawaited(_playback.playRange(parte.path, _trechoStart, _trechoEnd));
    _watchPlayback(clipStillOpening: true);
  }

  void _quietTheStretch() {
    unawaited(_playback.stop());
    state = state.copyWith(btTrechoTocando: false, btTrechoPausada: false);
  }

  /// End a stretch here. The scissors only cuts: the translation is the circle's.
  void cortarTrecho() {
    if (!state.canCut) return;
    if (_trechoTraduzidoDeNovo != null) return;
    if (state.btTrechoTocando || state.btTrechoPausada) {
      final cabeca = _trechoStart + _playback.position;
      _silenceTheRoom();
      if (cabeca > _trechoStart && cabeca < _trechoEnd) _trechoEnd = cabeca;
      return;
    }
    // A belt. No way the room starts playback puts the playhead behind the cursor any
    // more — a part picked back up opens at its cursor, crossing into a part opens at
    // that part's, and holding the clip and letting it run again never rewinds — but
    // the position is the player's answer, not the room's, and a player that comes back
    // from behind it would send a stretch that ends before it begins and then walk the
    // cursor backwards over every stretch after it. Unconditional: a cut can never end
    // before it begins, whatever else stands.
    _silenceTheRoom(holdTheClip: true);
    if (_cabeca <= _trechoStart) return;
    _trechoEnd = _cabeca;
  }

  Duration get _cabeca {
    if (state.btParteFronteira || state.btClipEnded) {
      final medido = _tamanhoDaParteMs[_parteNoAr?.path];
      if (medido != null) return Duration(milliseconds: medido);
    }
    return _cabecaForaDoPlayer ?? _playback.position;
  }

  /// Arm a one-shot deadline for the moment the head will pass the cursor, read from the
  /// position of the clip that has just finished opening — never from whatever the
  /// previous clip's position happened to be, which is still what `_playback.position`
  /// answers for the instant between a new source being asked for and its `openings`
  /// event landing.
  ///
  /// `SalaSessionState.nothingHeardSinceCursor` is what the circle's label reads — a
  /// plain field, the way `canCut` and `canConfirmTranslation` are, because nothing else
  /// in state changes while a part simply plays on, and a label baked from a live read at
  /// the last state change would go stale the moment the room stopped touching state for
  /// it. The capture and the scissors do not read this field: a fact this timer can only
  /// answer to the nearest hundred milliseconds is not the belt a cut's own boundary
  /// needs, so both still read `_cabeca` live, as they always have.
  void _armCursorDeadline() {
    _timers.remove('cursor')?.cancel();
    if (_writeCursorCrossingNow()) return;
    final restante = _trechoStart - _cabeca;
    _after(
      'cursor',
      restante > _umInstanteOuvido ? restante : _umInstanteOuvido,
      () => state = state.copyWith(btOuvidoAlemDoCursor: true),
    );
  }

  /// The same read [_armCursorDeadline] opens with, but never schedules anything: called
  /// where the head has just stopped moving (a hold), so a gap still open when the head
  /// stands still stays open — a wall-clock timer armed against a frozen head would fire
  /// on schedule over a clip that never reached the cursor.
  void _checkCursorNow() {
    _timers.remove('cursor')?.cancel();
    _writeCursorCrossingNow();
  }

  /// Whether the head has passed the cursor right now, written down as the state fact
  /// either way.
  bool _writeCursorCrossingNow() {
    final passou = _cabeca > _trechoStart;
    state = state.copyWith(btOuvidoAlemDoCursor: passou);
    return passou;
  }

  Future<void> _tellThatStretchAgain(
    Trecho alvo,
    String path,
    String sessionId,
    int epoch,
  ) async {
    // Read before the room is asked, not after. The place is what the successor is found
    // by, and asking for it on the far side of the wait would be asking a list that the
    // wait itself is there to change.
    final lugar = state.btTrechos.indexWhere(
      (trecho) => trecho.segmentId == alvo.segmentId,
    );
    final TellingAgain told;
    try {
      told = await _room.replaceSegment(
        sessionId,
        alvo.segmentId!,
        File(path),
        takeId: alvo.takeId,
        from: alvo.from,
        to: alvo.to,
      );
      if (epoch != _epoch) return;
    } on StretchNoLongerCounts catch (refusal) {
      if (epoch != _epoch) return;
      await _readWhatTheRefusalSays(alvo, path, sessionId, epoch, refusal);
      return;
    } on Exception catch (error) {
      _fileiraDaUltimaRecusa = null;
      _contadasSemResposta.add(path);
      _guardarATraducao(path);
      if (epoch != _epoch) return;
      _theCorrectionFailed(error);
      return;
    }
    _fileiraDaUltimaRecusa = null;

    if (!told.captured) {
      // The room made nothing out of it, which is also what a transcriber outage looks
      // like from here. The stretch is left exactly as it was — an explanation is not
      // swapped for an empty one over somebody else's failure — and their audio is kept.
      _guardarATraducao(path);
      // A refusal leaves the stretches as they were, so the ground told back is the same
      // ground the taken correction would have left: read it off what the tablet already
      // holds rather than off an answer that carries nothing.
      _walkTheCursorBack(state.btTrechos);
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
        warning: told.needsPerson ? true : null,
      );
      if (told.needsPerson) _watchTheHalt();
      return;
    }

    _contadasSemResposta.clear();
    _theTellingLandedOn(
      told.segments,
      alvo: alvo,
      lugar: lugar,
      path: path,
      needsPerson: told.needsPerson,
    );
    if (epoch != _epoch) return;
    // The correction is finished, so the room goes and finds out what it was worth.
    //
    // Only a correction arrives here — an ordinary telling during the back-translation
    // returns before this, and it should, because there is still passage left to hear and
    // tell.
    //
    // Nothing had to be unlocked for this: the mark that the recording ended survives a
    // correction, so the ask is allowed the moment it is made.
    await finishBackTranslation();
  }

  void _theCorrectionFailed(Object error) {
    state = state.copyWith(
      btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
    );
    _handleRoomFailure(error);
  }

  Future<void> _readWhatTheRefusalSays(
    Trecho alvo,
    String path,
    String sessionId,
    int epoch,
    StretchNoLongerCounts refusal,
  ) async {
    final SessionSnapshot snapshot;
    try {
      snapshot = await _room.fetchState(sessionId);
    } on Exception catch (error) {
      _guardarATraducao(path);
      if (epoch != _epoch) return;
      _theCorrectionFailed(error);
      return;
    }
    if (epoch != _epoch) return;
    final segments = snapshot.backTranslation.segments;
    final fileira = [for (final segment in segments) segment.segmentId];
    final repetida =
        _fileiraDaUltimaRecusa != null &&
        listEquals(_fileiraDaUltimaRecusa, fileira);
    _fileiraDaUltimaRecusa = fileira;
    if (repetida) {
      _guardarATraducao(path);
      _theCorrectionFailed(refusal);
      return;
    }
    final sucessor = segments.indexWhere(
      (segment) =>
          segment.told &&
          segment.segmentId != alvo.segmentId &&
          segment.takeId == alvo.takeId &&
          segment.startsMs == alvo.from.inMilliseconds &&
          segment.endsMs == alvo.to.inMilliseconds,
    );
    final aContadaPousou =
        _contadasSemResposta.length == 1 && _contadasSemResposta.contains(path);
    _contadasSemResposta.clear();
    if (sucessor < 0) {
      _theStretchIsGone(segments);
      return;
    }
    if (aContadaPousou) {
      _theTellingLandedOn(segments, alvo: alvo, lugar: sucessor, path: path);
      return;
    }
    final trechos = _trechosFrom(segments, lugar: sucessor, noLugarDe: alvo);
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTrechos: trechos,
    );
    _armarOTrecho(trechos[sucessor]);
    _rememberWhereTheyAre(SalaStage.retro);
  }

  void _theStretchIsGone(List<SegmentView> segments) {
    final trechos = _trechosFrom(segments);
    _walkTheCursorBack(trechos);
    _trechoTraduzidoDeNovo = null;
    _descartarATraducaoPendente();
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTrechos: trechos,
    );
    _rememberWhereTheyAre(SalaStage.retro);
  }

  void _theTellingLandedOn(
    List<SegmentView> segments, {
    required Trecho alvo,
    required int lugar,
    required String path,
    bool needsPerson = false,
  }) {
    // The telling just recorded is this stretch's own. Only a first telling used to keep
    // its file, so from the first correction on the blue voice played back the very
    // explanation the analyst had refused.
    final trechos = _trechosFrom(
      segments,
      lugar: lugar,
      noLugarDe: alvo,
      contadoEm: path,
    );
    _walkTheCursorBack(trechos);
    _trechoTraduzidoDeNovo = null;
    unawaited(_retirarDaFilaSeGuardada(path));
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTrechos: trechos.isEmpty ? state.btTrechos : trechos,
      clearTraducaoPendente: true,
      // The room asking for a person over a stretch told again is a warning: somebody is
      // called to come and watch, and the team is refused nothing. Written with the row,
      // because a warning is a field and whatever follows the landing only walks the voice.
      warning: needsPerson ? true : null,
    );
    if (needsPerson) _watchTheHalt();
    _rememberWhereTheyAre(SalaStage.retro);
  }

  /// Put the cursor back on the furthest stretch already told.
  ///
  /// Telling a stretch again adds no new ground, so the cursor goes back rather than
  /// staying where the excursion left it. The ordinary path walks it forward past what
  /// was just told; here there is nothing to walk past, and a cursor left behind makes
  /// the next cut begin inside ground already explained.
  ///
  /// Whether the room made anything of the correction does not change that. A refused
  /// one used to skip this and leave the cursor on the bounds the finding had named, so
  /// the next cut began at the start of the recording and sent the whole rehearsal as one
  /// new stretch — the team's own telling, handed back to the room a second time.
  void _walkTheCursorBack(List<Trecho> trechos) {
    final alcancado = trechos.fold(
      Duration.zero,
      (ate, trecho) => trecho.to > ate ? trecho.to : ate,
    );
    _trechoStart = alcancado;
    _trechoEnd = alcancado;
  }

  void retroTap() {
    if (state.stage != SalaStage.retro) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.needsPerson) return;
    switch (state.btPhase) {
      case BtPhase.playing:
        _abrirACaptura();
      case BtPhase.capturing:
        // Held, not stopped: the stretch the team has just told ends inside the part
        // that is still open behind it, and the next listening carries that same part
        // on. Stopped, the room loses the length the end of the part is measured by.
        _silenceTheRoom(holdTheClip: true);
        unawaited(_finishChunkCapture());
      case BtPhase.findings:
        _silenceTheRoom();
        unawaited(_repeatTheFinding());
      case BtPhase.thinking:
      case BtPhase.conferida:
        break;
    }
  }

  void _abrirACaptura() {
    if (_trechoTraduzidoDeNovo == null && !state.btCortado) {
      if (_cabeca <= _trechoStart) return;
      _silenceTheRoom(holdTheClip: true);
      _trechoEnd = _cabeca;
    } else {
      _silenceTheRoom(holdTheClip: true);
    }
    _startChunkCapture();
  }

  void _startChunkCapture() {
    state = state.copyWith(
      btPhase: BtPhase.capturing,
      voice: VoiceState.listening,
    );
    unawaited(_recordOrBlock('retro_passada${state.btPass}_pedaco${_stamp()}'));
  }

  Future<void> _finishChunkCapture() async {
    final epoch = _epoch;
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    _watchBusyState();
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final sessionId = state.sessionId;

    if (path != null && !_hasAudio(path)) {
      _trechoStart = _ondeParouNesteArquivo(_parteTocando);
      state = state.copyWith(btPhase: BtPhase.playing);
      _haltForAPerson();
      unawaited(_recorder.delete(path));
      return;
    }

    if (path == null || sessionId == null) {
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
      );
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }

    final substituida = state.btTraducaoPendenteEmprestada
        ? null
        : state.btTraducaoPendente;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTraducaoPendente: path,
    );
    if (substituida != null) {
      unawaited(_retirarDaFilaSeGuardada(substituida));
      unawaited(_recorder.delete(substituida));
    }
  }

  Future<void> confirmarTraducao() async {
    if (!state.canConfirmTranslation) return;
    final path = state.btTraducaoPendente!;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final epoch = _epoch;
    _silenceTheRoom(holdTheClip: true);
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    _watchBusyState();

    final traduzidoDeNovo = _trechoTraduzidoDeNovo;
    if (traduzidoDeNovo != null) {
      await _tellThatStretchAgain(traduzidoDeNovo, path, sessionId, epoch);
      if (epoch != _epoch || state.btTraducaoPendente == null) return;
      if (state.btPhase == BtPhase.thinking) {
        state = state.copyWith(btPhase: BtPhase.playing);
      }
      return;
    }

    final gravacao = _parteNoAr?.takeId;
    if (gravacao == null) {
      // A stretch is a slice of a recording the room can name, and it cannot name one it
      // has never received — but the recording itself did reach this tablet, and the
      // rehearsal it belongs to is either still uploading or waiting for its own guard()
      // to adopt the name. That is not the room being broken, and a corte landing here
      // must not read as one: it kept the room open for a team that had done nothing
      // wrong, over a name that is (almost always) already on its way.
      _guardarATraducao(path);
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      return;
    }

    final BackTranslationChunk captured;
    try {
      captured = await _room.sendChunk(
        sessionId,
        File(path),
        takeId: gravacao,
        from: _trechoStart,
        to: _trechoEnd,
      );
      if (epoch != _epoch) return;
      if (!captured.captured) {
        // The room heard nothing in it — which is also what a transcription outage looks
        // like from here. Either way the stretch they just told is audio, and it used to
        // be dropped on both sides: the server returns before it stores anything, and
        // this branch kept no copy.
        _guardarATraducao(path);
        state = state.copyWith(
          btPhase: BtPhase.playing,
          voice: VoiceState.invite,
          btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
        );
        return;
      }
    } on Exception catch (error) {
      _guardarATraducao(path);
      if (epoch != _epoch) return;
      state = state.copyWith(
        btPhase: BtPhase.playing,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      _handleRoomFailure(error);
      return;
    }

    final trecho = Trecho(
      segmentId: null,
      takeId: gravacao,
      retroPath: path,
      parte: _parteTocando,
      from: _trechoStart,
      to: _trechoEnd,
      // Nobody has corrected it: the slice it plays is the slice of the part it occupies.
      lugarFrom: _trechoStart,
      lugarTo: _trechoEnd,
    );
    _trechoStart = _trechoEnd;
    unawaited(_retirarDaFilaSeGuardada(path));
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTrechos: [...state.btTrechos, trecho],
      clearTraducaoPendente: true,
    );
    _tocarOProximoTrecho();
  }

  void _guardarATraducao(String path) {
    if (!_traducoesGuardadas.add(path)) return;
    unawaited(
      _guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ),
    );
  }

  void _descartarATraducaoPendente() {
    final path = state.btTraducaoPendente;
    if (path == null) return;
    final emprestada = state.btTraducaoPendenteEmprestada;
    state = state.copyWith(clearTraducaoPendente: true);
    unawaited(_retirarDaFilaSeGuardada(path));
    if (!emprestada) unawaited(_recorder.delete(path));
  }

  void _tocarOProximoTrecho() {
    if (state.btParteFronteira) {
      _tocarParteDaRetro(_parteTocando + 1);
      return;
    }
    if (state.btClipEnded) return;
    _tocarParteDaRetro(_parteTocando, noCursor: true);
  }

  /// The part in the air, or null while no part is.
  ///
  /// Its name was adopted when the upload landed and is never fetched here: reading it now
  /// would put a disk read in the middle of telling a stretch back, and the answer would
  /// be no fresher than the one already beside the file.
  KeptTake? get _parteNoAr {
    final partes = state.partes;
    if (_parteTocando < 0 || _parteTocando >= partes.length) return null;
    return partes[_parteTocando];
  }

  /// Where the stretch just told sits in the row, counting the ones that failed.
  int _nextChunkPlace() =>
      state.btTrechos.length + state.btChunkFailures.length + 1;

  Future<void> finishBackTranslation() async {
    if (!state.canFinishBackTranslation) return;
    _silenceTheRoom();
    final sessionId = state.sessionId;
    if (sessionId == null) {
      _haltForAPerson();
      return;
    }

    final epoch = _epoch;
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    _watchBusyState();
    try {
      final verdict = await _room.finishBackTranslation(
        sessionId,
        playedByTake: _escuta.relato(state.partes),
      );
      if (epoch != _epoch) return;
      await _readyToSpeak(verdict.audioUrl, verdict.fixedLine);
      if (epoch != _epoch) return;
      state = state.copyWith(voice: VoiceState.speaking);
      _watchBusyState();
      final spoke = await _speak(
        verdict.audioUrl,
        verdict.fixedLine,
        remember: !verdict.usedFailSafe,
      );
      if (epoch != _epoch) return;
      // It returns, as all five of its siblings do. Registering and carrying on was the
      // other option and it is not one: on the third rung the halt fires, the room says
      // out loud that a person is needed and the desk is called — and then the lines
      // below overwrite that with the closing screen, so the team hears the call and is
      // shown a finished passage.
      //
      // Leaving `thinking` is not decoration. The five siblings never speak from inside
      // it, so the invitation they hand back is already a gesture; this one does, and
      // `thinking` takes no tap and holds the finish button down — the team would be left
      // watching "um instante" with nothing to touch. The third rung escapes only because
      // the halt leaves it on the way past. Same door, not a new one.
      if (!spoke) {
        _leaveThinking();
        return _registerUnplayableTurn();
      }
      _unplayableTurns = 0;

      final naoContadas = verdict.untoldTakeIds;
      if (naoContadas.isNotEmpty) {
        await _levarAParteApontadaPelaRecusa(
          naoContadas.first,
          epoch,
          semChaoTraduzido: true,
        );
        return;
      }

      final naoOuvidas = verdict.unheardTakeIds;
      if (naoOuvidas.isNotEmpty) {
        await _levarAParteApontadaPelaRecusa(
          naoOuvidas.first,
          epoch,
          semChaoTraduzido: false,
        );
        return;
      }

      if (verdict.checked) {
        // The finding is over, and so is the stretch it named. This branch returns above
        // the place the pointer is resolved, so a name outlived the objection that gave
        // it. It only showed after a correction the room made nothing of: one that lands
        // retires the name it replaces, so the pointer goes stale on its own and matches
        // nothing.
        state = state.copyWith(
          btPhase: BtPhase.conferida,
          voice: VoiceState.done,
          clearFindingSegment: true,
        );
        return;
      }
      // The room names the stretch the finding lands on, and the name is the room's to
      // give: nothing in the chunk it answered ever said it. The stretches are read back
      // before the pointer is resolved, so it is resolved against names that exist.
      try {
        await _readTheStretchesBack(sessionId, epoch);
      } on Exception {
        // The verdict is already in hand and already spoken. Failing to re-read the names
        // costs the pointer, not the verdict, so the findings screen still opens — on the
        // whole recording, which is where an unnamed stretch has always landed.
      }
      if (epoch != _epoch) return;

      final naoTraduzido = verdict.untoldSegmentId;
      if (naoTraduzido != null) {
        _levarAoTrechoNaoTraduzido(naoTraduzido);
        return;
      }
      state = state.copyWith(
        btPhase: BtPhase.findings,
        voice: VoiceState.invite,
        btFindingSegmentId: verdict.findingSegmentId,
        clearFindingSegment: verdict.findingSegmentId == null,
      );
      // The stretch is no longer played at the team. Which voice needs to speak again is
      // theirs to say, and they say it by comparing the two — so hearing either one is a
      // tap they choose to make, on the screen that asks the question.
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
  }

  /// The team makes what it recorded its final draft.
  ///
  /// The close of the necklace hangs off this and no longer off the verdict: a passage the
  /// room called checked stays on screen until somebody presses. The phase never leaves
  /// [BtPhase.conferida] while the request is out, which is what keeps the affordance
  /// alive under a transport failure — [_leaveThinking] has nothing to undo there.
  Future<void> aprovarRascunhoFinal() async {
    if (state.stage != SalaStage.retro) return;
    if (state.btPhase != BtPhase.conferida) return;
    if (state.needsPerson || state.offline) return;
    if (_aprovando) return;
    _silenceTheRoom();
    final sessionId = state.sessionId;
    if (sessionId == null) {
      _haltForAPerson();
      return;
    }
    _aprovando = true;
    final epoch = _epoch;
    try {
      // The release is the room's already once it has been given: a press that follows a
      // line nobody heard is asking for the line again, not for a second release.
      if (!_aprovada) {
        final resposta = await _room.approveRelease(sessionId);
        if (epoch != _epoch) return;
        if (!resposta.minted) {
          await _levarAoBuracoQueARecusaNomeia(resposta, sessionId, epoch);
          return;
        }
        _aprovada = true;
      }
      final disse = await _voice.playAsset(
        fixedLineAsset(approvedLine, _lingua),
      );
      if (epoch != _epoch) return;
      // As all five of its siblings do. Closing over a line the team never heard ends the
      // passage on a gesture nobody was answered for, and the press is the whole of what
      // the approval is.
      if (!disse) return _registerUnplayableTurn();
      _unplayableTurns = 0;
      _closeTheNecklace();
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    } finally {
      _aprovando = false;
    }
  }

  /// Take the team to the first hole the refusal names that this room has a door for.
  ///
  /// Which hole is first is [_PortaDaRecusa]'s own order and never the order the codes
  /// arrived in: a refusal naming the check and a part nobody told back names the check
  /// first, and opening that door hands the team back the very button that was refused. A
  /// hole with no door, a code this tablet does not know, a named hole whose ground never
  /// came, and an answer that is neither a version nor a refusal are the same thing from
  /// here — nothing the team can do from this screen — and they end where a refused
  /// approval has always ended.
  Future<void> _levarAoBuracoQueARecusaNomeia(
    ApprovalAnswer resposta,
    String sessionId,
    int epoch,
  ) async {
    _PortaDaRecusa? aberta;
    for (final blocker in resposta.blockers) {
      final porta = _portaDaRecusa(blocker);
      if (porta == null) continue;
      if (aberta == null || porta.index < aberta.index) aberta = porta;
    }

    switch (aberta) {
      case _PortaDaRecusa.trecho:
        final trecho = resposta.untoldSegmentId;
        if (trecho == null) return _haltForAPerson();
        // A passage the check cleared on its first verdict never had the names read back,
        // so the stretches it holds are the ones this tablet cut, and the name the refusal
        // gives matches none of them. Asked for after the ground, which a round trip
        // cannot supply: without it the room stood silent for a whole wait and called a
        // person anyway. A read that fails is not a hole with no ground, and it is left to
        // reach the approval's own ladder rather than resolving the name against nothing
        // and halting the room over a request the next press would repeat.
        await _readTheStretchesBack(sessionId, epoch);
        if (epoch != _epoch) return;
        _levarAoTrechoNaoTraduzido(trecho);
      case _PortaDaRecusa.parteNaoContada:
        final gravacoes = resposta.untoldTakeIds;
        if (gravacoes.isEmpty) return _haltForAPerson();
        await _levarAParteApontadaPelaRecusa(
          gravacoes.first,
          epoch,
          semChaoTraduzido: true,
        );
      case _PortaDaRecusa.parteNaoOuvida:
        final gravacoes = resposta.unheardTakeIds;
        if (gravacoes.isEmpty) return _haltForAPerson();
        await _levarAParteApontadaPelaRecusa(
          gravacoes.first,
          epoch,
          semChaoTraduzido: false,
        );
      case _PortaDaRecusa.conferir:
        // The room is already silent — the press silenced it — and the last listening of a
        // checked passage is what took the end of the clip away, which the advance disc
        // waits on beside told ground and nothing pending.
        state = state.copyWith(
          btPhase: BtPhase.playing,
          btClipEnded: true,
          voice: VoiceState.invite,
        );
      case null:
        _haltForAPerson();
    }
  }

  /// Straight to the part the verdict names, with the telling-back left standing.
  ///
  /// The room refuses to read a passage carrying ground it does not know about, and it
  /// names the part it is missing — whether nobody heard it ([semChaoTraduzido] false) or
  /// nobody told it back ([semChaoTraduzido] true). The press is not spent on the refusal:
  /// the part goes in the air, the team hears it, and the finish is offered again at its end.
  /// [semChaoTraduzido] carries straight through to [_tocarParteDaRetro], whose own doc
  /// says what it does to the cursor and why.
  Future<void> _levarAParteApontadaPelaRecusa(
    String gravacao,
    int epoch, {
    required bool semChaoTraduzido,
  }) async {
    if (!state.partes.any((take) => take.takeId == gravacao)) {
      // A recording this tablet is not holding. There is nothing to lead them to and no
      // way to say so without words. Asked before anything is measured: a name that leads
      // nowhere is a person, and measuring the whole rehearsal first only makes them wait
      // for it.
      _haltForAPerson();
      return;
    }
    // Landing forward over a part nobody has measured leaves the ruler short by the whole
    // of that part, so a file the player still answers nothing about is measured here.
    //
    // The row is read again after every wait, and a path that has left it is left alone:
    // a part recorded again in the middle of this would otherwise have a length written
    // under the file it just replaced.
    for (var antes = 0; antes < state.partes.length; antes++) {
      final arquivo = state.partes[antes].path;
      if (state.partes[antes].takeId == gravacao) break;
      if (_tamanhoDaParteMs.containsKey(arquivo)) continue;
      // Measuring waits on the player, and the watchdog that gives up on a wait only
      // watches a room that says it is thinking. Left speaking — which is where saying
      // the refusal leaves it — a measurement that never answered wedged the room with
      // nobody called, which is the one thing every other wait here is protected from.
      state = state.copyWith(voice: VoiceState.thinking);
      _watchBusyState();
      final medida = await _playback.howLong(arquivo);
      if (epoch != _epoch) return;
      if (medida == null) continue;
      if (!state.partes.any((take) => take.path == arquivo)) continue;
      _marcarOFimDaParte(arquivo, medida.inMilliseconds);
    }
    final parte = state.partes.indexWhere((take) => take.takeId == gravacao);
    if (parte < 0) {
      _haltForAPerson();
      return;
    }
    _pousadaNaParteApontadaPelaRecusa = true;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btFimDasPartesMs: _fimDaParteMs,
    );
    _tocarParteDaRetro(
      parte,
      doComeco: true,
      semChaoTraduzido: semChaoTraduzido,
    );
  }

  /// Straight to the stretch nobody told, with the rehearsal left standing.
  ///
  /// The answer that stops a reading over a missing explanation used to arrive with no
  /// address, and the only way forward the screen had left was the one that starts the
  /// rehearsal over: a team lost every recording of the passage over one stretch they had
  /// not got to yet. Nothing is thrown away here.
  ///
  /// Their own voice plays the stretch, because the room said only that parts are missing
  /// — which one is a thing they hear, not a thing anybody wrote. The room speaks no new
  /// line: the answer already carried the one it says.
  ///
  /// And the telling is armed as a replacement of that very stretch. Told back the
  /// ordinary way it would be captured at the next position, the named stretch would
  /// still be waiting, and the same gate would stop the passage again the next time they
  /// said they had finished.
  void _levarAoTrechoNaoTraduzido(String named) {
    // A sua própria porta. Chegar aqui já calado é uma coincidência do caminho que
    // chama, não uma regra, e a fatia que esta aterragem põe no ar sai por
    // _leadThemToTheTrecho, que não passa por onde uma parte passa.
    _silenceTheRoom();
    final trecho = _armarOTrecho(state.trechoChamado(named));
    if (trecho == null) return;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      clearFindingSegment: true,
    );
    _leadThemToTheTrecho(trecho);
  }

  Trecho? _armarOTrecho(Trecho? trecho) {
    if (trecho == null ||
        trecho.parte < 0 ||
        trecho.parte >= state.partes.length) {
      // A name this tablet cannot turn into a slice of a recording it is holding. There
      // is nothing to lead them to and no way to say so without words, and every quiet
      // way out of here ends on the exit that empties the rehearsal.
      _haltForAPerson();
      return null;
    }
    _parteTocando = trecho.parte;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _trechoTraduzidoDeNovo = trecho;
    return trecho;
  }

  /// Take the room's own reading of the stretches, names and all.
  ///
  /// A stretch is born on the server and only the server knows what it is called; the
  /// answer to telling one back carries a count and no name. Without this the pointer on
  /// a finding matched nothing this tablet held, and a team that had told six stretches
  /// back was offered the whole recording every time.
  ///
  /// It throws. Whether a read that did not happen is survivable is the caller's to say:
  /// the verdict swallows it, because it already holds its answer and only the pointer is
  /// lost; the approval's refusal does not, because the name is the whole of what it has.
  Future<void> _readTheStretchesBack(String sessionId, int epoch) async {
    final snapshot = await _room.fetchState(sessionId);
    if (epoch != _epoch) return;
    final trechos = _trechosFrom(snapshot.backTranslation.segments);
    if (trechos.isEmpty) return;
    state = state.copyWith(btTrechos: trechos);
  }

  /// The room's stretches as this tablet's own, each tied back to the recording it slices.
  ///
  /// [noLugarDe] is the stretch a replacement took the place of and [lugar] where it sat,
  /// on the routes that know. Identity is what ties the room's reading back to what this
  /// tablet holds, and a take the tablet does not hold breaks it: nothing about such a
  /// stretch matches. Its place has to survive that — it is the same stretch, and the bead
  /// row is where a team who cannot read sees where it went.
  ///
  /// [naParte] says which part of the rehearsal a recording this tablet does not hold
  /// answers for, for the stretches the room named over one. Read from the room's listing
  /// and handed in, because only the room knows it.
  ///
  /// [contadoEm] is the file a telling was just recorded into. It belongs to the stretch
  /// that replaced the one it was told over, and to no other.
  List<Trecho> _trechosFrom(
    List<SegmentView> told, {
    int lugar = -1,
    Trecho? noLugarDe,
    String? contadoEm,
    Map<String, int> naParte = const {},
  }) {
    final partes = state.partes;
    return [
      for (var onde = 0; onde < told.length; onde++)
        () {
          final segment = told[onde];
          final from = Duration(milliseconds: segment.startsMs);
          final to = Duration(milliseconds: segment.endsMs);
          // The room says what a stretch is called, where it sits and whether anyone has
          // explained it; the tablet knows what it is holding. Taking the room's reading
          // wholesale threw away the copy of the telling this tablet recorded, and the
          // blue voice had nothing to play — in every session, not only in one picked
          // back up.
          //
          // The two travel together or not at all: a stretch the room says is not told
          // has no explanation to hold a file for. Its own recording was replaced, and
          // the telling that belonged to the audio nobody will hear again does not carry
          // over — the same rule the room keeps on its side.
          //
          // By name where the room said one, and by the slice where it did not. The
          // slice alone stopped answering the day a recording could be replaced under a
          // correction: every stretch of that part moves to another file at another time
          // at once, and a stretch nobody touched came back matching nothing and lost the
          // telling this tablet holds for it.
          final chamado = state.btTrechos.where(
            (trecho) =>
                trecho.segmentId != null &&
                trecho.segmentId == segment.segmentId,
          );
          final aFatia = state.btTrechos.where(
            (trecho) =>
                trecho.takeId == segment.takeId &&
                trecho.from == from &&
                trecho.to == to,
          );
          final aqui = chamado.isNotEmpty ? chamado : aFatia;
          // What this stretch was a moment ago: found by identity, and where identity was
          // the very thing the mend broke, by the place the replacement took.
          final antes = aqui.isNotEmpty
              ? aqui.first
              : (onde == lugar ? noLugarDe : null);
          // Where it sits, which is the slice of a part it covers, and has nothing to do
          // with the file it plays. A stretch out of a rehearsal part sits where it
          // plays, and so does one the room's listing placed on a part. One that neither
          // names keeps the place of the stretch it stands in for.
          final daqui = partes.indexWhere((p) => p.takeId == segment.takeId);
          final aParte = daqui >= 0
              ? daqui
              : (naParte[segment.takeId] ?? daqui);
          final parte = aParte >= 0 ? aParte : (antes?.parte ?? aParte);
          return Trecho(
            segmentId: segment.segmentId,
            takeId: segment.takeId,
            retroPath: !segment.told
                ? null
                : onde == lugar
                ? contadoEm
                : (aqui.isNotEmpty ? aqui.first.retroPath : null),
            parte: parte,
            from: from,
            to: to,
            lugarFrom: aParte >= 0 ? from : (antes?.lugarFrom ?? from),
            lugarTo: aParte >= 0 ? to : (antes?.lugarTo ?? to),
            contado: segment.told,
          );
        }(),
    ];
  }

  /// Which part of the rehearsal each stretch this tablet has no recording for belongs
  /// to, asked of the room once, on a session picked back up.
  ///
  /// A stretch addressed to a recording that is not here is what a session told back
  /// before the room stopped assembling passages looks like afterwards. Which part such a
  /// recording answers for is the one thing the stretches cannot say, so the room's own
  /// list of them is read for it, by the number this tablet gave that part when it sent
  /// it up. Nothing is fetched: the stretch sits on the part the team recorded and plays
  /// that part's own audio at the place it sits in.
  ///
  /// A recording the room does not number, and a listing that does not answer, leave the
  /// reading as it was. Neither is a reason to stop the team: the stretch is on the
  /// server and the telling-back goes on.
  ///
  /// The resume row is not written again. Nothing it holds moves here — the stretches it
  /// keeps are the room's, and the recordings, the stage and the pass are all as they
  /// were.
  Future<void> _porCadaTrechoNaSuaParte(
    String sessionId,
    List<SegmentView> segments,
    int epoch,
  ) async {
    final faltando = {
      for (final segment in segments)
        if (segment.takeId.isNotEmpty &&
            !state.keptTakes.any((take) => take.takeId == segment.takeId))
          segment.takeId,
    };
    if (faltando.isEmpty) return;
    // The row of stretches as it stands before the listing waits. The rehearsal goes on
    // playing under it, and a team that cuts a stretch inside that window has it in this
    // list and nowhere else yet.
    final eram = state.btTrechos;
    final List<TakeView> guardadas;
    try {
      guardadas = await _room.takesOf(sessionId);
    } on Exception catch (error) {
      debugPrint(
        'A sessão $sessionId tem trechos numa gravação que este tablet não '
        'tem, e as gravações dela não puderam ser lidas: $error',
      );
      return;
    }
    if (epoch != _epoch) return;
    final naParte = <String, int>{};
    for (final guardada in guardadas) {
      if (!faltando.contains(guardada.takeId)) continue;
      final numero = guardada.ordinal;
      if (numero == null) continue;
      final onde = state.partes.indexWhere(
        (parte) => parte.scopeId == KeptScope.parte(numero),
      );
      if (onde < 0) continue;
      naParte[guardada.takeId] = onde;
    }
    if (naParte.isEmpty) return;
    // Only over a row nothing else has touched. This reading is built out of the answer
    // the resume came in with, so writing it over a row that moved meanwhile would take
    // the stretch the team just told back off the screen.
    if (!identical(state.btTrechos, eram)) return;
    state = state.copyWith(btTrechos: _trechosFrom(segments, naParte: naParte));
  }

  void _leadThemToTheTrecho(Trecho trecho, {VoidCallback? depois}) {
    if (_ondeTocar(trecho) == null) return;
    state = state.copyWith(btTrechoTocando: true);
    _tocarOTrecho(trecho, depois: depois);
  }

  /// Which take answers for a stretch's audio: the one its own id names, never the one
  /// sitting at its place in the rehearsal. A correction moves the file without moving
  /// the place — [Trecho.parte] stays the stretch's address, and has nothing to do with
  /// which recording plays.
  String? _pathForTrecho(Trecho trecho) {
    for (final take in state.keptTakes) {
      if (take.takeId == trecho.takeId) return take.path;
    }
    return null;
  }

  /// The file and range that best play [trecho] right now, or null when this tablet has
  /// nothing that does.
  ///
  /// [trecho.takeId]'s own file first, wherever it sits in `keptTakes` — the ordinary
  /// case, true of every stretch sliced out of a part this tablet holds.
  ///
  /// Otherwise the part [trecho] sits in, at the place ([Trecho.lugarFrom]..
  /// [Trecho.lugarTo]) rather than the file's own slice — the part's audio has not moved
  /// for a stretch whose own recording is not here yet, so its place in the rehearsal is
  /// the best guess left. Null only for a stretch belonging to no part at all: that would
  /// be some other stretch's recording, not this one's, and playing it is worse than the
  /// silence a skip is.
  (String, Duration, Duration)? _ondeTocar(Trecho trecho) {
    final path = _pathForTrecho(trecho);
    if (path != null) return (path, trecho.from, trecho.to);
    if (trecho.parte >= 0 && trecho.parte < state.partes.length) {
      return (
        state.partes[trecho.parte].path,
        trecho.lugarFrom,
        trecho.lugarTo,
      );
    }
    return null;
  }

  /// Play one stretch: a slice of the one file it came out of, or the best local
  /// stand-in [_ondeTocar] finds for it when that file is not here yet.
  ///
  /// It used to resolve which part a global millisecond fell in and stitch across the
  /// boundary when a stretch spanned two recordings. A stretch cannot span two recordings
  /// any more — it is a slice of one — so the resolving and the stitching are gone with
  /// the ruler that needed them.
  void _tocarOTrecho(Trecho trecho, {VoidCallback? depois}) {
    final onde = _ondeTocar(trecho);
    if (onde == null) {
      state = state.copyWith(btTrechoTocando: false, btTrechoPausada: false);
      return;
    }

    void quiet() {
      // Without a state to show, the stretch played into a screen that looked exactly
      // like the one waiting for the team to speak.
      //
      // The stop is not only for a real end: the ceiling can call this same callback
      // while the clip is still sounding, and without it the state said "stopped" over
      // a player still in the air.
      unawaited(_playback.stop());
      state = state.copyWith(btTrechoTocando: false, btTrechoPausada: false);
    }

    _onPlaybackComplete = () {
      quiet();
      depois?.call();
    };
    _onPlaybackFailed = quiet;
    _clipHeld = false;
    _listenForTheEnd();
    unawaited(_playback.playRange(onde.$1, onde.$2, onde.$3));
    _watchPlayback(clipStillOpening: true);
  }

  void ouvirOTrechoEATraducao() {
    if (state.btPhase != BtPhase.findings) return;
    if (state.btTrechoTocando) {
      _holdClip();
      state = state.copyWith(btTrechoTocando: false, btTrechoPausada: true);
      return;
    }
    if (state.btRetroTocando) {
      _holdClip();
      state = state.copyWith(btRetroTocando: false, btRetroPausada: true);
      return;
    }
    if (state.btTrechoPausada) {
      state = state.copyWith(btTrechoTocando: true, btTrechoPausada: false);
      _letTheClipRun();
      return;
    }
    if (state.btRetroPausada) {
      state = state.copyWith(btRetroTocando: true, btRetroPausada: false);
      _letTheClipRun();
      return;
    }
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    _silenceTheRoom();
    _leadThemToTheTrecho(trecho, depois: () => _ouvirATraducaoDada(trecho));
  }

  void _ouvirATraducaoDada(Trecho trecho) {
    final path = trecho.retroPath;
    if (path == null || state.btPhase != BtPhase.findings) return;
    state = state.copyWith(btRetroTocando: true);
    _play(path, onComplete: _calarOQueSeOuvia, onFailed: _calarOQueSeOuvia);
  }

  /// The team's own voice stands and only the telling slipped: the explanation is redone
  /// over a recording that does not move.
  void traduzirDeNovoEmPortugues() {
    final trecho = state.btFindingTrecho;
    if (state.btPhase != BtPhase.findings || trecho == null) return;
    _silenceTheRoom();
    if (_armarOTrecho(trecho) == null) return;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTraducaoPendente: trecho.retroPath,
      btTraducaoEmprestada: trecho.retroPath,
    );
  }

  /// Back to the rehearsal with everything kept, to record what the story still lacks.
  ///
  /// A finding of something missing that the analyst could not place in any stretch is a
  /// passage whose stretches are right and whose end was never recorded. Nothing is asked
  /// of the room here, because the stretches are still the session's, and the takes stay,
  /// so the team records more and the next telling-back starts where the told ground
  /// ends.
  void continuarOEnsaio() {
    if (state.btPhase != BtPhase.findings) return;
    _voltarAoEnsaio();
  }

  /// Back to the rehearsal to record one part again, in the place that part already has.
  void gravarAParteDeNovo() {
    if (state.btPhase != BtPhase.findings) return;
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    // Read before the way back clears the pointer, which is the only place the part is
    // written down at all.
    final parte = trecho.parte;
    if (parte < 0 || parte >= state.partes.length) {
      // A stretch on a recording this tablet is not holding has no part to record again,
      // and there is no way to say so without words. Carried on, the keep would send a
      // recording up under a part number the rehearsal does not have, and the team would
      // have recorded for nothing without the room ever saying a thing.
      _silenceTheRoom();
      _haltForAPerson();
      return;
    }
    _voltarAoEnsaio();
    state = state.copyWith(parteARegravar: parte);
    _rememberWhereTheyAre(SalaStage.ensaio);
  }

  void _voltarAoEnsaio() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      btPhase: BtPhase.playing,
      clearFindingSegment: true,
      peerCue: false,
    );
    // A mend left armed by a chunk that never landed would make the first stretch of
    // the next telling-back upload as a correction of one that does not exist.
    _trechoTraduzidoDeNovo = null;
    _rememberWhereTheyAre(SalaStage.ensaio);
  }

  void _closeTheNecklace() {
    final feita = _emCurso;
    if (feita != null) {
      unawaited(_feitas.add(_book, feita).catchError((_) {}));
      unawaited(_mindingThePlace(() => _emAberto.forget(_book, feita)));
    }
    _after('fim', const Duration(milliseconds: 700), () {
      state = state.copyWith(stage: SalaStage.fim, voice: VoiceState.done);
      _after('close', const Duration(milliseconds: 1000), () {
        _after('recomecar', ref.read(fimLingerProvider), _startOver);
      });
    });
  }

  void _startOver() {
    _clearAll();
    _forgetThePassage();
    _panoramaSessionId = null;
    state = const SalaSessionState();
    unawaited(abrirEscolha());
  }

  /// Everything a passage leaves behind that the next one must not inherit.
  ///
  /// Mostly counters and latches with no home in the state object, so nothing about them
  /// is reset by rebuilding it; the cursor, the cut, the stretch being told again and the
  /// pending translation live in the state and are let go here too, the pending file with
  /// them. `leaveThePassage` reset none of them and `_startOver` reset most: a new passage
  /// could start with the previous one's strike count and halt for a person on its first
  /// failure, and the stretch being told again — armed when the team asks to tell one
  /// again and let go only by a telling that lands — made the very first stretch of the
  /// next back translation upload as a correction of a stretch that does not exist.
  void _forgetThePassage() {
    unawaited(_coverageWatch?.cancel());
    _coverageWatch = null;
    _coverageSessionId = null;
    _unplayableTurns = 0;
    _roomFailures = 0;
    _fileiraDaUltimaRecusa = null;
    _contadasSemResposta.clear();
    _resumeFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _strandedSpoken = false;
    _personAsked = false;
    _personAskStep = 0;
    _haltWatched = null;
    _trechoTraduzidoDeNovo = null;
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _parteJaTocou = false;
    _soavaQuandoParou = false;
    _cabecaForaDoPlayer = null;
    _descartarATraducaoPendente();
    _traducoesGuardadas.clear();
    _traducaoNaFila.clear();
    _tamanhoDaParteMs.clear();
    _pousadaNaParteApontadaPelaRecusa = false;
    _aprovando = false;
    _aprovada = false;
    _escuta.esquecerTudo();
    _desdeMs = 0;
    _pendingTakePath = null;
    _emCurso = null;
    _semNome.clear();
    _captureFails = 0;
    _calmTurns = 0;
    _ackSpoken = 0;
    _recordingStarting = false;
    _clipHeld = false;
    _conviteOpened = false;
    _doneSeenMidTurn = false;
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
      SalaSessionNotifier.new,
    );
