import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/bt_finding.dart';
import '../domain/facilitator_script.dart';
import '../domain/hand_reply.dart';
import '../domain/kept_take.dart';
import '../domain/passagem.dart';
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

final beadSettleDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

const _unplayableTurnsBeforeNeedsPerson = 3;
const _roomFailuresBeforeNeedsPerson = 3;

/// How many times the room may answer nothing before the app stops waiting for it.
const _slowAnswersBeforeGivingUp = 3;

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
  Duration _trechoStart = Duration.zero;
  Duration _trechoEnd = Duration.zero;
  String? _panoramaSessionId;
  String? _pendingTakePath;
  StreamSubscription<void>? _playbackDone;
  StreamSubscription<void>? _playbackFailed;
  StreamSubscription<void>? _networkWatch;
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
      unawaited(_networkWatch?.cancel());
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
    // Both, not one. A failure callback left behind by an abandoned ghost play fires
    // across the stage reset and flips a live recording back to idle.
    _onPlaybackFailed = null;
    unawaited(_voice.stop());
    unawaited(_playback.stop());
    unawaited(_recorder.discard());
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _play(String path, {VoidCallback? onComplete, VoidCallback? onFailed}) {
    _onPlaybackComplete = onComplete;
    _onPlaybackFailed = onFailed;
    _listenForTheEnd();
    unawaited(_playback.play(path).then((_) => _watchPlayback()));
  }

  void _listenForTheEnd() {
    _playbackDone ??= _playback.completions.listen((_) => _releasePlayback());
    _playbackFailed ??= _playback.failures.listen((_) => _cannotPlayTheirOwnAudio());
  }

  /// The recording the room was going to play does not play.
  ///
  /// This used to arrive as a completion, so the room went on as though the team had
  /// heard it — and in the retro that is the one thing `terminei` waits for, so a corrupt
  /// rehearsal could carry a passage all the way to checked with nothing ever played.
  ///
  /// Refusing the completion is only half of it: whoever asked for the audio left the
  /// screen mid-gesture, and something has to unwind it. Running the completion callback
  /// instead would put the lie back, so each caller says what its own failure looks like.
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

  void _watchPlayback() {
    if (_onPlaybackComplete == null) return;
    final length = _playback.playingLength;
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
    _timers.remove('playback')?.cancel();
    unawaited(_playback.pause());
  }

  void _letTheClipRun() {
    unawaited(_playback.resume());
    _watchPlayback();
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

  Future<bool> _speak(String url, String fixedLine) async {
    final epoch = _epoch;
    final played = fixedLine.isEmpty
        ? await _voice.play(url)
        : await _voice.playAsset(fixedLineAsset(fixedLine));
    if (played && epoch == _epoch) {
      state = state.copyWith(
        lastSpoken: SpokenLine(url: url, fixedLine: fixedLine),
      );
    }
    return played;
  }

  Future<void> hearAgain() async {
    final line = state.lastSpoken;
    if (line == null || !state.canHearAgain) return;
    final epoch = _epoch;
    await _readyToSpeak(line.url, line.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    await _speak(line.url, line.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  Future<void> _voiceTurn(TurnResult turn) async {
    final epoch = _epoch;
    await _readyToSpeak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    final played = await _speak(turn.audioUrl, turn.fixedLine);
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
      coverage: turn.coverage,
    );
    _scheduleSettle();
  }

  void _registerUnplayableTurn() {
    _unplayableTurns++;
    if (_unplayableTurns >= _unplayableTurnsBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
  }

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
    // Self-guarded on a null session, which is what `sessionIsGone` has just produced.
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
        // Nothing to tell a session the room has already forgotten.
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
    unawaited(_takes.flush().then((_) => _countUnsent()));
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
      unawaited(goConversa());
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
    beckon();
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
      final before = state.coverage.engaged;
      state = state.copyWith(
        coverage: snapshot.coverage,
        ping: snapshot.coverage.engaged > before
            ? PingRange(before, snapshot.coverage.engaged)
            : null,
      );
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
    if (state.voice != VoiceState.invite) return;
    if (state.conviteStep == ConviteStep.boasVindas) unawaited(openConvite());
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
    final feitas = await _feitas.all(_book);
    if (epoch != _epoch) return;
    final roda = [
      for (final passagem in todas)
        if (!feitas.contains(passagem.pericope)) passagem,
    ];
    state = state.copyWith(
      naRoda: roda,
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
    _emCurso = null;
    state = const SalaSessionState();
    unawaited(abrirEscolha());
  }

  Future<void> goConversa({String? pericope}) async {
    _clearAll();
    _emCurso = pericope;
    final epoch = _epoch;
    state = state.copyWith(
      stage: SalaStage.conversa,
      voice: VoiceState.thinking,
      peerCue: false,
    );
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
    try {
      final snapshot = await _room.createSession(
        pericope: pericope,
        afterSession: _panoramaSessionId,
      );
      if (epoch != _epoch) return;
      state = state.copyWith(
        sessionId: snapshot.sessionId,
        coverage: snapshot.coverage,
      );
      unawaited(_pullInbox());
      _watchBusyState();
      await _voiceTurn(await _room.openSession(snapshot.sessionId));
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
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
    state = state.copyWith(
      voice: VoiceState.listening,
      peerCue: false,
      clearLastSpoken: true,
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
    if (path == null || sessionId == null) {
      state = state.copyWith(voice: VoiceState.invite);
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
      await _voiceTurn(await _room.sendTurn(sessionId, File(path)));
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
    try {
      final fetched = await _inbox.fetchReplies();
      if (fetched.isEmpty) return;
      final known = {for (final reply in state.replies) reply.id: reply};
      state = state.copyWith(
        replies: [for (final reply in fetched) known[reply.id] ?? reply],
      );
    } on Exception {
      return;
    }
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
      state = state.copyWith(voice: VoiceState.invite);
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

  void goEnsaio() {
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
      _releasePlayback();
      unawaited(_playback.stop());
      return;
    }
    final take = state.wholeTake;
    if (take == null || state.ensaio != EnsaioStatus.idle) return;
    state = state.copyWith(ensaio: EnsaioStatus.ghostPlaying);
    void backToTheCircle() {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
    }

    _play(take.path, onComplete: backToTheCircle, onFailed: backToTheCircle);
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
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      takes: state.takes + 1,
      keptTakes: [
        ...state.keptTakes.where((take) => take.scopeId != KeptScope.whole),
        KeptTake(scopeId: KeptScope.whole, path: path),
      ],
    );
    unawaited(_guard(path, kind: 'ensaio', scope: KeptScope.whole));
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
    // Held before the first await, because this is the durable half: once the container
    // is disposed the provider cannot be read, and I had guarded the enqueue itself on
    // that — turning a crash into a lost recording, in the one method whose whole job is
    // not losing recordings.
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
    switch (await _recorder.start(fileName)) {
      case Capture.started:
        return;
      case Capture.denied:
        ref.read(micPermissionProvider.notifier).refuse();
      case Capture.failed:
        _theRecorderNeverStarted();
    }
  }

  /// The screen already said the room was listening, and it was not.
  ///
  /// Every caller sets its own state before this runs, so a recorder that never started
  /// left the circle gathering over a microphone that was off. The team performs the
  /// whole passage into it and loses it.
  void _theRecorderNeverStarted() {
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      noteMode: false,
      btPhase: state.btPhase == BtPhase.capturing
          ? BtPhase.playing
          : state.btPhase,
    );
    _haltForAPerson();
  }

  Future<void> _countUnsent() async {
    if (_gone) return;
    final epoch = _epoch;
    // Whether a recording is stuck is not a question about the session in progress, and
    // asking it only when one existed meant the check at the first frame — the moment a
    // facilitator is standing there and could act — did nothing at all.
    final stranded =
        (await _takes.giveUps()).isNotEmpty || await _takes.lostHistory();
    if (_gone) return;
    if (stranded && epoch == _epoch) _sayARecordingIsStranded();
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final takes = await _takes.unsentOf('ensaio', sessionId: sessionId);
    final chunks = await _takes.unsentOf('retro', sessionId: sessionId);
    if (_gone || epoch != _epoch) return;
    state = state.copyWith(unsentTakes: takes, unsentChunks: chunks);
  }

  void _sayARecordingIsStranded() {
    if (_strandedSpoken || _gone) return;
    _strandedSpoken = true;
    unawaited(_voice.playAsset(strandedTakeAsset));
  }

  void startRetro() {
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
    state = state.copyWith(
      btTrechos: const [],
      clearFindingChunk: true,
      btTrechoTocando: false,
    );
    final take = state.wholeTake;
    if (take == null) {
      // No rehearsal to tell back is not a rehearsal that finished playing. Calling it
      // one opened `terminei` over an empty back translation.
      _haltForAPerson();
      return;
    }
    _play(
      take.path,
      onComplete: () {
        state = state.copyWith(btClipEnded: true);
      },
      onFailed: () {
        // The one caller I left without this, under a comment saying every caller had it.
        // A rehearsal that will not open cannot be told back at all, and the retro has no
        // gesture that recovers — so the room goes back to where a new one can be made.
        state = state.copyWith(
          stage: SalaStage.ensaio,
          ensaio: EnsaioStatus.idle,
          btPhase: BtPhase.playing,
        );
      },
    );
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
        _trechoEnd = _playback.position;
        _holdClip();
        _startChunkCapture();
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
      if (!state.btClipEnded) _letTheClipRun();
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
        if (!state.btClipEnded) _letTheClipRun();
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
      if (!state.btClipEnded) _letTheClipRun();
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
    if (!state.btClipEnded) _letTheClipRun();
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
      final verdict = await _room.finishBackTranslation(sessionId);
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
    final take = state.wholeTake;
    final trecho = _trechoOfTheFinding();
    if (take == null || trecho == null) return;
    // Without a state to show, the stretch played into a screen that looked exactly like
    // the one waiting for the team to speak.
    void quiet() {
      state = state.copyWith(btTrechoTocando: false);
    }

    _onPlaybackComplete = quiet;
    _onPlaybackFailed = quiet;
    _listenForTheEnd();
    state = state.copyWith(btTrechoTocando: true);
    unawaited(
      _playback
          .playRange(take.path, trecho.from, trecho.to)
          .then((_) => _watchPlayback()),
    );
  }

  Trecho? _trechoOfTheFinding() {
    final at = state.btFindingChunk;
    if (at == null) return null;
    for (final trecho in state.btTrechos) {
      if (trecho.index == at) return trecho.to > trecho.from ? trecho : null;
    }
    return null;
  }

  void retellChunk() {
    if (state.btPhase != BtPhase.findings) return;
    final trecho = _trechoOfTheFinding();
    if (trecho == null) return;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _recontando = true;
    state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
    _leadThemToTheTrecho();
  }

  void reRecordClip() {
    if (state.btPhase != BtPhase.findings) return;
    final sessionId = state.sessionId;
    if (sessionId != null) {
      unawaited(_forgetTheAbandonedClip(sessionId));
    }
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      takes: 0,
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btChunkFailures: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
    );
    // Asserting `unsentTakes: 0` here was a claim about the disk made without reading it:
    // the queue still holds the old session's takes, and the two bookkeepers disagreed.
    unawaited(_countUnsent());
  }

  Future<void> _forgetTheAbandonedClip(String sessionId) async {
    try {
      await _room.restartBackTranslation(sessionId);
    } on Exception {
      return;
    }
  }

  void _closeTheNecklace() {
    final feita = _emCurso;
    if (feita != null) unawaited(_feitas.add(_book, feita).catchError((_) {}));
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
    _unplayableTurns = 0;
    _roomFailures = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _conviteOpened = false;
    _strandedSpoken = false;
    _personAsked = false;
    _panoramaSessionId = null;
    _pendingTakePath = null;
    state = const SalaSessionState();
    _emCurso = null;
    unawaited(abrirEscolha());
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
  SalaSessionNotifier.new,
);
