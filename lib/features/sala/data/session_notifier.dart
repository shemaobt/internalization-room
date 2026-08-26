import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../domain/bt_finding.dart';
import '../domain/facilitator_script.dart';
import '../domain/hand_reply.dart';
import '../domain/kept_take.dart';
import '../domain/passagem.dart';
import '../domain/coverage.dart';
import '../domain/room_reach.dart';
import '../domain/session_state.dart';
import '../domain/spoken_line.dart';
import '../domain/turn_result.dart';
import 'connectivity_service.dart';
import 'facilitator_voice_service.dart';
import 'finished_passages.dart';
import 'hand_inbox_repository.dart';
import 'mic_permission.dart';
import 'playback_repository.dart';
import 'recording_repository.dart';
import 'room_repository.dart';
import 'take_upload_queue.dart';
import 'work_in_progress.dart';

final beadSettleDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

const _unplayableTurnsBeforeNeedsPerson = 3;
const _roomFailuresBeforeNeedsPerson = 3;

/// How many times the room may answer nothing before the app stops waiting for it.
const _slowAnswersBeforeGivingUp = 3;

/// How many times the inbox may fail to answer before the room says so out loud.
const _inboxSilencesBeforeSayingSo = 3;

/// How many degraded turns in a row before the room stops pretending it is working.
const _degradedTurnsBeforeAPerson = 3;

final busyStateCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 120),
);

/// Slack added to a clip's own length before the room decides the playback is lost. A
/// provider, not a constant, because a ceiling nothing can shrink is a ceiling no test
/// can reach — which is how the paused-clip bug shipped.
final clipGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);
const _settleAttempts = 3;

/// How much sound counts as the team having said something. Below it the room answers
/// from the bundle instead of paying for a round trip to hear silence — the one place
/// the app judges a capture rather than forwarding it.
final shortestSpeechProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 900),
);

final settleRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

final playbackCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 6),
);

/// The book the room is serving. One string, in one place, so another book is a config
/// change rather than a code change — the catalogue route takes it as a parameter.
final bookProvider = Provider<String>((ref) => 'Ruth');

final beckonIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 25),
);

final fimLingerProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 14),
);

final roomRetryBackoffProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ],
);

class SalaSessionNotifier extends Notifier<SalaSessionState> {
  final Map<String, Timer> _timers = {};
  int _epoch = 0;
  int _unplayableTurns = 0;
  int _roomFailures = 0;
  int _slowAnswers = 0;
  int _retryStep = 0;
  bool _noticeSpoken = false;
  bool _conviteOpened = false;
  bool _returning = false;
  bool _strandedSpoken = false;
  bool _personAsked = false;
  int _ackSpoken = 0;
  int _inaudibleSpoken = 0;
  DateTime? _listeningSince;
  String? _emCurso;
  bool _recontando = false;
  bool _askingForANewClip = false;
  /// The clip is paused. `_onPlaybackComplete` deliberately survives a pause — the resume
  /// still has to be able to end the part — so it cannot be what tells a ceiling whether
  /// there is any sound left to measure.
  bool _clipHeld = false;
  int _inboxSilences = 0;
  int _degradedTurns = 0;
  Duration _trechoStart = Duration.zero;
  Duration _trechoEnd = Duration.zero;
  int _retroClipMs = 0;
  int _parteTocando = 0;
  List<int> _fimDaParteMs = [];
  /// What the team actually heard of their own rehearsal, in global milliseconds.
  ///
  /// This used to be invented at the very end — "nought to the length of the clip" — so
  /// the report that travels to Refine said a team had listened to the whole rehearsal
  /// however little of it had played, and the gate that exists to catch exactly that could
  /// never fail. It is a record now: one span per stretch of listening, closed whenever
  /// the rehearsal stops.
  List<List<int>> _ouvido = [];
  int _desdeMs = 0;
  int _ghostParte = 0;
  String? _panoramaSessionId;

  String? _bridgeMode;
  bool _awaitingCalibration = false;
  String? _pendingTakePath;
  StreamSubscription<void>? _playbackDone;
  StreamSubscription<void>? _playbackFailed;
  StreamSubscription<void>? _playbackOpened;
  StreamSubscription<void>? _networkWatch;
  StreamSubscription<bool>? _micWatch;
  VoidCallback? _onPlaybackComplete;
  VoidCallback? _onPlaybackFailed;

