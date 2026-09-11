import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/credential_vault.dart';
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
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
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

/// Ends the room before the binding looks for a timer still in the air.
///
/// A room stopped for a person keeps asking the server whether the halt is still
/// standing, on a cadence that ends only with the halt or with the room. A widget test
/// that leaves the team on a halt therefore always has one timer pending, and the
/// `addTearDown` that disposes the container runs after the check that would see it.
void closeTheRoom(ProviderContainer container) => container.dispose();

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

  /// How many times the room told this voice to stop, whatever it was saying.
  int stops = 0;

  @override
  Future<void> stop() async => stops++;

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
  Future<String> keepBytes(Uint8List bytes, String fileName) async {
    final file = File('${home.path}/$fileName.m4a')..writeAsBytesSync(bytes);
    return file.path;
  }

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

  /// How long a particular file is, for a test whose files are not all the same length.
  final Map<String, Duration> lengths = {};

  @override
  Future<Duration?> howLong(String path) async {
    measurements.add(path);
    await _measuring?.future;
    return lengths[path] ?? measured;
  }

  @override
  Duration? get playingLength => length;

  @override
  Duration get position => at;

  @override
  Future<void> play(String path, {Duration from = Duration.zero}) {
    played.add(path);
    return _soundUntilItStops(from);
  }

  @override
  Future<void> playRange(String path, Duration from, Duration to) {
    played.add(path);
    ranges.add('${from.inMilliseconds}-${to.inMilliseconds}');
    // At nought, not at [from]: a clip answers its position counted from its own start,
    // which is the very reason the resumed telling-back is not built on one.
    return _soundUntilItStops(Duration.zero);
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
  Future<void> _soundUntilItStops(Duration from) {
    _stopSounding();
    final playing = Completer<void>();
    _playing = playing;
    // A clip is not open the instant it is asked for: the source loads first, and only
    // then does the player know where it starts and how long it is.
    final held = _opening;
    scheduleMicrotask(() async {
      await held?.future;
      at = from;
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
  /// What this tablet last told the hand to present as itself. What the header actually
  /// carries is measured against real HTTP, not here.
  String? presented;

  @override
  void presents(String? credential) => presented = credential;

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
  final List<List<Map<String, Object?>>> playedByTakeSent = [];
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

  /// Every recording this room is holding, as the route that lists them answers.
  final List<TakeView> takes = [];

  /// The bytes each take's audio comes back as, so a test can tell one file from another.
  final Map<String, Uint8List> takeAudio = {};

  /// The name the rebuilt passage gets, when this room rebuilds one. Null is a room that
  /// composes nothing — a short correction, or a rebuilding that could not be done.
  String? composesInto;

  /// What listing the takes throws, when it is set.
  Exception? failTakesWith;
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
  /// Which kind of halt the room reports beside `serverStatus`. A server older than
  /// #336 names none, which is `HaltKind.unnamed`.
  HaltKind serverHalt = HaltKind.unnamed;

  /// A facilitator marked the session attended on the desk, and the room stops
  /// answering that it is halted.
  void theDeskAttended() {
    serverStatus = null;
    serverHalt = HaltKind.unnamed;
  }
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
  /// The ids this room gave the sessions it opened, in the order it opened them.
  final List<String> sessionIds = [];
  /// Which session each turn was spoken into, the opening one included, in order.
  final List<String> sessionsSpokenTo = [];

  int personsAsked = 0;
  int retells = 0;
  int retellBudget = 3;

  final List<String?> codesAskedFor = [];
  /// Which device this room was asked to hand a credential to, in order.
  final List<String> credentialsCollected = [];
  /// What this tablet last told the room to present as itself. What the header actually
  /// carries is measured against real HTTP, not here.
  String? presented;
  String credential = 'credencial-1';
  Exception? refuseCredentialWith;
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

  /// What a held call throws when it is let go. A room that always succeeded once the
  /// wait was over could not be asked what the app does when a call already in the air
  /// fails — which is the only way the room reaches some of its own states.
  Exception? failHeldTurnWith;

  Future<void> _turnArrives() async {
    final held = _holdingTurn;
    if (held != null) await held.future;
    final failure = failHeldTurnWith;
    if (failure != null) {
      failHeldTurnWith = null;
      throw failure;
    }
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
  Future<String> collectTheCredential(String deviceId) async {
    _guard('collectTheCredential');
    credentialsCollected.add(deviceId);
    final refusal = refuseCredentialWith;
    if (refusal != null) throw refusal;
    return credential;
  }

  @override
  void presents(String? credential) => presented = credential;

  @override
  Future<Uint8List> fetchClip(String url) async {
    _guard('fetchClip');
    clipsFetched.add(url);
    final refusal = failClipWith;
    if (refusal != null) throw refusal;
    for (final entry in takeAudio.entries) {
      if (url.endsWith('/takes/${entry.key}/audio')) return entry.value;
    }
    return Uint8List.fromList([1, 2, 3]);
  }

  /// What fetching audio throws, when it is set.
  Exception? failClipWith;

  @override
  Future<List<TakeView>> takesOf(String sessionId) async {
    _guard('takesOf');
    final refusal = failTakesWith;
    if (refusal != null) throw refusal;
    return List.of(takes);
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
    final sessionId = 'sessao-${sessionIds.length + 1}';
    sessionIds.add(sessionId);
    return SessionSnapshot(
      sessionId: sessionId,
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
      halt: serverHalt,
      backTranslation:
          retroSoFar ?? BackTranslationProgress(segments: List.of(segments)),
    );
  }

  @override
  Future<TurnResult> openSession(String sessionId) async {
    _guard('openSession');
    sessionsSpokenTo.add(sessionId);
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
    final antes = at >= 0 ? segments[at] : null;
    if (antes != null) {
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
      composedTakeId: audio == null ? _recompose(antes, at) : null,
    );
  }

  /// Rebuild the passage under a stretch just re-recorded, and re-point every stretch that
  /// was a slice of the recording it replaced.
  ///
  /// The room's own arithmetic: a boundary at or before the start of the corrected stretch
  /// stays put, and one past it moves by the difference the correction made. Not a new
  /// version of any of them — the same sound at a different offset in a different file —
  /// so every neighbour keeps the name it already had.
  ///
  /// Nothing is rebuilt when the mother tongue did not move to another recording, which is
  /// the short correction, and nothing is rebuilt when [composesInto] is unset, which is
  /// how a room without an encoder answers.
  String? _recompose(SegmentView? replaced, int at) {
    final rebuilt = composesInto;
    if (rebuilt == null || replaced == null || at < 0) return null;
    final version = segments[at];
    if (version.takeId == replaced.takeId) return null;
    final started = replaced.startsMs;
    final grew = (version.endsMs - version.startsMs) -
        (replaced.endsMs - replaced.startsMs);
    int moved(int ms) => ms <= started ? ms : ms + grew;
    for (var onde = 0; onde < segments.length; onde++) {
      final row = segments[onde];
      if (onde == at) {
        segments[onde] = _pointedAt(row, rebuilt, started, moved(replaced.endsMs));
      } else if (row.takeId == replaced.takeId) {
        segments[onde] =
            _pointedAt(row, rebuilt, moved(row.startsMs), moved(row.endsMs));
      }
    }
    final was = takes.where((take) => take.takeId == replaced.takeId);
    takes.add(TakeView(
      takeId: rebuilt,
      scope: KeptScope.composed,
      ordinal: was.isEmpty ? null : was.first.ordinal,
    ));
    takeAudio[rebuilt] = Uint8List.fromList(utf8.encode('áudio de $rebuilt'));
    return rebuilt;
  }

  SegmentView _pointedAt(SegmentView row, String takeId, int starts, int ends) =>
      SegmentView(
        segmentId: row.segmentId,
        takeId: takeId,
        startsMs: starts,
        endsMs: ends,
        passNumber: row.passNumber,
        told: row.told,
      );

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

  /// Whether the room asks for a person to come and watch on the next restart of the
  /// telling-back — a warning, the same as [serverHalt]'s and the retold chunk's.
  bool restartNeedsPerson = false;

  @override
  Future<BackTranslationRestart> restartBackTranslation(String sessionId) async {
    _guard('restartBackTranslation');
    final refusal = failRestartWith;
    if (refusal != null) throw refusal;
    restartsAsked.add('novo-clipe');
    await _turnArrives();
    retells = 0;
    return BackTranslationRestart(needsPerson: restartNeedsPerson);
  }

  /// What the next call to the session-scoped ask throws, independent of `failWith` —
  /// a case needs a turn to succeed (so the halt is reached with a live session) and
  /// only the ask itself to fail, and `failWith` is shared by every guarded call.
  Exception? askForAPersonFailsWith;

  Completer<void>? _holdingAskForAPerson;

  /// Holds the next session-scoped ask in flight, so a test can act — resolve the halt,
  /// change `askForAPersonFailsWith` — before the answer lands.
  void holdNextAskForAPerson() => _holdingAskForAPerson = Completer<void>();

  void finishHeldAskForAPerson() {
    _holdingAskForAPerson?.complete();
    _holdingAskForAPerson = null;
  }

  @override
  Future<void> askForAPerson(String sessionId) async {
    _guard('askForAPerson');
    final held = _holdingAskForAPerson;
    if (held != null) await held.future;
    final failure = askForAPersonFailsWith;
    if (failure != null) throw failure;
    personsAsked++;
    // The route is what raises the blocking halt on the server: a double that only
    // counted the call answered the next state read as if nobody had asked.
    serverStatus = 'needs_person';
    serverHalt = HaltKind.blocking;
  }

  /// What the next call to `personArrived` throws, independent of `failWith` — a case
  /// needs the halt to stay reachable and only the arrival ping itself to fail.
  Exception? personArrivedFailsWith;

  /// Every session id `personArrived` was called for, one entry per attempt.
  final List<String> personArrivedSessions = [];

  @override
  Future<void> personArrived(String sessionId) async {
    _guard('personArrived');
    personArrivedSessions.add(sessionId);
    final failure = personArrivedFailsWith;
    if (failure != null) throw failure;
  }

  /// Every device id the device-scoped ask was made for, one entry per attempt —
  /// including one that is about to fail, the way `calls` tracks `askForAPerson`.
  final List<String> deviceAsksReceived = [];

  /// What the next calls to the device-scoped ask throw, consumed in order. Separate
  /// from `failWith` because a case has to fail this route without touching the
  /// session-scoped one, and has to fail it a fixed number of times and then stop.
  final List<Object> deviceAskFailures = [];

  @override
  Future<void> askForAPersonWithoutASession(String deviceId) async {
    deviceAsksReceived.add(deviceId);
    if (deviceAskFailures.isNotEmpty) throw deviceAskFailures.removeAt(0);
  }

  /// Which scope's upload to hold, and until when. Lets a test put a real gap between
  /// one take reaching the room and another guard() call finding the outbox already
  /// mid-flush — the overlap a slow network opens and a fast fake never does on its own.
  String? holdTakeScope;
  Completer<void>? _holdingTake;
  Completer<void>? _reachedTakeHold;

  void holdNextTake(String scope) {
    holdTakeScope = scope;
    _holdingTake = Completer<void>();
    _reachedTakeHold = Completer<void>();
  }

  /// Waits until the held scope's sendTake is the one actually blocking, not just asked.
  Future<void> untilTakeHeld() async => _reachedTakeHold?.future;

  void finishHeldTake() {
    _holdingTake?.complete();
    _holdingTake = null;
    holdTakeScope = null;
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
    if (scope == holdTakeScope) {
      _reachedTakeHold?.complete();
      await _holdingTake?.future;
    }
    if (refuseTake == '$kind/$scope') throw const RoomRefused();
    takesKept.add('$kind/$scope');
    takePasses.add(passNumber);
    final id = 'gravacao-${takeIds.length + 1}';
    takeIds.add(id);
    takes.add(TakeView(takeId: id, scope: scope, ordinal: chunkIndex));
    takeAudio[id] = Uint8List.fromList(utf8.encode('áudio de $id'));
    return id;
  }

  @override
  Future<TurnResult> sendTurn(String sessionId, File audio) async {
    _guard('sendTurn');
    sessionsSpokenTo.add(sessionId);
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
    required List<PlayedByTake> playedByTake,
  }) async {
    duranteOVeredito?.call();
    final refusal = failFinishWith;
    if (refusal != null) throw refusal;
    playedByTakeSent.add([for (final parte in playedByTake) parte.toJson()]);
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
  Future<void> rememberDevice(String deviceId) async => _keep(deviceId: deviceId);

  @override
  Future<void> rememberTeam(TeamLink team) async => _keep(team: team);

  @override
  Future<void> rememberCredential(String credential) async =>
      _keep(credential: credential);

  @override
  Future<void> forgetTheLink() async => remembered = const RememberedLink();

  /// One place where a write keeps what it did not touch.
  ///
  /// Spelled out at each writer, the three halves were three chances to drop one of the
  /// other two — and a double that forgets a half the real ledger keeps is a double that
  /// reads green over a tablet which has lost its device id.
  void _keep({String? deviceId, TeamLink? team, String? credential}) =>
      remembered = RememberedLink(
        deviceId: deviceId ?? remembered.deviceId,
        team: team ?? remembered.team,
        credential: credential ?? remembered.credential,
      );
}

/// A vault kept in a field, for a test that needs to see or seed a credential without a
/// Keychain under it.
///
/// [unavailable] and [keepUnavailable] simulate the Keychain refusing to answer before
/// first unlock — the former for every call, the latter for `keep` alone, since a read
/// can succeed (confirmed empty) while a write to the same item still cannot.
class FakeCredentialVault implements CredentialVault {
  String? _credential;
  bool unavailable = false;
  bool keepUnavailable = false;

  @override
  Future<String?> read() async {
    if (unavailable) throw const VaultUnavailable();
    return _credential;
  }

  @override
  Future<void> keep(String credential) async {
    if (unavailable || keepUnavailable) throw const VaultUnavailable();
    _credential = credential;
  }

  @override
  Future<void> forget() async {
    if (unavailable) throw const VaultUnavailable();
    _credential = null;
  }
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

  /// Whether the room has stopped naming what it stored: the take is kept and sent,
  /// and the name that should come back for it never does.
  bool forgetsNames = false;

  @override
  Future<String?> takeIdOf(
    String kind, {
    required String sessionId,
    required String scope,
  }) async {
    if (forgetsNames) return null;
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

  /// A load that never settles, for the line the player never manages to open.
  bool neverLoads = false;

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) =>
      neverLoads ? Completer<Duration?>().future : Future.value(lineLength);

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

  /// A stop that never settles, for the player that wedges on the way out.
  bool neverStops = false;

  @override
  Future<void> stop() {
    if (neverStops) return Completer<void>().future;
    _playing = false;
    _quiet();
    return Future.value();
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
