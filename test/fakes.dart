import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
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
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

/// Throwing here instead of returning keeps the failure at the wait: a deadline that
/// passes in silence surfaces as an unrelated error several lines later.
Future<void> waitFor(
  String what,
  FutureOr<bool> Function() ready, {
  Duration limit = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      final waited = limit.inMilliseconds % 1000 == 0
          ? '${limit.inSeconds}s'
          : '${limit.inMilliseconds}ms';
      throw TimeoutException('esperei $waited e $what não aconteceu', limit);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

const totalBeads = 12;

const testLanguage = 'pt';

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
  final StreamController<bool> _interruptions =
      StreamController<bool>.broadcast();
  final Directory home = Directory.systemTemp.createTempSync('sala-gravacoes');
  int captures = 0;
  bool returnsNothing = false;
  bool returnsEmpty = false;
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

  @override
  Stream<bool> get interrupted => _interruptions.stream;

  void takeTheMicrophone() => _interruptions.add(true);

  void giveTheMicrophoneBack() => _interruptions.add(false);

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
      ..writeAsStringSync(returnsEmpty ? '' : 'a equipe falou');
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
  Future<void> dispose() async => _interruptions.close();
}

class FakePlayback implements PlaybackRepository {
  final StreamController<void> _completions = StreamController<void>.broadcast();
  final StreamController<void> _failures = StreamController<void>.broadcast();
  final StreamController<void> _openings = StreamController<void>.broadcast();
  final List<String> played = [];
  bool paused = false;

  /// Whether the real player would be making sound right now. False on a pause, a stop,
  /// or a completion, however it was reached — including a ceiling that fired before the
  /// clip itself said it was done.
  bool get sounding => _sounding;

  Duration? length;
  Duration at = Duration.zero;
  final List<String> ranges = [];
  Completer<void>? _playing;
  Completer<void>? _opening;
  Timer? _walking;
  Duration _step = Duration.zero;
  bool _sounding = false;

  /// Let the position walk on its own, the way a real player's does.
  ///
  /// Opt-in, because the position is otherwise a number the test writes by hand. A double
  /// that only ever walked forward would lie about the two states that matter as much as
  /// playing: the position stands still on a pause, a stop or the end of the clip, and it
  /// stops at the clip's own length instead of running past it.
  void walkWhilePlaying({Duration step = const Duration(milliseconds: 100)}) {
    _step = step;
    if (_sounding) _startWalking();
  }

  void stopWalking() {
    _walking?.cancel();
    _walking = null;
  }

  void _startWalking() {
    stopWalking();
    if (_step == Duration.zero) return;
    _walking = Timer.periodic(_step, (_) {
      final fim = length;
      final proximo = at + _step;
      if (fim != null && proximo >= fim) {
        at = fim;
        stopWalking();
        return;
      }
      at = proximo;
    });
  }

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

  Duration? measured = const Duration(seconds: 30);
  final List<String> measurements = [];
  Completer<void>? _measuring;

  /// Hold the measuring, the way an old tablet holds a long file on its second player.
  void holdNextMeasurement() => _measuring = Completer<void>();

  void finishHeldMeasurement() {
    _measuring?.complete();
    _measuring = null;
  }

  @override
  Future<Duration?> howLong(String path) async {
    measurements.add(path);
    await _measuring?.future;
    return measured;
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
  Future<void> resume() async {
    paused = false;
    // Sound coming back out, not a new clip: the future `play` handed out is long since
    // completed by the pause, so it cannot be what says whether anything is sounding.
    _sounding = true;
    _startWalking();
  }

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
      if (_playing != playing) return;
      _sounding = true;
      _startWalking();
    });
    return playing.future;
  }

  void _stopSounding() {
    _sounding = false;
    stopWalking();
    final playing = _playing;
    _playing = null;
    playing?.complete();
  }

  @override
  Future<void> dispose() async {
    stopWalking();
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

  /// Whether the desk turns the mark down — the real one answers for itself now, so the
  /// double has to be able to say no as well as yes.
  bool refusesMarks = false;

  @override
  Future<bool> markHeard(String replyId) async {
    if (refusesMarks) return false;
    heard.add(replyId);
    return true;
  }

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
  final List<String> languagesSent = [];
  final List<String> languagesAsked = [];
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
  /// Which recording each told-back stretch named, in order.
  final List<String> chunkTakes = [];
  /// The names this room gave the recordings it stored, in the order it stored them.
  final List<String> takeIds = [];
  /// The stretches this room kept, in the order they were told. A room that forgets what
  /// it was told cannot hand a telling-back back, and cannot name the stretch a finding
  /// lands on either.
  final List<SegmentView> segments = [];

  List<String> get segmentIds =>
      [for (final segment in segments) segment.segmentId];
  final List<String> takesKept = [];
  final List<int?> takePasses = [];
  String? refuseTake;
  Exception? failRestartWith;
  Exception? failDivideWith;
  Exception? failReplaceWith;

  /// What the ask for a verdict throws, when it is set. The one knob that lets a test put
  /// a failure between a correction the room answered and the answer reaching the team.
  Exception? failFinishWith;

  /// Run while the ask for a verdict is still in the air. The seam for a test that needs
  /// the team to do something — leave the passage, say — during that wait.
  void Function()? duranteOVeredito;
  bool replaceCaptured = true;

  /// Whether the room answers a correction by asking for a person. False is also what
  /// a server that does not send the field at all looks like from here.
  bool replaceNeedsPerson = false;
  /// Which stretch each retelling named, and the slice it sent, in order.
  final List<String> replacesAsked = [];
  /// Which stretches arrived as a new mother-tongue recording — a replacement carrying no
  /// explanation, which is the only shape the room accepts for a re-recorded voice.
  final List<String> replacesSemArquivo = [];
  int _versoes = 0;
  /// Which stretch each division named, and where it was cut, in order.
  final List<String> dividesAsked = [];
  bool chunkCaptured = true;
  bool turnsAreCanned = false;
  bool turnsAreDegraded = false;
  bool silentAboutCoverage = false;
  bool verdictChecked = true;
  /// Whether the verdict itself is a canned line the room could not compose — the wire
  /// twin of [turnsAreCanned] for the turn that closes a telling-back, and the only way a
  /// test can make the findings screen open with nothing worth repeating.
  bool verdictUsedFailSafe = false;
  /// What the room answers about the telling-back, when a test wants to state it rather
  /// than build it up by telling stretches back.
  BackTranslationProgress? retroSoFar;
  String? verdictFindingSegmentId;

  /// Which place on the cord the analyst points at, when it points by place instead of by
  /// name. Read at the moment the verdict is built, which is the only way to say "the same
  /// stretch again": mending retires a name and mints a new one, so a test that wanted to
  /// reprove what the team just corrected could only name it by guessing the double's
  /// versioning scheme.
  int? verdictFindingPlace;

  /// Which stretch the room says was recorded and never told back, when that is what
  /// stopped the reading. Its own field, as on the wire: a finding and an untold stretch
  /// are never named in the same answer — and neither is the place above, which addresses
  /// a stretch the team told.
  String? verdictUntoldSegmentId;
  BtFindingKind? verdictFinding;
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
  /// The passage the room hands back when this tablet asks for the panorama.
  String? panoramaAnsweredWith;

  int personsAsked = 0;
  int retells = 0;
  int retellBudget = 3;

  final List<String?> codesAskedFor = [];
  int linksRead = 0;
  List<String> claimCodes = const ['QHF-3M7K'];
  Duration claimCodeLife = const Duration(minutes: 15);
  TeamLink? linkedTo;

  Exception? failWith;

  String? shutsThePassage;

  Completer<void>? _holdingTurn;
  Completer<void>? _holdingCode;

  void holdNextCode() => _holdingCode = Completer<void>();

  void finishHeldCode() {
    _holdingCode?.complete();
    _holdingCode = null;
  }

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
  Future<ClaimCode> askForACode(String? deviceId) async {
    _guard('askForACode');
    codesAskedFor.add(deviceId);
    final held = _holdingCode;
    if (held != null) await held.future;
    return ClaimCode(
      deviceId: 'aparelho-1',
      code: claimCodes[min(codesAskedFor.length - 1, claimCodes.length - 1)],
      expiresAt: DateTime.now().toUtc().add(claimCodeLife),
    );
  }

  @override
  Future<TeamLink?> readTheLink(String deviceId) async {
    _guard('readTheLink');
    linksRead++;
    return linkedTo;
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
    required String language,
  }) async {
    _guard('createSession');
    if (pericope != null && pericope == shutsThePassage) throw const PassageShut();
    pericopesAsked.add(pericope);
    metBefore.add(afterSession != null);
    bridgeModesSent.add(bridgeMode);
    languagesSent.add(language);
    // The server decides which passage a session is for; asking for the panorama is a
    // request, not an instruction. Today it always honours "OV", and this is where that
    // stops being true.
    final answered = pericope == panoramaPericope && panoramaAnsweredWith != null
        ? panoramaAnsweredWith
        : pericope;
    return SessionSnapshot(
      sessionId: 'sessao-1',
      pericope: answered ?? 'rute-1',
      status: 'in_progress',
      coverage: nextCoverage,
      done: false,
    );
  }

  @override
  Future<List<Passagem>> passagesOf(String book, {required String language}) async {
    _guard('passagesOf');
    booksAsked.add(book);
    languagesAsked.add(language);
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
      backTranslation:
          retroSoFar ?? BackTranslationProgress(segments: List.of(segments)),
    );
  }

  @override
  Future<TurnResult> openSession(String sessionId) async {
    _guard('openSession');
    await _turnArrives();
    return _turn(sessionId);
  }

  @override
  Future<TellingAgain> replaceSegment(
    String sessionId,
    String segmentId,
    File? audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) async {
    _guard('replaceSegment');
    final refusal = failReplaceWith;
    if (refusal != null) throw refusal;
    replacesAsked.add(
      '$segmentId@$takeId:${from.inMilliseconds}-${to.inMilliseconds}',
    );
    if (audio == null) replacesSemArquivo.add(segmentId);
    if (!replaceCaptured) {
      return TellingAgain(
        segments: List.of(segments),
        captured: false,
        needsPerson: replaceNeedsPerson,
      );
    }
    final at = segments.indexWhere((one) => one.segmentId == segmentId);
    if (at >= 0) {
      final antes = segments[at];
      // The route has two shapes and this double owes both. With audio over the same
      // slice, the explanation was redone and the stretch is told. With no audio the
      // mother tongue was re-recorded: the stretch takes the new recording and its slice,
      // and goes back to waiting — the telling that belonged to the audio nobody will
      // hear again does not carry over.
      // A version is a new row, not an edit in place: the room mints a fresh id for the
      // successor and retires the one it replaces. A double that kept the id would let an
      // app follow a pointer the room has already thrown away.
      segments[at] = SegmentView(
        segmentId: '${antes.segmentId}-v${++_versoes}',
        takeId: audio == null ? takeId : antes.takeId,
        startsMs: audio == null ? from.inMilliseconds : antes.startsMs,
        endsMs: audio == null ? to.inMilliseconds : antes.endsMs,
        passNumber: antes.passNumber,
        told: audio != null,
      );
    }
    return TellingAgain(
      segments: List.of(segments),
      captured: true,
      needsPerson: replaceNeedsPerson,
    );
  }

  @override
  Future<List<SegmentView>> divideSegment(
    String sessionId,
    String segmentId, {
    required Duration at,
  }) async {
    _guard('divideSegment');
    final refusal = failDivideWith;
    if (refusal != null) throw refusal;
    dividesAsked.add('$segmentId@${at.inMilliseconds}');
    final cut = segments.indexWhere((one) => one.segmentId == segmentId);
    if (cut < 0) return List.of(segments);
    final whole = segments[cut];
    segments
      ..removeAt(cut)
      ..insertAll(cut, [
        SegmentView(
          segmentId: '${whole.segmentId}-a',
          takeId: whole.takeId,
          startsMs: whole.startsMs,
          endsMs: at.inMilliseconds,
          passNumber: whole.passNumber,
          told: false,
        ),
        SegmentView(
          segmentId: '${whole.segmentId}-b',
          takeId: whole.takeId,
          startsMs: at.inMilliseconds,
          endsMs: whole.endsMs,
          passNumber: whole.passNumber,
          told: false,
        ),
      ]);
    return List.of(segments);
  }

  @override
  Future<BackTranslationRestart> restartBackTranslation(String sessionId) async {
    _guard('restartBackTranslation');
    final refusal = failRestartWith;
    if (refusal != null) throw refusal;
    restartsAsked.add('novo-clipe');
    await _turnArrives();
    retells = 0;
    return const BackTranslationRestart(needsPerson: false);
  }

  @override
  Future<void> askForAPerson(String sessionId) async {
    _guard('askForAPerson');
    personsAsked++;
  }

  @override
  Future<String> sendTake(
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
    takePasses.add(passNumber);
    final id = 'gravacao-${takeIds.length + 1}';
    takeIds.add(id);
    return id;
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
        degraded: turnsAreDegraded,
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
    required String takeId,
    required Duration from,
    required Duration to,
    bool retelling = false,
  }) async {
    _guard('sendChunk');
    chunksSent++;
    chunkSpans.add('${from.inMilliseconds}-${to.inMilliseconds}');
    chunkTakes.add(takeId);
    if (chunkCaptured) {
      segments.add(SegmentView(
        segmentId: 'trecho-${segments.length + 1}',
        takeId: takeId,
        startsMs: from.inMilliseconds,
        endsMs: to.inMilliseconds,
        passNumber: retelling ? 2 : 1,
      ));
    }
    if (retelling) retells++;
    return BackTranslationChunk(
      chunks: chunksSent,
      captured: chunkCaptured,
      passNumber: retelling ? 2 : 1,
      needsPerson: retelling && retells >= retellBudget,
    );
  }

  String? _oQueOAnalistaAponta() {
    final place = verdictFindingPlace;
    if (place == null) return verdictFindingSegmentId;
    return place >= 0 && place < segments.length
        ? segments[place].segmentId
        : null;
  }

  @override
  Future<BackTranslationVerdict> finishBackTranslation(
    String sessionId, {
    int? clipDurationMs,
    List<List<int>> playedRanges = const [],
  }) async {
    duranteOVeredito?.call();
    final refusal = failFinishWith;
    if (refusal != null) throw refusal;
    clipDurationsSent.add(clipDurationMs);
    playedRangesSent.add(playedRanges);
    _guard('finishBackTranslation');
    return BackTranslationVerdict(
      audioUrl: '/api/internalization-room/voice/veredito',
      fixedLine: '',
      checked: verdictChecked,
      findingKind: verdictFinding,
      findingSegmentId: _oQueOAnalistaAponta(),
      untoldSegmentId: verdictUntoldSegmentId,
      findingsRemaining: verdictFinding == null ? 0 : 1,
      usedFailSafe: verdictUsedFailSafe,
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

class FakeLinkedTeam implements LinkedTeam {
  RememberedLink remembered;

  FakeLinkedTeam({this.remembered = const RememberedLink()});

  @override
  Future<RememberedLink> read() async => remembered;

  @override
  Future<void> rememberDevice(String deviceId) async =>
      remembered = RememberedLink(deviceId: deviceId, team: remembered.team);

  @override
  Future<void> rememberTeam(TeamLink team) async =>
      remembered = RememberedLink(deviceId: remembered.deviceId, team: team);
}

/// The upload outbox with no disk under it.
///
/// The real queue copies audio and writes its manifest with dart:io, and a widget test's
/// binding never lets real IO that started under its clock finish — measured, not
/// assumed: a rehearsal part never reaches the room in one, at any amount of pumping.
/// That was invisible until a told-back stretch had to name the recording it came from.
///
/// Opt-in and never the default: a test that does not know this exists keeps the real
/// queue, and every test that measures the outbox itself — what is still unsent, what was
/// given up on, what is stranded — goes on measuring the real one.
class FakeTakeQueue implements TakeUploadQueue {
  final FakeRoom room;
  final List<PendingTake> rows = [];
  int _minted = 0;

  FakeTakeQueue({required this.room});

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    final entry = PendingTake(
      id: '${_minted++}',
      path: audio.path,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
    );
    rows.add(entry);
    return entry;
  }

  @override
  Future<int> flush() async {
    var sent = 0;
    for (var at = 0; at < rows.length; at++) {
      final entry = rows[at];
      if (entry.stored) continue;
      final String landed;
      try {
        landed = await room.sendTake(
          entry.sessionId,
          File(entry.path),
          kind: entry.kind,
          scope: entry.scope,
          passNumber: entry.passNumber,
          chunkIndex: entry.chunkIndex,
        );
      } on Exception {
        rows[at] = entry.copyWith(attempts: entry.attempts + 1);
        continue;
      }
      rows[at] = entry.copyWith(takeId: landed, stored: true);
      sent++;
    }
    return sent;
  }

  @override
  Future<String?> takeIdOf(
    String kind, {
    required String sessionId,
    required String scope,
  }) async {
    for (final entry in rows) {
      if (entry.kind == kind &&
          entry.sessionId == sessionId &&
          entry.scope == scope &&
          entry.takeId != null) {
        return entry.takeId;
      }
    }
    return null;
  }

  @override
  Future<List<PendingTake>> entries() async => List.of(rows);

  @override
  Future<List<PendingTake>> pending() async =>
      [for (final entry in rows) if (!entry.stored) entry];

  @override
  Future<List<PendingTake>> giveUps() async => const [];

  @override
  Future<bool> lostHistory() async => false;

  @override
  Future<int> unsentOf(String kind, {required String sessionId}) async => [
        for (final entry in rows)
          if (!entry.stored && entry.kind == kind && entry.sessionId == sessionId)
            entry,
      ].length;

  Completer<void>? _armed;
  Completer<void>? _holding;

  /// Hold the next reading *after* it has looked at the queue, so a count taken while
  /// recordings were still here can be made to arrive after a newer one.
  void holdTheNextReading() => _armed = Completer<void>();

  /// Whether a reading is parked in the hold with its numbers already taken. Waiting on
  /// a duration here instead would let the queue change first, and the older reading
  /// would come back as fresh as the newer one — a race the case never ran.
  bool get readingHeld => _holding != null;

  void releaseTheHeldReading() {
    _holding?.complete();
    _holding = null;
  }

  @override
  Future<Set<String>> unsentScopesOf(
    String kind, {
    required String sessionId,
  }) async {
    final held = _armed;
    _armed = null;
    if (held != null) _holding = held;
    final scopes = {
      for (final entry in rows)
        if (!entry.stored && entry.kind == kind && entry.sessionId == sessionId)
          entry.scope,
    };
    if (held != null) await held.future;
    return scopes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Let the tablet's real disk work finish inside a widget test.
///
/// Keeping a rehearsal part copies the audio and writes the upload manifest with dart:io,
/// and a pumped clock never advances that. The room answers with the name it gave the
/// recording across the same stretch of time, and a told-back stretch cannot name a
/// recording the room has not answered for yet.
Future<void> letTheRehearsalReachTheRoom(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump(const Duration(milliseconds: 100));
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
  final FakeLinkedTeam vinculo;
  final Duration settleDelay;
  final List<Duration> retryBackoff;
  final Duration? beckonInterval;
  final Duration? busyCeiling;
  final Duration? playbackCeiling;
  final Duration clipGrace;
  final Duration shortestSpeech;
  final Duration fimLinger;
  /// Whether the outbox keeps its rows in memory instead of on disk. Opt-in, for widget
  /// tests, whose binding never lets the real queue's IO finish.
  final bool filaEmMemoria;

  final String? lingua;

  SalaHarness({
    this.voiceService,
    List<HandReply> replies = const [],
    RememberedLink linkedAs = const RememberedLink(
      deviceId: 'aparelho-1',
      team: TeamLink(projectId: 'equipe-1'),
    ),
    this.linkPoll,
    this.settleDelay = const Duration(milliseconds: 60),
    this.retryBackoff = const [Duration(milliseconds: 20)],
    this.beckonInterval,
    this.busyCeiling,
    this.playbackCeiling,
    this.clipGrace = const Duration(seconds: 10),
    this.shortestSpeech = Duration.zero,
    this.fimLinger = const Duration(seconds: 30),
    this.filaEmMemoria = false,
    this.lingua = testLanguage,
    this.emAbertoNoDisco,
    this.inboxService,
  })  : inbox = FakeInbox(replies: replies),
        vinculo = FakeLinkedTeam(remembered: linkedAs);

  final Duration? linkPoll;

  final FakeFinished finished = FakeFinished();

  /// The real inbox, for the cases that need a server that can refuse or go away.
  final HandInboxRepository? inboxService;

  final FakeWorkInProgress emAberto = FakeWorkInProgress();

  /// The real ledger, for the tests that need a disk that can refuse.
  final WorkInProgress? emAbertoNoDisco;

  late final TakeUploadQueue takes = filaEmMemoria
      ? FakeTakeQueue(room: room)
      : TakeUploadQueue(room: room, home: () async => takesHome);

  List<Override> get overrides => [
        facilitatorVoiceProvider.overrideWithValue(voiceService ?? voice),
        recordingRepositoryProvider.overrideWithValue(recorder),
        playbackRepositoryProvider.overrideWithValue(playback),
        handInboxRepositoryProvider.overrideWithValue(inboxService ?? inbox),
        roomRepositoryProvider.overrideWithValue(room),
        takeUploadQueueProvider.overrideWithValue(takes),
        finishedPassagesProvider.overrideWithValue(finished),
        workInProgressProvider.overrideWithValue(emAbertoNoDisco ?? emAberto),
        connectivityServiceProvider.overrideWithValue(network),
        linkedTeamProvider.overrideWithValue(vinculo),
        linkPollIntervalProvider.overrideWithValue(linkPoll),
        screenAwakeProvider.overrideWithValue(awake),
        beadSettleDelayProvider.overrideWithValue(settleDelay),
        roomRetryBackoffProvider.overrideWithValue(retryBackoff),
        beckonIntervalProvider.overrideWithValue(beckonInterval),
        busyStateCeilingProvider.overrideWithValue(busyCeiling),
        playbackCeilingProvider.overrideWithValue(playbackCeiling),
        clipGraceProvider.overrideWithValue(clipGrace),
        shortestSpeechProvider.overrideWithValue(shortestSpeech),
        fimLingerProvider.overrideWithValue(fimLinger),
        if (lingua != null) roomLanguageProvider.overrideWithValue(lingua!),
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

  bool get sounding => _sounding?.isCompleted == false;

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

  bool _playing = false;

  @override
  bool get playing => _playing;

  @override
  Future<void> play() {
    // just_audio returns at once when it already believes it is playing
    // (just_audio.dart:939), and iOS never clears that flag when a clip ends: the native
    // `complete` sets processingState and leaves `_playing` YES. Only stop, pause or a
    // failed session activation clear it.
    if (_playing) return Future<void>.value();
    _playing = true;
    _sounding = Completer<void>();
    if (stopsBeforeTheEnd) _quiet();
    return _sounding!.future;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _quiet();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _quiet();
  }

  void pauseIt() {
    _playing = false;
    _quiet();
  }

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

class QueueHeldOnGiveUps extends TakeUploadQueue {
  QueueHeldOnGiveUps({required super.room, super.home});

  final Completer<void> asking = Completer<void>();
  final Completer<void> answer = Completer<void>();

  @override
  Future<List<PendingTake>> giveUps() async {
    if (!asking.isCompleted) asking.complete();
    await answer.future;
    return super.giveUps();
  }
}
