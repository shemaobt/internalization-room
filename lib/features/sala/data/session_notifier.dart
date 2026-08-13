import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/facilitator_script.dart';
import '../domain/hand_reply.dart';
import '../domain/kept_take.dart';
import '../domain/session_state.dart';
import '../domain/spoken_line.dart';
import '../domain/turn_result.dart';
import 'connectivity_service.dart';
import 'facilitator_voice_service.dart';
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
  int _retryStep = 0;
  bool _noticeSpoken = false;
  bool _conviteOpened = false;
  bool _returning = false;
  bool _strandedSpoken = false;
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
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _play(String path, {VoidCallback? onComplete}) {
    _onPlaybackComplete = onComplete;
    _playbackDone ??= _playback.completions.listen((_) {
      final callback = _onPlaybackComplete;
      _onPlaybackComplete = null;
      callback?.call();
    });
    unawaited(_playback.play(path));
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
    state = state.copyWith(voice: VoiceState.speaking);
    await _speak(line.url, line.fixedLine);
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  Future<void> _voiceTurn(TurnResult turn) async {
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.speaking);
    final played = await _speak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    if (!played) {
      _registerUnplayableTurn();
      return;
    }
    _unplayableTurns = 0;
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
    state = state.copyWith(
      voice: _unplayableTurns >= _unplayableTurnsBeforeNeedsPerson
          ? VoiceState.needsPerson
          : VoiceState.invite,
      peerCue: false,
    );
  }

  void _handleRoomFailure(Object error) {
    _leaveThinking();
    switch (error) {
      case RoomRefused():
        state = state.copyWith(voice: VoiceState.needsPerson, peerCue: false);
      case SessionGone():
        state = state.copyWith(clearSession: true, voice: VoiceState.needsPerson);
      default:
        _goOffline();
    }
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
    _unplayableTurns = 0;
    unawaited(_takes.flush().then((_) => _countUnsent()));
    state = state.copyWith(voice: VoiceState.invite);
    if (state.stage == SalaStage.convite &&
        state.conviteStep == ConviteStep.boasVindas) {
      _conviteOpened = false;
      beckon();
    } else if (state.sessionId == null && state.stage == SalaStage.conversa) {
      unawaited(goConversa());
    }
  }

  void resolveWithPerson() {
    if (!state.needsPerson && !state.offline) return;
    _timers.remove('retry')?.cancel();
    _unplayableTurns = 0;
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

  Future<void> _pullState(String sessionId) async {
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
      return;
    }
  }

  void beckon() {
    if (state.stage != SalaStage.convite) return;
    if (state.conviteStep != ConviteStep.boasVindas) return;
    if (_conviteOpened || state.offline) return;
    unawaited(_voice.playAsset(inviteToStartAsset));
    final again = ref.read(beckonIntervalProvider);
    if (again != null) _after('beckon', again, beckon);
  }

  Future<void> openConvite() async {
    if (state.stage != SalaStage.convite || _conviteOpened) return;
    _conviteOpened = true;
    _timers.remove('beckon')?.cancel();
    state = state.copyWith(voice: VoiceState.thinking);
    if (!await _network.canReachRoom()) {
      _conviteOpened = false;
      _goOffline();
      return;
    }
    try {
      final snapshot = await _room.createSession(pericope: panoramaPericope);
      _panoramaSessionId = snapshot.sessionId;
      final turn = await _room.openSession(snapshot.sessionId);
      state = state.copyWith(conviteStep: ConviteStep.panorama);
      await _voicePanorama(turn);
    } on Exception catch (error) {
      _conviteOpened = false;
      _handleRoomFailure(error);
    }
  }

  Future<void> _voicePanorama(TurnResult turn) async {
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.speaking);
    final played = await _speak(turn.audioUrl, turn.fixedLine);
    if (epoch != _epoch) return;
    if (!played) {
      _registerUnplayableTurn();
      return;
    }
    _unplayableTurns = 0;
    _retryStep = 0;
    _noticeSpoken = false;
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

  Future<void> goConversa() async {
    _clearAll();
    final epoch = _epoch;
    state = state.copyWith(
      stage: SalaStage.conversa,
      voice: VoiceState.thinking,
      peerCue: false,
    );
    final reachable = await _network.canReachRoom();
    if (epoch != _epoch) return;
    if (!reachable) {
      _goOffline();
      return;
    }
    try {
      final snapshot = await _room.createSession(
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
    state = state.copyWith(
      voice: VoiceState.listening,
      peerCue: false,
      clearLastSpoken: true,
    );
    unawaited(_recordOrBlock(fileName));
  }

  Future<void> _finishListening() async {
    final path = await _recorder.stop();
    state = state.copyWith(voice: VoiceState.thinking);
    final sessionId = state.sessionId;
    if (path == null || sessionId == null) {
      state = state.copyWith(voice: VoiceState.invite);
      return;
    }
    try {
      await _voiceTurn(await _room.sendTurn(sessionId, File(path)));
    } on Exception catch (error) {
      _handleRoomFailure(error);
    } finally {
      unawaited(_recorder.delete(path));
    }
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
    final played = await _voice.play(reply.audioUrl);
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
    unawaited(_deliverQuestion());
  }

  Future<void> _deliverQuestion() async {
    final path = await _recorder.stop();
    final sessionId = state.sessionId;
    if (path == null || sessionId == null) {
      state = state.copyWith(voice: VoiceState.invite);
      return;
    }
    try {
      await _inbox.sendQuestion(sessionId, File(path));
    } on Exception catch (error) {
      _handleRoomFailure(error);
      return;
    }
    unawaited(_recorder.delete(path));
    state = state.copyWith(
      handAck: true,
      knots: state.knots + 1,
      voice: VoiceState.invite,
    );
    _after('ack', const Duration(milliseconds: 3200), () {
      state = state.copyWith(handAck: false);
    });
  }

  void replayKeptTake(String scopeId) {
    if (state.stage != SalaStage.conversa) return;
    final take = state.keptTakes.firstWhere(
      (candidate) => candidate.scopeId == scopeId,
      orElse: () => const KeptTake(scopeId: '', path: ''),
    );
    if (take.path.isEmpty) return;
    state = state.copyWith(replayingScope: scopeId);
    _play(take.path, onComplete: () {
      state = state.copyWith(clearReplayingScope: true);
    });
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
        state = state.copyWith(ensaio: EnsaioStatus.recorded);
        unawaited(_stopTake());
      case EnsaioStatus.ghostPlaying:
      case EnsaioStatus.recorded:
        break;
    }
  }

  Future<void> _stopTake() async {
    _pendingTakePath = await _recorder.stop();
  }

  void takePlay() {
    final path = _pendingTakePath;
    if (path != null) _play(path);
    state = state.copyWith(playPing: true);
    _after('play', const Duration(milliseconds: 1800), () {
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
    switch (state.btPhase) {
      case BtPhase.playing:
        unawaited(_playback.pause());
        _startChunkCapture();
      case BtPhase.capturing:
        unawaited(_finishChunkCapture());
      case BtPhase.thinking:
      case BtPhase.findings:
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
        'retro_passada${state.btPass}_pedaco${state.btChunkPasses.length + 1}',
      ),
    );
  }

  Future<void> _finishChunkCapture() async {
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      voice: VoiceState.thinking,
    );
    final path = await _recorder.stop();
    final sessionId = state.sessionId;

    if (path == null || sessionId == null) {
      state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
      if (!state.btClipEnded) unawaited(_playback.resume());
      return;
    }

    try {
      final captured = await _room.sendChunk(sessionId, File(path));
      if (!captured.captured) {
        state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
        if (!state.btClipEnded) unawaited(_playback.resume());
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
      _handleRoomFailure(error);
      if (!state.btClipEnded) unawaited(_playback.resume());
      return;
    }

    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btChunkPasses: [...state.btChunkPasses, state.btPass],
    );
    if (!state.btClipEnded) unawaited(_playback.resume());
  }

  Future<void> finishBackTranslation() async {
    if (!state.canFinishBackTranslation) return;
    final sessionId = state.sessionId;
    if (sessionId == null) return;

    state = state.copyWith(btPhase: BtPhase.thinking, voice: VoiceState.thinking);
    try {
      final verdict = await _room.finishBackTranslation(sessionId);
      state = state.copyWith(voice: VoiceState.speaking);
      await _voice.play(verdict.audioUrl);

      if (verdict.checked) {
        state = state.copyWith(btPhase: BtPhase.conferida, voice: VoiceState.done);
        _closeTheNecklace();
        return;
      }
      state = state.copyWith(
        btPhase: BtPhase.findings,
        voice: VoiceState.invite,
        btFindings: verdict.findingKind == null ? const [] : [verdict.findingKind!],
      );
    } on Exception catch (error) {
      _handleRoomFailure(error);
    }
  }

  void retellChunk() {
    if (state.btPhase != BtPhase.findings) return;
    state = state.copyWith(
      btPass: 2,
      btPhase: BtPhase.playing,
      btClipEnded: false,
      btFindings: const [],
      btChunkPasses: const [],
    );
    _playClipFromStart();
  }

  void reRecordClip() {
    if (state.btPhase != BtPhase.findings) return;
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      takes: 0,
      btPhase: BtPhase.playing,
      btChunkPasses: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
    );
  }

  void _closeTheNecklace() {
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
    _retryStep = 0;
    _noticeSpoken = false;
    _conviteOpened = false;
    _strandedSpoken = false;
    _panoramaSessionId = null;
    _pendingTakePath = null;
    state = const SalaSessionState();
    beckon();
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
  SalaSessionNotifier.new,
);
