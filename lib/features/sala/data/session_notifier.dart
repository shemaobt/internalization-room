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

final busyStateCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 120),
);

final clipGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);
const _settleAttempts = 3;

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
  StreamSubscription<void>? _networkWatch;
  VoidCallback? _onPlaybackComplete;

  FacilitatorVoiceService get _voice => ref.read(facilitatorVoiceProvider);
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);
  PlaybackRepository get _playback => ref.read(playbackRepositoryProvider);
  HandInboxRepository get _inbox => ref.read(handInboxRepositoryProvider);
  RoomRepository get _room => ref.read(roomRepositoryProvider);
  TakeUploadQueue get _takes => ref.read(takeUploadQueueProvider);
  ConnectivityService get _network => ref.read(connectivityServiceProvider);
  FinishedPassages get _feitas => ref.read(finishedPassagesProvider);

  String get _book => ref.read(bookProvider);

  @override
  SalaSessionState build() {
    ref.onDispose(() {
      _cancelTimers();
      unawaited(_playbackDone?.cancel());
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
    unawaited(_voice.stop());
    unawaited(_playback.stop());
    unawaited(_recorder.discard());
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _play(String path, {VoidCallback? onComplete}) {
    _onPlaybackComplete = onComplete;
    _playbackDone ??= _playback.completions.listen((_) => _releasePlayback());
    unawaited(_playback.play(path).then((_) => _watchPlayback()));
  }

  void _releasePlayback() {
    _timers.remove('playback')?.cancel();
    final callback = _onPlaybackComplete;
    _onPlaybackComplete = null;
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

  void _haltForAPerson() {
    _leaveThinking();
    if (!state.needsPerson) {
      unawaited(_voice.playAsset(fixedLineAsset(needsPersonLine)));
    }
    state = state.copyWith(voice: VoiceState.needsPerson, peerCue: false);
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
        state = state.copyWith(voice: VoiceState.needsPerson, peerCue: false);
      case SessionGone():
        state = state.copyWith(clearSession: true, voice: VoiceState.needsPerson);
      case RoomBroke():
        _registerRoomFailure();
      default:
        _goOffline();
    }
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

  void _goOffline() {
    if (state.offline) return;
    _cancelTimers();
    _leaveThinking();
    state = state.copyWith(voice: VoiceState.offline, peerCue: false);
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
      final reachable = await _network.canReachRoom();
      if (epoch != _epoch) return;
      if (reachable) {
        _comeBack();
      } else if (state.offline) {
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
        state = state.copyWith(voice: VoiceState.needsPerson, peerCue: false);
      } else if (snapshot.done && state.stage == SalaStage.conversa) {
        state = state.copyWith(voice: VoiceState.done, peerCue: false);
      }
    } on Exception {
      if (epoch != _epoch || attempt + 1 >= _settleAttempts) return;
      _after('settle', ref.read(settleRetryDelayProvider), () {
        unawaited(_pullState(sessionId, attempt: attempt + 1));
      });
    }
  }

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
    final reachable = await _network.canReachRoom();
    if (epoch != _epoch) return;
    if (!reachable) {
      _conviteOpened = false;
      _goOffline();
      return;
    }
    try {
      final snapshot = await _room.createSession(pericope: panoramaPericope);
      if (epoch != _epoch) return;
      _panoramaSessionId = snapshot.sessionId;
      final turn = await _room.openSession(snapshot.sessionId);
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
    final feitas = await _feitas.all();
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
      _haltForAPerson();
      return;
    }
    unawaited(_dizerAOferecida());
  }

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
      unawaited(abrirEscolha());
      return;
    }
    if (roda.isEmpty) return;
    state = state.copyWith(aOferecer: (state.aOferecer + 1) % roda.length);
    unawaited(_dizerAOferecida());
  }

  Future<void> _dizerAOferecida() async {
    final passagem = state.oferecida;
    if (passagem == null) return;
    final epoch = _epoch;
    await _readyToSpeak(passagem.audioUrl, '');
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.speaking);
    _watchBusyState();
    await _speak(passagem.audioUrl, '');
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  void entrarNaOferecida() {
    final passagem = state.oferecida;
    if (passagem == null || state.voice != VoiceState.invite) return;
    unawaited(goConversa(pericope: passagem.pericope));
  }

  void leaveThePassage() {
    _clearAll();
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
    final reachable = await _network.canReachRoom();
    if (epoch != _epoch) return;
    if (!reachable) {
      _goOffline();
      return;
    }
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
      await _voiceTurn(await _room.openSession(snapshot.sessionId));
    } on Exception catch (error) {
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

  Future<void> _playReply(HandReply reply) async {
    final epoch = _epoch;
    final played = await _voice.play(reply.audioUrl);
    if (epoch != _epoch) return;
    if (played) _markHeard(reply.id);
    state = state.copyWith(clearPlayingReply: true);
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
      _releasePlayback();
      unawaited(_playback.stop());
      return;
    }
    final take = state.wholeTake;
    if (take == null || state.ensaio != EnsaioStatus.idle) return;
    state = state.copyWith(ensaio: EnsaioStatus.ghostPlaying);
    _play(take.path, onComplete: () {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
    });
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

  Future<void> _finishTake() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    _pendingTakePath = path;
    state = state.copyWith(ensaio: EnsaioStatus.recorded);
  }

  void takePlay() {
    final path = _pendingTakePath;
    if (path == null) return;
    state = state.copyWith(playPing: true);
    _play(path, onComplete: () {
      state = state.copyWith(playPing: false);
    });
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

  Future<void> _guard(
    String path, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    final sessionId = state.sessionId;
    final audio = File(path);
    if (sessionId == null || !await audio.exists()) return;
    await _takes.enqueue(
      audio,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
    );
    await _countUnsent();
    await _takes.flush();
    await _countUnsent();
  }

  Future<void> refreshUnsent() => _countUnsent();

  Future<void> _recordOrBlock(String fileName) async {
    if (await _recorder.start(fileName)) return;
    ref.read(micPermissionProvider.notifier).refuse();
  }

  Future<void> _countUnsent() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final epoch = _epoch;
    final takes = await _takes.unsentOf('ensaio', sessionId: sessionId);
    final chunks = await _takes.unsentOf('retro', sessionId: sessionId);
    final stranded = (await _takes.giveUps()).isNotEmpty;
    if (epoch != _epoch) return;
    state = state.copyWith(unsentTakes: takes, unsentChunks: chunks);
    if (stranded && !_strandedSpoken) {
      _strandedSpoken = true;
      unawaited(_voice.playAsset(strandedTakeAsset));
    }
  }

  void startRetro() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.retro,
      voice: VoiceState.invite,
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
      peerCue: false,
    );
    _playClipFromStart();
  }

  void _playClipFromStart() {
    _recontando = false;
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    state = state.copyWith(
      btTrechos: const [],
      clearFindingChunk: true,
      btTrechoTocando: false,
    );
    final take = state.wholeTake;
    if (take == null) {
      state = state.copyWith(btClipEnded: true);
      return;
    }
    _play(take.path, onComplete: () {
      state = state.copyWith(btClipEnded: true);
    });
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
        if (!_recontando) _trechoEnd = _playback.position;
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
      btTrechoTocando: false,
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
        state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
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
        btChunkPasses: [...state.btChunkPasses, state.btPass],
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
    _onPlaybackComplete = () {
      state = state.copyWith(btTrechoTocando: false);
    };
    _playbackDone ??= _playback.completions.listen((_) => _releasePlayback());
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
      unsentTakes: 0,
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
    );
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
    if (feita != null) unawaited(_feitas.add(feita).catchError((_) {}));
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
