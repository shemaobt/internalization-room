import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/finished_passages.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/screen_awake.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
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
  final List<String> fetched = [];
  bool succeeds = true;
  /// Lines this voice refuses to play, by url — for the halves of one turn.
  final Set<String> refuses = {};
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
    if (refuses.contains(url)) return Future.value(false);
    return _answer();
  }

  @override
  Future<File> clipFor(String url) async => File(url);

  /// Lines this tablet does not have yet, by url.
  final Set<String> missing = {};

  @override
  Future<bool> holds(String url) async => url.isNotEmpty && !missing.contains(url);

  Completer<void>? _fetching;

  void holdNextFetch() => _fetching = Completer<void>();

  void finishHeldFetch() {
    _fetching?.complete();
    _fetching = null;
  }

  @override
  Future<bool> fetch(String url) async {
    fetched.add(url);
    await _fetching?.future;
    return succeeds;
  }

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
  String? lastPath;

  bool permitted = true;

  bool? answersPermission = true;
  bool startThrows = false;

  @override
  Future<bool?> hasPermission() async => permitted ? answersPermission : false;

  @override
  Future<Capture> start(String fileName) async {
    captures++;
    if (!permitted) return Capture.denied;
    if (startThrows) return Capture.failed;
    return Capture.started;
  }

  Completer<void>? _holdingStop;

  void holdNextStop() => _holdingStop = Completer<void>();

  void finishStop() {
    _holdingStop?.complete();
    _holdingStop = null;
  }

  @override
  Future<String?> stop() async {
    final held = _holdingStop;
    if (held != null) await held.future;
    if (returnsNothing) return null;
    final file = File('${home.path}/captura-$captures.m4a')
      ..writeAsStringSync('a equipe falou');
    return lastPath = file.path;
  }

  File aFile(String name) => File('${home.path}/$name.m4a')
    ..writeAsStringSync('a equipe contou a passagem');

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
  final StreamController<void> _failures = StreamController<void>.broadcast();
  final StreamController<void> _openings = StreamController<void>.broadcast();
  final List<String> played = [];
  bool paused = false;

  Duration? length;
  Duration at = Duration.zero;
  final List<String> ranges = [];
  Completer<void>? _playing;
  Completer<void>? _opening;

  /// Hold the source load, the way an old tablet with a long take does.
  void holdNextOpening() => _opening = Completer<void>();

  void finishHeldOpening() {
    _opening?.complete();
    _opening = null;
  }

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<void> get failures => _failures.stream;

  @override
  Stream<void> get openings => _openings.stream;

  void failPlayback() {
    _failures.add(null);
    _stopSounding();
  }

  @override
  Duration? get playingLength => length;

  @override
  Duration get position => at;

  @override
  Future<void> play(String path) {
    played.add(path);
    return _soundUntilItStops();
  }

  @override
  Future<void> playRange(String path, Duration from, Duration to) {
    played.add(path);
    ranges.add('${from.inMilliseconds}-${to.inMilliseconds}');
    return _soundUntilItStops();
  }

  @override
  Future<void> pause() async {
    paused = true;
    _stopSounding();
  }

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async => _stopSounding();

  void finishPlayback() {
    _completions.add(null);
    _stopSounding();
  }

  // just_audio only completes the future of `play` when the sound stops: at the end
  // of the clip, on a pause or on a stop. A double that returns at once hides
  // everything hung off that future.
  Future<void> _soundUntilItStops() {
    _stopSounding();
    final playing = Completer<void>();
    _playing = playing;
    // A clip is not open the instant it is asked for: the source loads first, and only
    // then does the player rewind and know how long it is.
    final held = _opening;
    scheduleMicrotask(() async {
      await held?.future;
      at = Duration.zero;
      _openings.add(null);
    });
    return playing.future;
  }

  void _stopSounding() {
    final playing = _playing;
    _playing = null;
    playing?.complete();
  }

  @override
  Future<void> dispose() async {
    await _completions.close();
    await _openings.close();
  }
}

class FakeFinished implements FinishedPassages {
  final Set<String> done = {};

  @override
  Future<Set<String>> all(String book) async => {
        for (final row in done)
          if (row.startsWith('$book/')) row.substring(book.length + 1),
      };

  @override
  Future<void> add(String book, String pericope) async =>
      done.add('$book/$pericope');

  @override
  Future<bool> bookOpened(String book) async => done.contains('livro:$book');

  @override
  Future<void> markBookOpened(String book) async => done.add('livro:$book');
}

/// In memory, like the finished-passages double. The real one touches disk, and the
/// wheel now reads it on every open — under a widget test's fake clock that never
/// resolves, which hangs the whole suite.
const turnoUrl = '/api/internalization-room/voice/turno';
const panoramaUrl = '/api/internalization-room/voice/panorama';
const sceneUrl = '/api/internalization-room/voice/cena';

class FakeWorkInProgress implements WorkInProgress {
  final Map<String, ResumePoint> rows = {};

  @override
  Future<Set<String>> startedIn(String book) async => {
        for (final key in rows.keys)
          if (key.startsWith('$book/')) key.substring(book.length + 1),
      };