  FacilitatorVoiceService get _voice => ref.read(facilitatorVoiceProvider);
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);
  PlaybackRepository get _playback => ref.read(playbackRepositoryProvider);
  HandInboxRepository get _inbox => ref.read(handInboxRepositoryProvider);
  RoomRepository get _room => ref.read(roomRepositoryProvider);
  TakeUploadQueue get _takes => ref.read(takeUploadQueueProvider);
  ConnectivityService get _network => ref.read(connectivityServiceProvider);
  FinishedPassages get _feitas => ref.read(finishedPassagesProvider);
  WorkInProgress get _emAberto => ref.read(workInProgressProvider);

  String get _book => ref.read(bookProvider);

  /// The room is gone and its providers with it.
  ///
  /// Half this class is fire-and-forget: `_guard` queues a take and counts what is left
  /// long after the gesture that started it returned. Reading a provider once the
  /// container is disposed throws, and the throw lands in no one's `catch` — it showed up
  /// as two tests that failed only on a slower machine, which is the same thing happening
  /// where nobody was looking.
  bool _gone = false;

  @override
  SalaSessionState build() {
    ref.onDispose(() {
      _gone = true;
      _cancelTimers();
      unawaited(_playbackDone?.cancel());
      unawaited(_playbackFailed?.cancel());
      unawaited(_playbackOpened?.cancel());
      unawaited(_networkWatch?.cancel());
      unawaited(_micWatch?.cancel());
    });
    return const SalaSessionState();
  }

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
  }

  void _clearAll() {
    _cancelTimers();
    state = state.copyWith(clearLastSpoken: true);
    _onPlaybackComplete = null;
    _onPlaybackFailed = null;
    unawaited(_voice.stop());
    unawaited(_playback.stop());
    unawaited(_recorder.discard());
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _play(String path, {VoidCallback? onComplete, VoidCallback? onFailed}) {
    _clipHeld = false;
    _onPlaybackComplete = onComplete;
    _onPlaybackFailed = onFailed;
    _listenForTheEnd();
    unawaited(_playback.play(path));
    _watchPlayback(clipStillOpening: true);
  }

  void _listenForTheEnd() {
    _playbackDone ??= _playback.completions.listen((_) => _releasePlayback());
    _playbackFailed ??= _playback.failures.listen((_) => _cannotPlayTheirOwnAudio());
    _playbackOpened ??= _playback.openings.listen((_) => _watchPlayback());
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
  }

  void _letTheClipRun() {
    _clipHeld = false;
    unawaited(_playback.resume());
    _watchPlayback();
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
  /// The download has a 90 s ceiling, and every caller used to enter `speaking` before it
  /// — the room rippled as if it were talking while nothing came out. `thinking` is what
  /// this actually is, and it is also what makes the screen refuse a touch that would
  /// start a second line on top of this one.
  Future<void> _readyToSpeak(String url, String fixedLine) async {
    if (fixedLine.isEmpty) {
      state = state.copyWith(voice: VoiceState.thinking);
      _watchBusyState();
      await _voice.fetch(url);
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
  }) async {
    final epoch = _epoch;
    final played = fixedLine.isEmpty
        ? await _voice.play(url)
        : await _voice.playAsset(fixedLineAsset(fixedLine));
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
    final line = state.lastSpoken;
    if (line == null || !state.canHearAgain) return;
    final epoch = _epoch;
    await _readyToRepeat(line.url, line.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    await _speak(line.url, line.fixedLine, panoramaUrl: line.panoramaUrl);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
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
    final played = await _speak(line.panoramaUrl, '', panoramaUrl: line.panoramaUrl);
    if (epoch != _epoch) return;
    state = state.copyWith(contasEnfiadas: true);
    if (!played) {
      state = state.copyWith(voice: VoiceState.invite);
      return;
    }
    _watchBusyState();
    await _speak(line.url, '', panoramaUrl: line.panoramaUrl);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  Future<void> _voiceTurn(TurnResult turn, int epoch) async {
    if (epoch != _epoch) return;
    _captureBridgeMode(turn);
    state = state.copyWith(coverage: turn.coverage);
    _scheduleSettle();
    await _readyToSpeak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    if (turn.audioUrl.isEmpty && turn.fixedLine.isEmpty) {
      _registerUnplayableTurn();
      return;
    }
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    final played = turn.toldInTwoMovements
        ? await _speakTheOpening(turn, epoch)
        : await _speak(
            turn.audioUrl,
            turn.fixedLine,
            remember: !turn.usedFailSafe,
          );
    if (epoch != _epoch) return;
    if (!played) {
      _registerUnplayableTurn();
      return;
    }
    _unplayableTurns = 0;
    _roomFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    state = state.copyWith(
      voice: turn.done ? VoiceState.done : VoiceState.invite,
      peerCue: turn.peerCue,
    );
    if (turn.degraded) {
      _degradedTurns++;
      if (_degradedTurns >= _degradedTurnsBeforeAPerson) _haltForAPerson();
    } else {
      _degradedTurns = 0;
    }
    _scheduleSettle();
  }

  /// The opening said in the two movements the room wrote it in.
  ///
  /// The necklace waits for the second one: the beads belong to the scene, and hanging
  /// them over the passage's own shape said the work was already laid out. Whatever
  /// happens to the scene's clip, the beads are handed over — a necklace held back by a
  /// failure would never come.
  Future<bool> _speakTheOpening(TurnResult turn, int epoch) async {
    state = state.copyWith(contasEnfiadas: false);
    // Brought in while the first movement is being spoken, so the second follows it
    // without a gap — and awaited before it is asked for, so the download and the playing
    // are never two callers racing for the same file.
    final arriving = _voice.fetch(turn.sceneUrl);
    final opened = await _speak(turn.panoramaUrl, '', panoramaUrl: turn.panoramaUrl);
    if (epoch != _epoch) return opened;
    state = state.copyWith(contasEnfiadas: true);
    if (!opened) return false;
    await arriving;
    if (epoch != _epoch) return true;
    // The voice stays `speaking` across both: one opening in two breaths, not a turn that
    // ended and another that began. Dropping to `thinking` in between showed the team the
    // room had stopped talking while it was still mid-sentence.
    _watchBusyState();
    return _speak(turn.sceneUrl, '', panoramaUrl: turn.panoramaUrl);
  }

  void _registerUnplayableTurn() {
    _unplayableTurns++;
    if (_unplayableTurns >= _unplayableTurnsBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
  }

  /// The build has no address or no key, so nothing the team does can work.
  ///
  /// Reached before the room opens, because the alternative is discovering it one failed
  /// request at a time — and `Env`'s throw is an `Error`, which the network layer's
  /// catches all miss.
  void haltForABrokenBuild() => _haltForAPerson();

  void _haltForAPerson({bool sessionIsGone = false}) {
    _leaveThinking();
    if (!state.needsPerson) {
      unawaited(_voice.playAsset(fixedLineAsset(needsPersonLine)));
    }
    state = state.copyWith(
      voice: VoiceState.needsPerson,
      peerCue: false,
      clearSession: sessionIsGone,
    );
    _tellTheRoomAPersonIsNeeded();
  }

  void _tellTheRoomAPersonIsNeeded() {
    final sessionId = state.sessionId;
    if (sessionId == null || _personAsked) return;
    _personAsked = true;
    unawaited(_room.askForAPerson(sessionId).catchError((_) {}));
  }

  void _handleRoomFailure(Object error) {
    _leaveThinking();
    switch (error) {
      case RoomRefused():
        _haltForAPerson();
      case SessionGone():
        _haltForAPerson(sessionIsGone: true);
      case RoomBroke():
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
    _conviteOpened = false;
    if (_slowAnswers >= _slowAnswersBeforeGivingUp) {
      _goOffline(RoomReach.roomSilent);
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
    beckon();
  }

  void _registerRoomFailure() {
    _roomFailures++;
    _conviteOpened = false;
    if (_roomFailures >= _roomFailuresBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
    beckon();
  }

  void _watchBusyState() {
    final ceiling = ref.read(busyStateCeilingProvider);
    if (ceiling != null) _after('watchdog', ceiling, _giveUpOnBusyState);
  }

  void _giveUpOnBusyState() {
    if (state.voice != VoiceState.thinking &&
        state.voice != VoiceState.speaking) {
      return;
    }
    _cancelTimers();
    _conviteOpened = false;
    _leaveThinking();
    _haltForAPerson();
  }

  void _leaveThinking() {
    if (state.stage == SalaStage.retro && state.btPhase == BtPhase.thinking) {
      state = state.copyWith(btPhase: BtPhase.playing);
    }
  }

  void _goOffline(RoomReach why) {
    if (state.offline) return;
    _cancelTimers();
    _leaveThinking();
    state = state.copyWith(
      voice: VoiceState.offline,
      reach: why,
      peerCue: false,
    );
    if (!_noticeSpoken) {
      _noticeSpoken = true;
      unawaited(_voice.playAsset(offlineNoticeAsset));
    }
    _watchForNetwork();
    _scheduleRetry();
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
    _after('retry', backoff[step], () => unawaited(_attemptReturn()));
  }

  Future<void> _attemptReturn() async {
    if (!state.offline || _returning) return;
    _returning = true;
    final epoch = _epoch;
    try {
      final reach = await _network.reachRoom();
      if (epoch != _epoch) return;
      if (reach == RoomReach.fine) {
        _comeBack();
      } else if (state.offline) {
        state = state.copyWith(reach: reach);
        _scheduleRetry();
      }
    } finally {
      _returning = false;
    }
  }

  void retryNow() {
    if (!state.offline) return;
    _timers.remove('retry')?.cancel();
    unawaited(_attemptReturn());
  }

  void _comeBack() {
    if (!state.offline) return;
    _timers.remove('retry')?.cancel();
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
    final epoch = _epoch;
    unawaited(_takes.flush().then((_) {
      if (epoch == _epoch) unawaited(_countUnsent());
    }));
    state = state.copyWith(voice: VoiceState.invite);
    if (state.stage == SalaStage.fim) {
      _startOver();
    } else if (state.stage == SalaStage.escolha) {
      unawaited(abrirEscolha());
    } else if (state.stage == SalaStage.convite &&
        state.conviteStep == ConviteStep.boasVindas) {
      _conviteOpened = false;
      beckon();
    } else if (state.sessionId == null && state.stage == SalaStage.conversa) {
      unawaited(goConversa(pericope: _emCurso));
    }
  }

  void beginAgain() => _startOver();

  void resolveWithPerson() {
    if (!state.needsPerson && !state.offline) return;
    _timers.remove('retry')?.cancel();
    _personAsked = false;
    _unplayableTurns = 0;
    _roomFailures = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
    state = state.copyWith(voice: VoiceState.invite);
    if (state.sessionId == null && state.stage == SalaStage.conversa) {
      unawaited(goConversa(pericope: _emCurso));
    } else {
      beckon();
    }
  }

  void _scheduleSettle() {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    _after('settle', ref.read(beadSettleDelayProvider), () {
      unawaited(_pullState(sessionId));
      unawaited(_pullInbox());
    });
  }

  Future<void> _pullState(String sessionId, {int attempt = 0}) async {
    final epoch = _epoch;
    try {
      final snapshot = await _room.fetchState(sessionId);
      if (epoch != _epoch || state.sessionId != sessionId) return;
      final told = snapshot.coverage;
      final before = state.coverage.engaged;
      // A turn that carried no coverage leaves the necklace where it is. Reading a
      // missing field as zero emptied the cord mid-passage — the only record of progress
      // this team can perceive — and put it back thirty seconds later, or never.
      if (told != null) {
        state = state.copyWith(
          coverage: told,
          ping: told.engaged > before ? PingRange(before, told.engaged) : null,
        );
      }
      if (state.ping != null) {
        _after('ping', const Duration(milliseconds: 700), () {
          state = state.copyWith(clearPing: true);
        });
      }
      if (snapshot.needsPerson && state.stage == SalaStage.conversa) {
        _haltForAPerson();
      } else if (snapshot.done && state.stage == SalaStage.conversa) {
        state = state.copyWith(voice: VoiceState.done, peerCue: false);
      }
    } on SessionGone {
      // Retrying a session the server has forgotten just spends the budget. The invite
      // disc used to keep breathing over it while the team spoke a whole turn into a
      // session that no longer existed.
      if (epoch != _epoch) return;
      _haltForAPerson(sessionIsGone: true);
    } on RoomRefused {
      if (epoch != _epoch) return;
      _haltForAPerson();
    } on Exception {
      if (epoch != _epoch || attempt + 1 >= _settleAttempts) return;
      _after('settle', ref.read(settleRetryDelayProvider), () {
        unawaited(_pullState(sessionId, attempt: attempt + 1));
      });
    }
  }

  /// Open the room: invite the team the first time, and go straight to the passages
  /// after that. The panorama belongs to a book, not to a launch.
  Future<void> openTheRoom() async {
    if (state.stage != SalaStage.convite) return;
    if (state.conviteStep != ConviteStep.boasVindas) return;
    if (await _feitas.bookOpened(_book)) {
      await abrirEscolha();
      return;
    }
    beckon();
  }

  void beckon() {
    if (state.stage != SalaStage.convite) return;
    if (state.conviteStep != ConviteStep.boasVindas) return;
    if (_conviteOpened || state.offline || state.needsPerson) return;
    unawaited(_voice.playAsset(inviteToStartAsset));
    final again = ref.read(beckonIntervalProvider);
    if (again != null) _after('beckon', again, beckon);
  }

  Future<void> openConvite() async {
    if (state.stage != SalaStage.convite || _conviteOpened) return;
    _conviteOpened = true;
    _timers.remove('beckon')?.cancel();
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
      final panorama = _panoramaSessionId ??
          (await _room.createSession(pericope: panoramaPericope)).sessionId;
      if (epoch != _epoch) return;
      _panoramaSessionId = panorama;
      final turn = await _room.openSession(panorama);
      if (epoch != _epoch) return;
      await _voicePanorama(turn);
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _conviteOpened = false;
      _handleRoomFailure(error);
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
      beckon();
      return;
    }
    _unplayableTurns = 0;
    _roomFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _captureBridgeMode(turn);
    unawaited(_feitas.markBookOpened(_book).catchError((_) {}));
    state = state.copyWith(
      voice: VoiceState.invite,
      conviteStep: ConviteStep.entrada,
    );
  }

  void _captureBridgeMode(TurnResult turn) {
    if (turn.bridgeMode.isEmpty) {
      _awaitingCalibration = false;
      return;
    }
    if (turn.bridgeMode == 'calibration_pending') {
      _awaitingCalibration = true;
      return;
    }
    _bridgeMode = turn.bridgeMode;
    _awaitingCalibration = false;
  }

  void conviteTap() {
    if (state.stage != SalaStage.convite) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.conviteStep == ConviteStep.entrada && _awaitingCalibration) {
      switch (state.voice) {
        case VoiceState.invite:
          _startListening('calibracao_${_stamp()}');
        case VoiceState.listening:
          unawaited(_finishCalibrationListening());
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

  Future<void> _finishCalibrationListening() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final panorama = _panoramaSessionId;
    if (path == null) {
      state = state.copyWith(voice: VoiceState.invite);
      _haltForAPerson();
      return;
    }
    if (panorama == null) {
      _awaitingCalibration = false;
      state = state.copyWith(voice: VoiceState.invite);
      unawaited(_recorder.delete(path));
      return;
    }
    if (!_heardSomething) {
      await _askThemToRepeat(path);
      return;
    }
    _sayImThinking();
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    try {
      final turn = await _room.sendTurn(panorama, File(path));
      if (epoch != _epoch) return;
      await _voicePanorama(turn);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    } finally {
      unawaited(_recorder.delete(path));
    }
  }


  Future<void> abrirEscolha() async {
    _clearAll();
    final epoch = _epoch;
    state = state.copyWith(
      stage: SalaStage.escolha,
      voice: VoiceState.thinking,
      peerCue: false,
      clearRoda: true,
    );
    _watchBusyState();
    final List<Passagem> todas;
    try {
      todas = await _room.passagesOf(ref.read(bookProvider));
    } on Object catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
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
    final roda = [
      for (final passagem in todas)
        if (!feitas.contains(passagem.pericope)) passagem,
    ];
    state = state.copyWith(
      naRoda: roda,
      comecadas: comecadas,
      aOferecer: 0,
      voice: VoiceState.invite,
    );
    if (roda.isEmpty) {
      // Nothing left for the room to offer, which is exactly what needsPerson means —
      // and it is the only state here with a glyph, a spoken line and a way out. A green
      // disc that refused every gesture in silence looked like a room that had died.
      _haltForAPerson();
      return;
    }
    unawaited(_dizerAOferecida());
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
    if (at == state.aOferecer && state.voice == VoiceState.invite) return;
    // Not `_cancelTimers()`: it bumps the epoch and clears every timer in the room,
    // including the one that retries the network. A finger on the ruler would have killed
    // the way back from offline. Cutting the line short is enough, and `_dizerAOferecida`
    // checks for itself that the finger has not moved on.
    unawaited(_voice.stop());
    state = state.copyWith(aOferecer: at, voice: VoiceState.invite);
  }

  /// Say where the finger landed.
  void dizerAPassagem() {
    if (state.stage != SalaStage.escolha) return;
    if (state.needsPerson || state.offline) return;
    if (state.naRoda?.isEmpty ?? true) return;
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
    await _speak(passagem.audioUrl, '');
    if (moved()) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  void entrarNaOferecida() {
    final passagem = state.oferecida;
    if (passagem == null || state.voice != VoiceState.invite) return;
    unawaited(goConversa(pericope: passagem.pericope));
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

  /// Enter a passage, resuming the session this tablet left in it when there is one.
  ///
  /// `fresh` skips the resume, which is how the 404 path starts over: retrying without it
  /// looked the session up again and recursed forever.
  Future<void> goConversa({String? pericope, bool fresh = false}) async {
    _clearAll();
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
    final reach = await _network.reachRoom();
    if (epoch != _epoch) return;
    if (reach != RoomReach.fine) {
      _goOffline(reach);
      return;
    }
    // Re-armed, not armed once: the ceiling is meant to say "nothing has happened for two
    // minutes", and a single arming over reach + create + open made it say "the whole
    // chain took two minutes" — which a slow but perfectly successful panorama does.
    _watchBusyState();
    // Only the passages the wheel already said have work waiting are looked up on disk,
    // so entering a fresh one costs no read at all.
    final waiting = !fresh && pericope != null && state.comecadas.contains(pericope)
        ? await _emAberto.of(_book, pericope)
        : null;
    if (epoch != _epoch) return;
    try {
      final resumed = waiting != null;
      final created = waiting == null
          ? await _room.createSession(
              pericope: pericope,
              afterSession: _panoramaSessionId,
              bridgeMode: _bridgeMode,
            )
          : null;
      final sessionId = waiting?.sessionId ?? created!.sessionId;
      if (epoch != _epoch) return;
      state = state.copyWith(sessionId: sessionId, coverage: created?.coverage);
      if (pericope != null && !resumed) {
        unawaited(
          _emAberto
              .remember(
                _book,
                pericope,
                ResumePoint(sessionId: sessionId, stage: SalaStage.conversa),
              )
              .catchError((_) {}),
        );
      }
      unawaited(_pullInbox());
      _watchBusyState();
      if (resumed) {
        final pastTheConversa = await _backToWhereTheyStopped(waiting, epoch);
        if (epoch != _epoch) return;
        if (pastTheConversa) {
          final snapshot = await _room.fetchState(sessionId);
          if (epoch != _epoch) return;
          state = state.copyWith(coverage: snapshot.coverage);
          return;
        }
      }
      // Re-opening carries the coverage back with it, so the necklace fills itself.
      await _voiceTurn(await _room.openSession(sessionId), epoch);
    } on SessionGone {
      if (epoch != _epoch) return;
      if (pericope != null) {
        unawaited(_emAberto.forget(_book, pericope).catchError((_) {}));
      }
      if (fresh) {
        // Already the clean attempt: the server is refusing the passage itself, not the
        // session we remembered. Retrying again is the loop this guard exists to stop.
        _haltForAPerson(sessionIsGone: true);
        return;
      }
      // The tablet remembered a session the server has forgotten. Start clean, once.
      unawaited(goConversa(pericope: pericope, fresh: true));
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
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
      _emAberto
          .remember(
            _book,
            pericope,
            ResumePoint(
              sessionId: sessionId,
              stage: stage,
              takes: state.keptTakes,
            ),
          )
          .catchError((_) {}),
    );
  }

  /// Put the team back on the stage they left, when the audio for it is still here.
  Future<bool> _backToWhereTheyStopped(ResumePoint waiting, int epoch) async {
    if (waiting.stage == SalaStage.conversa || waiting.takes.isEmpty) {
      return false;
    }
    final here = [
      for (final take in waiting.takes)
        if (await File(take.path).exists()) take,
    ];
    if (epoch != _epoch) return false;
    if (_gone || here.length != waiting.takes.length) {
      // Not all of the rehearsal is on the tablet, so the retro cannot be told back over
      // it. The conversa is the step that still works.
      return false;
    }
    state = state.copyWith(
      stage: SalaStage.ensaio,
      ensaio: EnsaioStatus.idle,
      voice: VoiceState.invite,
      keptTakes: here,
      takes: here.length,
    );
    unawaited(_countUnsent());
    return true;
  }

  void conversaTap() {
    if (state.stage != SalaStage.conversa) return;
    if (state.offline) {
      retryNow();
      return;
    }
    if (state.playingReplyId != null) return;
    if (state.noteMode) {
      _sendQuestion();
      return;
    }
    switch (state.voice) {
      case VoiceState.invite:
        _startListening('conversa_${_stamp()}');
      case VoiceState.listening:
        unawaited(_finishListening());
      case VoiceState.thinking:
      case VoiceState.speaking:
      case VoiceState.done:
      case VoiceState.needsPerson:
      case VoiceState.offline:
      case VoiceState.blocked:
        break;
    }
  }

  void _startListening(String fileName) {
    _listeningSince = DateTime.now();
    // The line is kept, not dropped. `canHearAgain` already hides the button for every
    // voice but `invite`, so it is gone while the microphone is open either way — and
    // forgetting it here meant that when the room could only answer with a canned line,
    // the team had nothing at all to hear again.
    state = state.copyWith(
      voice: VoiceState.listening,
      peerCue: false,
    );
    unawaited(_recordOrBlock(fileName));
  }

  bool get _heardSomething {
    final since = _listeningSince;
    if (since == null) return true;
    return DateTime.now().difference(since) >= ref.read(shortestSpeechProvider);
  }

  Future<void> _finishListening() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final sessionId = state.sessionId;
    if (path == null) {
      // The recorder handed nothing back after a turn the team just spoke. Reading that
      // as an ordinary return to the invite is the same silence `_finishTake` used to
      // keep, one method over.
      state = state.copyWith(voice: VoiceState.invite);
      _haltForAPerson();
      return;
    }
    if (sessionId == null) {
      state = state.copyWith(voice: VoiceState.invite);
      _haltForAPerson(sessionIsGone: true);
      return;
    }
    if (!_heardSomething) {
      await _askThemToRepeat(path);
      return;
    }
    _sayImThinking();
    state = state.copyWith(voice: VoiceState.thinking);
    _watchBusyState();
    try {
      await _voiceTurn(await _room.sendTurn(sessionId, File(path)), epoch);
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    } finally {
      unawaited(_recorder.delete(path));
    }
  }

  void _sayImThinking() {
    final line = rotated(instantAckLines, _ackSpoken++);
    unawaited(_voice.playAsset(fixedLineAsset(line)));
  }

  Future<void> _askThemToRepeat(String path) async {
    final epoch = _epoch;
    unawaited(_recorder.delete(path));
    state = state.copyWith(voice: VoiceState.speaking, peerCue: false);
    _watchBusyState();
    final line = rotated(inaudibleLines, _inaudibleSpoken++);
    await _voice.playAsset(fixedLineAsset(line));
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  Future<void> _pullInbox() async {
    final fetched = await _inbox.fetchReplies();
    if (fetched == null) {
      _inboxSilences++;
      if (_inboxSilences >= _inboxSilencesBeforeSayingSo) _haltForAPerson();
      return;
    }
    _inboxSilences = 0;
    if (fetched.isEmpty || _gone) return;
    final known = {for (final reply in state.replies) reply.id: reply};
    state = state.copyWith(
      replies: [for (final reply in fetched) known[reply.id] ?? reply],
    );
  }

  void handTap() {
    // The hand lives on the conversa, but the outgoing screen stays hit-testable for the
    // 400 ms the switcher takes, so a finger already travelling lands here from the next
    // stage — and starts a question recording no screen shows and no gesture stops.
    if (state.stage != SalaStage.conversa) return;
    if (state.offline) {
      // `_haltForAPerson` writes over `voice: offline`, and every way back — the retry
      // timer, the network watch, the touch — is guarded on `state.offline`. One tap on
      // the lit hand during an outage turned a room that would have healed itself into
      // one that needs a person to walk in.
      retryNow();
      return;
    }
    if (state.needsPerson) return;
    if (state.playingReplyId != null) return;
    if (state.voice == VoiceState.listening && !state.noteMode) return;
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
    state = state.copyWith(
      noteMode: true,
      voice: VoiceState.listening,
      peerCue: false,
    );
    unawaited(_recordOrBlock('pergunta_${_stamp()}'));
  }

  /// Play the facilitator's answer, and never let a broken one take the gesture away.
  ///
  /// Marking a reply heard only when it played sounds careful and is a trap: the hand
  /// offers the oldest unheard reply on every touch, so an answer that cannot be played
  /// is offered again, and again, and the team loses the one gesture they have for
  /// reaching a person. The answer is already lost — refusing to let go of it costs them
  /// the ability to ask anything else.
  Future<void> _playReply(HandReply reply) async {
    final epoch = _epoch;
    final played = await _voice.play(reply.audioUrl);
    if (epoch != _epoch) return;
    _markHeard(reply.id);
    if (played) {
      state = state.copyWith(clearPlayingReply: true);
      return;
    }
    // No strike count here, unlike every other line. `_markHeard` above is unconditional and
    // tells the server too, so this answer is gone whatever happened to it — a ducked reply
    // and a broken one cost the team the same thing, and only a person can now relay it.
    // Giving this path the three strikes a turn gets would destroy three answers before
    // anyone was called; a turn survives its strikes because the room can say it again.
    _haltForAPerson();
  }

  void _markHeard(String replyId) {
    unawaited(_inbox.markHeard(replyId));
    state = state.copyWith(
      replies: [
        for (final reply in state.replies)
          reply.id == replyId ? reply.asHeard() : reply,
      ],
      clearPlayingReply: true,
    );
  }

  void _cancelQuestion() {
    unawaited(_recorder.discard());
    state = state.copyWith(noteMode: false, voice: VoiceState.invite);
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
    final sessionId = state.sessionId;
    if (path == null || sessionId == null) {
      // The team raised their hand, spoke a question, and nothing came back from the
      // recorder. Returning to the invite in silence is the room forgetting they asked.
      state = state.copyWith(voice: VoiceState.invite, noteMode: false);
      _haltForAPerson(sessionIsGone: sessionId == null);
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
    final asked = state.knots;
    state = state.copyWith(
      handAck: true,
      knots: asked + 1,
      voice: VoiceState.speaking,
    );
    _watchBusyState();
    _after('ack', const Duration(milliseconds: 3200), () {
      state = state.copyWith(handAck: false);
    });
    await _voice.playAsset(fixedLineAsset(rotated(handoffLines, asked)));
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  void devRecomecarPassagem() {
    if (!Env.devPularFases) return;
    final pericope = _emCurso;
    if (pericope == null) return;
    unawaited(_emAberto.forget(_book, pericope).catchError((_) {}));
    unawaited(goConversa(pericope: pericope, fresh: true));
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

  void ghostPlay() {
    if (state.ensaio == EnsaioStatus.ghostPlaying) {
      // The button already showed a pause glyph; it just did not pause.
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      _releasePlayback();
      unawaited(_playback.stop());
      return;
    }
    if (state.partes.isEmpty || state.ensaio != EnsaioStatus.idle) return;
    state = state.copyWith(ensaio: EnsaioStatus.ghostPlaying);
    _ghostParte = 0;
    _tocarParteFantasma();
  }

  void _tocarParteFantasma() {
    void backToTheCircle() {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
    }

    void aProxima() {
      _ghostParte++;
      if (_ghostParte >= state.partes.length ||
          state.ensaio != EnsaioStatus.ghostPlaying) {
        backToTheCircle();
        return;
      }
      _tocarParteFantasma();
    }

    _play(
      state.partes[_ghostParte].path,
      onComplete: aProxima,
      onFailed: backToTheCircle,
    );
  }

  void ensaioTap() {
    switch (state.ensaio) {
      case EnsaioStatus.idle:
        state = state.copyWith(ensaio: EnsaioStatus.recording);
        unawaited(_recordOrBlock('ensaio_tomada_${_stamp()}'));
      case EnsaioStatus.recording:
        unawaited(_finishTake());
      case EnsaioStatus.ghostPlaying:
      case EnsaioStatus.recorded:
        break;
    }
  }

  /// The take is only offered once the recorder has handed the file back.
  ///
  /// Flipping to `recorded` first showed the keep/redo/listen buttons while `stop()` was
  /// still writing, and a quick keep found no path and dropped the take without a word.
  /// Staying in `recording` for those few frames is also the truer thing to show.
  Future<void> _finishTake() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    if (path == null) {
      // Nothing came back. Offering keep, redo and listen over a take that does not exist
      // let a team confirm a rehearsal into nothing — the buttons vanished exactly as on a
      // good keep, no bead appeared, and the way to the retro never opened.
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      _haltForAPerson();
      return;
    }
    _pendingTakePath = path;
    state = state.copyWith(ensaio: EnsaioStatus.recorded);
  }

  void takePlay() {
    final path = _pendingTakePath;
    if (path == null) return;
    state = state.copyWith(playPing: true);
    void stopThePulse() {
      state = state.copyWith(playPing: false);
    }

    _play(path, onComplete: stopThePulse, onFailed: stopThePulse);
  }

  void takeRedo() {
    final path = _pendingTakePath;
    if (path != null) unawaited(_recorder.delete(path));
    _pendingTakePath = null;
    state = state.copyWith(ensaio: EnsaioStatus.idle);
  }

  void takeKeep() {
    final path = _pendingTakePath;
    _pendingTakePath = null;
    if (path == null) {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      return;
    }
    final parte = state.keptTakes.length + 1;
    final escopo = KeptScope.parte(parte);
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [...state.keptTakes, KeptTake(scopeId: escopo, path: path)],
      takes: state.keptTakes.length + 1,
    );
    unawaited(_guard(path, kind: 'ensaio', scope: escopo, chunkIndex: parte));
    _rememberWhereTheyAre(SalaStage.ensaio);
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
    try {
      await queue.enqueue(
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
    await _countUnsent();
    await queue.flush();
    await _countUnsent();
  }

  Future<void> refreshUnsent() => _countUnsent();

  Future<void> _recordOrBlock(String fileName) async {
    final epoch = _epoch;
    _micWatch ??= _recorder.interrupted.listen(_theMicrophoneChangedHands);
    final capture = await _recorder.start(fileName);
    // The answer can arrive a minute late — `hasPermission` waits up to sixty seconds for
    // the platform — by which time the team may be on another stage entirely.
    if (epoch != _epoch || _gone) return;
    switch (capture) {
      case Capture.started:
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
      ensaio: EnsaioStatus.idle,
      noteMode: false,
      btPhase: capturing ? BtPhase.playing : state.btPhase,
      voice: VoiceState.invite,
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
    _haltForAPerson();
  }

  Future<void> _countUnsent() async {
    if (_gone) return;
    final epoch = _epoch;
    final queue = _takes;
    // Whether a recording is stuck is not a question about the session in progress, and
    // asking it only when one existed meant the check at the first frame — the moment a
    // facilitator is standing there and could act — did nothing at all.
    final stranded =
        (await queue.giveUps()).isNotEmpty || await queue.lostHistory();
    if (_gone) return;
    if (stranded && epoch == _epoch) _sayARecordingIsStranded();
    if (epoch != _epoch) return;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final takes = await queue.unsentOf('ensaio', sessionId: sessionId);
    final chunks = await queue.unsentOf('retro', sessionId: sessionId);
    final scopes = await queue.unsentScopesOf('ensaio', sessionId: sessionId);
    if (_gone || epoch != _epoch) return;
    state = state.copyWith(
      unsentTakes: takes,
      unsentChunks: chunks,
      unsentTakeScopes: scopes,
    );
  }

  void _sayARecordingIsStranded() {
    if (_strandedSpoken || _gone) return;
    _strandedSpoken = true;
    unawaited(_voice.playAsset(strandedTakeAsset));
  }

  void startRetro() {
    if (state.stage == SalaStage.ensaio) {
      if (state.ensaio == EnsaioStatus.recording) return;
      if (state.ensaio == EnsaioStatus.recorded) takeKeep();
    }
    _rememberWhereTheyAre(SalaStage.retro);
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.retro,
      voice: VoiceState.invite,
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btChunkFailures: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
      peerCue: false,
    );
    _playClipFromStart();
  }

  void _playClipFromStart() {
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _fimDaParteMs = [];
    _ouvido = [];
    _desdeMs = 0;
    _retroClipMs = 0;
    state = state.copyWith(
      btTrechos: const [],
      clearFindingChunk: true,
      btTrechoTocando: false,
      btParteFronteira: false,
      btClipRodando: false,
    );
    if (state.partes.isEmpty) {
      // No rehearsal to tell back is not a rehearsal that finished playing. Calling it
      // one opened `terminei` over an empty back translation.
      _haltForAPerson();
      return;
    }
    _tocarParteDaRetro(0);
  }

  int _inicioDaParteMs(int parte) => parte == 0 ? 0 : _fimDaParteMs[parte - 1];

  Duration get _posicaoGlobal =>
      Duration(milliseconds: _inicioDaParteMs(_parteTocando)) +
      _playback.position;

  void _seguirOClipe() {
    _desdeMs = _posicaoGlobal.inMilliseconds;
    state = state.copyWith(btClipRodando: true);
    _letTheClipRun();
  }

  /// Stop the rehearsal and write down how far it got.
  ///
  /// [ate] is the true end of a part, which the part's own duration knows better than the
  /// player's position at the moment it finished.
  void _pararOClipe({int? ate}) {
    _holdClip();
    if (state.btClipRodando) {
      final fim = ate ?? _posicaoGlobal.inMilliseconds;
      if (fim > _desdeMs) _ouvido = [..._ouvido, [_desdeMs, fim]];
    }
    state = state.copyWith(btClipRodando: false);
  }

  void _tocarParteDaRetro(int parte) {
    _parteTocando = parte;
    _desdeMs = _inicioDaParteMs(parte);
    state = state.copyWith(btParteFronteira: false, btClipRodando: true);
    _play(
      state.partes[parte].path,
      onComplete: _fimDeParte,
      onFailed: () {
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
    // stretch the team tells back, and the length of the whole rehearsal — was measured
    // from there. A three-part rehearsal reported itself as one part long.
    final medido = _playback.playingLength?.inMilliseconds ??
        _playback.position.inMilliseconds;
    final fim = _inicioDaParteMs(_parteTocando) + medido;
    if (_fimDaParteMs.length <= _parteTocando) _fimDaParteMs.add(fim);
    _pararOClipe(ate: fim);
    final ultima = _parteTocando >= state.partes.length - 1;
    if (ultima && _fimDaParteMs.length >= state.partes.length) {
      _retroClipMs = _fimDaParteMs.last;
      state = state.copyWith(btClipEnded: true, btParteFronteira: false);
      return;
    }
    state = state.copyWith(btParteFronteira: true);
  }

  /// Listen to the rehearsal, hold it, or cross into the next part.
  ///
  /// One gesture with one meaning. It used to share the circle with cutting a stretch and
  /// opening the microphone, which is why the room could only guess how much had been
  /// heard.
  void ouvirGravacao() {
    if (state.stage != SalaStage.retro) return;
    if (state.btPhase != BtPhase.playing) return;
    if (state.needsPerson || state.offline) return;
    if (state.btTrechoTocando) return;
    if (state.btClipRodando) {
      _pararOClipe();
      return;
    }
    if (state.btParteFronteira) {
      _tocarParteDaRetro(_parteTocando + 1);
      return;
    }
    if (state.btClipEnded) return;
    _seguirOClipe();
  }

  /// End a stretch here and hand the floor to the team.
  void cortarTrecho() {
    if (state.stage != SalaStage.retro) return;
    if (state.btPhase != BtPhase.playing) return;
    if (state.needsPerson || state.offline) return;
    if (state.btTrechoTocando) return;
    // While telling a stretch again, its bounds are the ones the finding named. Reading the
    // position instead wrote a place inside the excerpt into a number that means a place in
    // the whole rehearsal, and every stretch after it inherited the lie.
    if (!_recontando) _trechoEnd = _posicaoGlobal;
    _pararOClipe();
    _startChunkCapture();
  }

  void proximaParte() {
    if (state.stage != SalaStage.retro) return;
    if (state.btPhase != BtPhase.playing || !state.btParteFronteira) return;
    if (state.needsPerson || state.offline) return;
    _tocarParteDaRetro(_parteTocando + 1);
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
        break;
      case BtPhase.capturing:
        unawaited(_finishChunkCapture());
      case BtPhase.findings:
        _leadThemToTheTrecho();
      case BtPhase.thinking:
      case BtPhase.conferida:
        break;
    }
  }

  void _startChunkCapture() {
    state = state.copyWith(
      btPhase: BtPhase.capturing,
      voice: VoiceState.listening,
    );
    unawaited(
      _recordOrBlock(
        'retro_passada${state.btPass}_pedaco${_stamp()}',
      ),
    );
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

    if (path == null || sessionId == null) {
      state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
      return;
    }

    final BackTranslationChunk captured;
    try {
      captured = await _room.sendChunk(
        sessionId,
        File(path),
        from: _trechoStart,
        to: _trechoEnd,
        retelling: _recontando,
      );
      if (epoch != _epoch) return;
      if (!captured.captured) {
        // The room heard nothing in it — which is also what a transcription outage looks
        // like from here. Either way the stretch they just told is audio, and it used to
        // be dropped on both sides: the server returns before it stores anything, and
        // this branch kept no copy.
        unawaited(_guard(
          path,
          kind: 'retro',
          scope: KeptScope.whole,
          passNumber: state.btPass,
          chunkIndex: state.btChunkPasses.length + 1,
        ));
        state = state.copyWith(
          btPhase: BtPhase.playing,
          voice: VoiceState.invite,
          btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
        );
          return;
      }
    } on Exception catch (error) {
      unawaited(_guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
        chunkIndex: state.btChunkPasses.length + 1,
      ));
      if (epoch != _epoch) return;
      state = state.copyWith(
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      _handleRoomFailure(error);
      return;
    }

    _recontando = false;
    if (captured.needsPerson) {
      _haltForAPerson();
      return;
    }
    final trecho = Trecho(
      index: captured.chunks,
      from: _trechoStart,
      to: _trechoEnd,
    );
    _trechoStart = _trechoEnd;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btChunkPasses: [...state.btChunkPasses, captured.passNumber],
      btTrechos: [...state.btTrechos, trecho],
    );
  }

  /// Where the stretch just told sits in the row, counting the ones that failed.
  int _nextChunkPlace() =>
      state.btChunkPasses.length + state.btChunkFailures.length + 1;

  Future<void> finishBackTranslation() async {
    if (!state.canFinishBackTranslation) return;
    final sessionId = state.sessionId;
    if (sessionId == null) {
      _haltForAPerson();
      return;
    }

    final epoch = _epoch;
    state = state.copyWith(btPhase: BtPhase.thinking, voice: VoiceState.thinking);
    _watchBusyState();
    try {
      final verdict = await _room.finishBackTranslation(
        sessionId,
        clipDurationMs: _retroClipMs,
        playedRanges: _ouvido,
      );
      if (epoch != _epoch) return;
      await _readyToSpeak(verdict.audioUrl, verdict.fixedLine);
      if (epoch != _epoch) return;
      state = state.copyWith(voice: VoiceState.speaking);
      _watchBusyState();
      await _speak(verdict.audioUrl, verdict.fixedLine);
      if (epoch != _epoch) return;

      if (verdict.checked) {
        state = state.copyWith(btPhase: BtPhase.conferida, voice: VoiceState.done);
        _closeTheNecklace();
        return;
      }
      state = state.copyWith(
        btPhase: BtPhase.findings,
        voice: VoiceState.invite,
        btFindings: verdict.findingKind == null ? const [] : [verdict.findingKind!],
        btFindingChunk: verdict.findingChunk,
        clearFindingChunk: verdict.findingChunk == null,
      );
      _leadThemToTheTrecho();
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
  }

  void _leadThemToTheTrecho() {
    final trecho = state.btFindingTrecho;
    if (state.partes.isEmpty || trecho == null) return;
    state = state.copyWith(btTrechoTocando: true);
    _tocarFaixaGlobal(trecho.from, trecho.to);
  }

  int _parteQueContem(int posicaoMs) {
    for (var i = 0; i < _fimDaParteMs.length; i++) {
      if (posicaoMs < _fimDaParteMs[i]) return i;
    }
    return state.partes.length - 1;
  }

  void _tocarFaixaGlobal(Duration from, Duration to) {
    // Without a state to show, the stretch played into a screen that looked exactly like
    // the one waiting for the team to speak.
    void quiet() {
      state = state.copyWith(btTrechoTocando: false);
    }

    final parte = _parteQueContem(from.inMilliseconds);
    final inicio = _inicioDaParteMs(parte);
    final fimDaParte = parte < _fimDaParteMs.length
        ? _fimDaParteMs[parte]
        : to.inMilliseconds;
    final localFrom = Duration(milliseconds: from.inMilliseconds - inicio);
    final atravessa = to.inMilliseconds > fimDaParte;
    final localTo = Duration(
      milliseconds: (atravessa ? fimDaParte : to.inMilliseconds) - inicio,
    );

    _onPlaybackComplete = atravessa
        ? () => _tocarFaixaGlobal(Duration(milliseconds: fimDaParte), to)
        : quiet;
    _onPlaybackFailed = quiet;
    _clipHeld = false;
    _listenForTheEnd();
    unawaited(_playback.playRange(state.partes[parte].path, localFrom, localTo));
    _watchPlayback(clipStillOpening: true);
  }

  void retellChunk() {
    if (state.btPhase != BtPhase.findings) return;
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _recontando = true;
    state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
    _leadThemToTheTrecho();
  }

  Future<void> reRecordClip() async {
    if (state.btPhase != BtPhase.findings || _askingForANewClip) return;
    final sessionId = state.sessionId;
    if (sessionId != null && !await _theRoomForgotTheAbandonedClip(sessionId)) {
      return;
    }
    if (state.btPhase != BtPhase.findings) return;
    _clearAll();
    _parteTocando = 0;
    _fimDaParteMs = [];
    _ouvido = [];
    _retroClipMs = 0;
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      takes: 0,
      keptTakes: const [],
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btChunkFailures: const [],
      btClipEnded: false,
      btParteFronteira: false,
      btFindings: const [],
      btPass: 1,
    );
    _recontando = false;
    // Asserting `unsentTakes: 0` here was a claim about the disk made without reading it:
    // the queue still holds the old session's takes, and the two bookkeepers disagreed.
    unawaited(_countUnsent());
  }

  /// Whether the session itself dropped the abandoned clip, so the team's own copy can go.
  ///
  /// Clearing before the answer arrived was a claim about the server made without asking
  /// it: the chunks stayed in the session, the app believed the back translation had
  /// started over, and the next `finish` handed the analyst the old stretches concatenated
  /// with the new ones.
  ///
  /// The wait that asking opened is a busy state like every other one in this room: the
  /// findings exits are off the screen while it runs, and the circle says so without a
  /// written word. A refusal puts the team back on the findings they came from, because
  /// the stretches are still the session's — so the failure ladder is reached from there
  /// and not from the wait, whose own way out lands on `playing`.
  Future<bool> _theRoomForgotTheAbandonedClip(String sessionId) async {
    final epoch = _epoch;
    _askingForANewClip = true;
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    _watchBusyState();
    try {
      await _room.restartBackTranslation(sessionId);
    } on Exception catch (error) {
      if (epoch == _epoch) {
        if (state.btPhase == BtPhase.thinking) {
          state = state.copyWith(
            btPhase: BtPhase.findings,
            voice: VoiceState.invite,
          );
        }
        _handleRoomFailure(error);
      }
      return false;
    } finally {
      _askingForANewClip = false;
    }
    if (epoch != _epoch || state.btPhase != BtPhase.thinking) return false;
    state = state.copyWith(btPhase: BtPhase.findings);
    return true;
  }

  void _closeTheNecklace() {
    final feita = _emCurso;
    if (feita != null) {
      unawaited(_feitas.add(_book, feita).catchError((_) {}));
      unawaited(_emAberto.forget(_book, feita).catchError((_) {}));
    }
    _after('fim', const Duration(milliseconds: 700), () {
      state = state.copyWith(stage: SalaStage.fim, voice: VoiceState.done);
      _after('close', const Duration(milliseconds: 1000), () {
        state = state.copyWith(fimClosed: true);
        _after('recomecar', ref.read(fimLingerProvider), _startOver);
      });
    });
  }

  void _startOver() {
    _clearAll();
    _forgetThePassage();
    _conviteOpened = false;
    _panoramaSessionId = null;
    _awaitingCalibration = false;
    state = const SalaSessionState();
    unawaited(abrirEscolha());
  }

  /// Everything a passage leaves behind that the next one must not inherit.
  ///
  /// These are counters and latches with no home in the state object, so nothing about
  /// them is reset by rebuilding it. `leaveThePassage` reset none of them and `_startOver`
  /// reset most: a new passage could start with the previous one's strike count and halt
  /// for a person on its first failure, and `_recontando` — set when the team taps retell
  /// and cleared only by a chunk that lands — made the very first stretch of the next
  /// back translation upload as a correction of a stretch that does not exist.
  void _forgetThePassage() {
    _unplayableTurns = 0;
    _roomFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _strandedSpoken = false;
    _personAsked = false;
    _recontando = false;
    _inboxSilences = 0;
    _degradedTurns = 0;
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _fimDaParteMs = [];
    _ouvido = [];
    _desdeMs = 0;
    _retroClipMs = 0;
    _ghostParte = 0;
    _pendingTakePath = null;
    _emCurso = null;
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
  SalaSessionNotifier.new,
);
