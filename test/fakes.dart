import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

const totalBeads = 12;

Coverage coverage({int engaged = 0, int surfaced = 0}) => Coverage(
      engaged: engaged,
      surfaced: surfaced,
      total: totalBeads,
      absenceIndex: totalBeads - 1,
    );

class FakeVoice implements FacilitatorVoiceService {
  final List<String> played = [];
  final List<String> assets = [];
  bool succeeds = true;
  Completer<bool>? _holding;

  void holdNextLine() => _holding = Completer<bool>();

  void finishHeldLine() {
    _holding?.complete(succeeds);
    _holding = null;
  }

  Future<bool> _answer() {
    final held = _holding;
    return held == null ? Future.value(succeeds) : held.future;
  }

  @override
  Future<bool> play(String url) {
    played.add(url);
    return _answer();
  }

  @override
  Future<File> clipFor(String url) async => File(url);

  @override
  Future<bool> playAsset(String assetPath) {
    assets.add(assetPath);
    return _answer();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class FakeRecorder implements RecordingRepository {
  final Directory home = Directory.systemTemp.createTempSync('sala-gravacoes');
  int captures = 0;
  bool returnsNothing = false;
  final List<String> deleted = [];

  @override
  Future<bool> start(String fileName) async {
    captures++;
    return true;
  }

  @override
  Future<String?> stop() async {
    if (returnsNothing) return null;
    final file = File('${home.path}/captura-$captures.m4a')
      ..writeAsStringSync('a equipe falou');
    return file.path;
  }

  @override
  Future<void> discard() async {}

  @override
  Future<void> delete(String path) async => deleted.add(path);

  @override
  Future<String> keepAs(String path, String fileName) async => path;

  @override
  Future<void> dispose() async {}
}

class FakePlayback implements PlaybackRepository {
  final StreamController<void> _completions = StreamController<void>.broadcast();
  final List<String> played = [];
  bool paused = false;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async {}

  void finishPlayback() => _completions.add(null);

  @override
  Future<void> dispose() async => _completions.close();
}

class FakeInbox implements HandInboxRepository {
  List<HandReply> replies;
  final List<String> heard = [];
  final List<String> questionsSent = [];
  bool refuses = false;

  FakeInbox({this.replies = const []});

  @override
  Future<List<HandReply>> fetchReplies() async => replies;

  @override
  Future<void> markHeard(String replyId) async => heard.add(replyId);

  @override
  Future<void> sendQuestion(String sessionId, File audio) async {
    if (refuses) throw const RoomUnavailable('sem rede');
    questionsSent.add(sessionId);
  }

  @override
  void dispose() {}
}

class FakeRoom implements RoomRepository {
  final List<String> calls = [];
  final List<String?> pericopesAsked = [];
  final List<bool> metBefore = [];
  final List<String> clipsFetched = [];
  bool reachable = true;
  Coverage nextCoverage = coverage();

  Coverage? settledCoverage;
  bool peerCue = false;
  bool done = false;
  int turnsSent = 0;
  int chunksSent = 0;
  final List<String> takesKept = [];
  String? refuseTake;
  bool chunkCaptured = true;
  bool verdictChecked = true;
  BtFindingKind? verdictFinding;
  String? serverStatus;
  String fixedLine = '';

  Exception? failWith;

  void _guard(String call) {
    calls.add(call);
    final failure = failWith;
    if (failure != null) throw failure;
    if (!reachable) throw const RoomUnavailable('sem rede');
  }

  @override
  Future<Uint8List> fetchClip(String url) async {
    _guard('fetchClip');
    clipsFetched.add(url);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<SessionSnapshot> createSession({
    String? pericope,
    String? afterSession,
  }) async {
    _guard('createSession');
    pericopesAsked.add(pericope);
    metBefore.add(afterSession != null);
    return SessionSnapshot(
      sessionId: 'sessao-1',
      pericope: pericope ?? 'rute-1',
      status: 'in_progress',
      coverage: nextCoverage,
      done: false,
    );
  }

  @override
  Future<SessionSnapshot> fetchState(String sessionId) async {
    _guard('fetchState');
    return SessionSnapshot(
      sessionId: sessionId,
      pericope: 'rute-1',
      status: serverStatus ?? (done ? 'done' : 'in_progress'),
      coverage: settledCoverage ?? nextCoverage,
      done: done,
    );
  }

  @override
  Future<TurnResult> openSession(String sessionId) async {
    _guard('openSession');
    return _turn(sessionId);
  }

  @override
  Future<void> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    _guard('sendTake');
    if (refuseTake == '$kind/$scope') throw const RoomRefused();
    takesKept.add('$kind/$scope');
  }

  @override
  Future<TurnResult> sendTurn(String sessionId, File audio) async {
    _guard('sendTurn');
    turnsSent++;
    return _turn(sessionId);
  }

  TurnResult _turn(String sessionId) => TurnResult(
        sessionId: sessionId,
        audioUrl: fixedLine.isEmpty ? '/api/internalization-room/voice/turno' : '',
        fixedLine: fixedLine,
        transcript: 'a equipe falou',
        peerCue: peerCue,
        usedFailSafe: false,
        coverage: nextCoverage,
        done: done,
      );

  @override
  Future<BackTranslationChunk> sendChunk(String sessionId, File audio) async {
    _guard('sendChunk');
    chunksSent++;
    return BackTranslationChunk(chunks: chunksSent, captured: chunkCaptured);
  }

  @override
  Future<BackTranslationVerdict> finishBackTranslation(String sessionId) async {
    _guard('finishBackTranslation');
    return BackTranslationVerdict(
      audioUrl: '/api/internalization-room/voice/veredito',
      fixedLine: '',
      checked: verdictChecked,
      findingKind: verdictFinding,
      findingsRemaining: verdictFinding == null ? 0 : 1,
      usedFailSafe: false,
    );
  }

  @override
  void dispose() {}
}

class FakeNetwork implements ConnectivityService {
  final StreamController<void> _returned = StreamController<void>.broadcast();
  bool reachable = true;
  int checks = 0;

  @override
  Future<bool> canReachRoom() async {
    checks++;
    return reachable;
  }

  @override
  Stream<void> get onNetworkReturned => _returned.stream;

  void networkComesBack() => _returned.add(null);

  @override
  void dispose() => _returned.close();
}

class SalaHarness {
  final Directory takesHome = Directory.systemTemp.createTempSync('sala-tomadas');
  final FakeVoice voice = FakeVoice();
  final FakeRecorder recorder = FakeRecorder();
  final FakePlayback playback = FakePlayback();
  final FakeInbox inbox;
  final FakeRoom room = FakeRoom();
  final FakeNetwork network = FakeNetwork();
  final Duration settleDelay;
  final List<Duration> retryBackoff;
  final Duration? beckonInterval;

  SalaHarness({
    List<HandReply> replies = const [],
    this.settleDelay = const Duration(milliseconds: 60),
    this.retryBackoff = const [Duration(milliseconds: 20)],
    this.beckonInterval,
  }) : inbox = FakeInbox(replies: replies);

  late final TakeUploadQueue takes = TakeUploadQueue(
    room: room,
    home: () async => takesHome,
  );

  List<Override> get overrides => [
        facilitatorVoiceProvider.overrideWithValue(voice),
        recordingRepositoryProvider.overrideWithValue(recorder),
        playbackRepositoryProvider.overrideWithValue(playback),
        handInboxRepositoryProvider.overrideWithValue(inbox),
        roomRepositoryProvider.overrideWithValue(room),
        takeUploadQueueProvider.overrideWithValue(takes),
        connectivityServiceProvider.overrideWithValue(network),
        beadSettleDelayProvider.overrideWithValue(settleDelay),
        roomRetryBackoffProvider.overrideWithValue(retryBackoff),
        beckonIntervalProvider.overrideWithValue(beckonInterval),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);
}