  @override
  Future<ResumePoint?> of(String book, String pericope) async =>
      rows['$book/$pericope'];

  @override
  Future<void> remember(String book, String pericope, ResumePoint point) async =>
      rows['$book/$pericope'] = point;

  @override
  Future<void> forget(String book, String pericope) async =>
      rows.remove('$book/$pericope');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInbox implements HandInboxRepository {
  List<HandReply> replies;
  final List<String> heard = [];
  final List<String> questionsSent = [];
  bool refuses = false;
  bool cannotBeAsked = false;

  FakeInbox({this.replies = const []});

  @override
  Future<List<HandReply>?> fetchReplies() async =>
      cannotBeAsked ? null : replies;

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
  final List<String?> bridgeModesSent = [];
  final List<int?> clipDurationsSent = [];
  final List<List<List<int>>> playedRangesSent = [];
  final List<bool> metBefore = [];
  final List<String> clipsFetched = [];
  bool reachable = true;
  Coverage nextCoverage = coverage();

  Coverage? settledCoverage;
  bool peerCue = false;
  /// Whether the opening comes back cut where the Guide marked it.
  bool opensInTwoMovements = false;
  bool done = false;
  int turnsSent = 0;
  int chunksSent = 0;
  final List<String> chunkSpans = [];
  final List<String> takesKept = [];
  String? refuseTake;
  bool chunkCaptured = true;
  bool turnsAreCanned = false;
  bool silentAboutCoverage = false;
  bool verdictChecked = true;
  BtFindingKind? verdictFinding;
  int? verdictFindingChunk;
  String? serverStatus;
  String fixedLine = '';
  String bridgeMode = '';
  final List<String> restartsAsked = [];
  final List<String> booksAsked = [];
  List<Passagem> passages = const [
    Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
    Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
    Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
  ];
  int personsAsked = 0;
  int retells = 0;
  int retellBudget = 3;

  Exception? failWith;

  Completer<void>? _holdingTurn;

  void holdNextTurn() => _holdingTurn = Completer<void>();

  void finishHeldTurn() {
    _holdingTurn?.complete();
    _holdingTurn = null;
  }

  Future<void> _turnArrives() {
    final held = _holdingTurn;
    return held == null ? Future<void>.value() : held.future;
  }

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
    String? bridgeMode,
  }) async {
    _guard('createSession');
    pericopesAsked.add(pericope);
    metBefore.add(afterSession != null);
    bridgeModesSent.add(bridgeMode);
    return SessionSnapshot(
      sessionId: 'sessao-1',
      pericope: pericope ?? 'rute-1',
      status: 'in_progress',
      coverage: nextCoverage,
      done: false,
    );
  }

  @override
  Future<List<Passagem>> passagesOf(String book) async {
    _guard('passagesOf');
    booksAsked.add(book);
    return passages;
  }

  @override
  Future<SessionSnapshot> fetchState(String sessionId) async {
    _guard('fetchState');
    return SessionSnapshot(
      sessionId: sessionId,
      pericope: 'rute-1',
      status: serverStatus ?? (done ? 'done' : 'in_progress'),
      coverage: silentAboutCoverage ? null : (settledCoverage ?? nextCoverage),
      done: done,
    );
  }

  @override
  Future<TurnResult> openSession(String sessionId) async {
    _guard('openSession');
    await _turnArrives();
    return _turn(sessionId);
  }

  @override
  Future<BackTranslationRestart> restartBackTranslation(String sessionId) async {
    _guard('restartBackTranslation');
    restartsAsked.add('novo-clipe');
    retells = 0;
    return const BackTranslationRestart(needsPerson: false);
  }

  @override
  Future<void> askForAPerson(String sessionId) async {
    _guard('askForAPerson');
    personsAsked++;
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
    await _turnArrives();
    return _turn(sessionId);
  }

  TurnResult _turn(String sessionId) => TurnResult(
        sessionId: sessionId,
        audioUrl: fixedLine.isEmpty ? turnoUrl : '',
        fixedLine: fixedLine,
        transcript: 'a equipe falou',
        peerCue: peerCue,
        usedFailSafe: turnsAreCanned,
        coverage: silentAboutCoverage ? null : nextCoverage,
        done: done,
        bridgeMode: bridgeMode,
        segments: opensInTwoMovements
            ? const [
                SpokenSegment(role: 'panorama', audioUrl: panoramaUrl),
                SpokenSegment(role: 'scene', audioUrl: sceneUrl),
              ]
            : const [],
      );

  @override
  Future<BackTranslationChunk> sendChunk(
    String sessionId,
    File audio, {
    Duration? from,
    Duration? to,
    bool retelling = false,
  }) async {
    _guard('sendChunk');
    chunksSent++;
    chunkSpans.add('${from?.inMilliseconds}-${to?.inMilliseconds}');
    if (retelling) retells++;
    return BackTranslationChunk(
      chunks: chunksSent,
      captured: chunkCaptured,
      passNumber: retelling ? 2 : 1,
      needsPerson: retelling && retells >= retellBudget,
    );
  }

  @override
  Future<BackTranslationVerdict> finishBackTranslation(
    String sessionId, {
    int? clipDurationMs,
    List<List<int>> playedRanges = const [],
  }) async {
    clipDurationsSent.add(clipDurationMs);
    playedRangesSent.add(playedRanges);
    _guard('finishBackTranslation');
    return BackTranslationVerdict(
      audioUrl: '/api/internalization-room/voice/veredito',
      fixedLine: '',
      checked: verdictChecked,
      findingKind: verdictFinding,
      findingChunk: verdictFindingChunk,
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
  bool radioSeesNothing = false;
  int checks = 0;

  @override
  Future<RoomReach> reachRoom() async {
    checks++;
    if (radioSeesNothing) return RoomReach.noNetwork;
    return reachable ? RoomReach.fine : RoomReach.roomSilent;
  }

  @override
  Stream<void> get onNetworkReturned => _returned.stream;

  void networkComesBack() => _returned.add(null);

  @override
  void dispose() => _returned.close();
}

class FakeScreenAwake implements ScreenAwake {
  bool held = false;

  @override
  Future<void> hold() async => held = true;

  @override
  Future<void> release() async => held = false;
}

class SalaHarness {
  final Directory takesHome = Directory.systemTemp.createTempSync('sala-tomadas');
  final FakeVoice voice = FakeVoice();
  final FacilitatorVoiceService? voiceService;
  final FakeRecorder recorder = FakeRecorder();
  final FakePlayback playback = FakePlayback();
  final FakeInbox inbox;
  final FakeRoom room = FakeRoom();
  final FakeNetwork network = FakeNetwork();
  final FakeScreenAwake awake = FakeScreenAwake();
  final Duration settleDelay;
  final List<Duration> retryBackoff;
  final Duration? beckonInterval;
  final Duration? busyCeiling;
  final Duration? playbackCeiling;
  final Duration clipGrace;
  final Duration shortestSpeech;
  final Duration fimLinger;

  SalaHarness({
    this.voiceService,
    List<HandReply> replies = const [],
    this.settleDelay = const Duration(milliseconds: 60),
    this.retryBackoff = const [Duration(milliseconds: 20)],
    this.beckonInterval,
    this.busyCeiling,
    this.playbackCeiling,
    this.clipGrace = const Duration(seconds: 10),
    this.shortestSpeech = Duration.zero,
    this.fimLinger = const Duration(seconds: 30),
  }) : inbox = FakeInbox(replies: replies);

  final FakeFinished finished = FakeFinished();

  final FakeWorkInProgress emAberto = FakeWorkInProgress();

  late final TakeUploadQueue takes = TakeUploadQueue(
    room: room,
    home: () async => takesHome,
  );

  List<Override> get overrides => [
        facilitatorVoiceProvider.overrideWithValue(voiceService ?? voice),
        recordingRepositoryProvider.overrideWithValue(recorder),
        playbackRepositoryProvider.overrideWithValue(playback),
        handInboxRepositoryProvider.overrideWithValue(inbox),
        roomRepositoryProvider.overrideWithValue(room),
        takeUploadQueueProvider.overrideWithValue(takes),
        finishedPassagesProvider.overrideWithValue(finished),
        workInProgressProvider.overrideWithValue(emAberto),
        connectivityServiceProvider.overrideWithValue(network),
        screenAwakeProvider.overrideWithValue(awake),
        beadSettleDelayProvider.overrideWithValue(settleDelay),
        roomRetryBackoffProvider.overrideWithValue(retryBackoff),
        beckonIntervalProvider.overrideWithValue(beckonInterval),
        busyStateCeilingProvider.overrideWithValue(busyCeiling),
        playbackCeilingProvider.overrideWithValue(playbackCeiling),
        clipGraceProvider.overrideWithValue(clipGrace),
        shortestSpeechProvider.overrideWithValue(shortestSpeech),
        fimLingerProvider.overrideWithValue(fimLinger),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);
}

class SpeakingPlayer extends Fake implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast();
  Completer<void>? _sounding;
  Duration? lineLength = const Duration(milliseconds: 20);
  bool stopsBeforeTheEnd = false;
  ProcessingState _state = ProcessingState.ready;

  @override
  ProcessingState get processingState => _state;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async =>
      lineLength;

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    Duration? initialPosition,
    String? package,
    bool preload = true,
    dynamic tag,
  }) async =>
      lineLength;

  @override
  Future<void> play() {
    _sounding = Completer<void>();
    if (stopsBeforeTheEnd) _quiet();
    return _sounding!.future;
  }

  @override
  Future<void> stop() async => _quiet();

  void pauseIt() => _quiet();

  void reachTheEnd() {
    _state = ProcessingState.completed;
    _states.add(PlayerState(false, ProcessingState.completed));
    _quiet();
  }

  void _quiet() {
    if (_sounding?.isCompleted == false) _sounding!.complete();
  }

  @override
  Future<void> dispose() async => _states.close();
}
