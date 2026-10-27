import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../domain/accidental_tap.dart';
import '../domain/approval_answer.dart';
import '../domain/bt_finding.dart';
import '../domain/capture_guard.dart';
import '../domain/channel.dart';
import '../domain/escuta_das_partes.dart';
import '../domain/external_check.dart';
import '../domain/grain.dart';
import '../domain/facilitator_script.dart';
import '../domain/failure_policy.dart';
import '../domain/kept_take.dart';
import '../domain/left_entry.dart';
import '../domain/passagem.dart';
import '../domain/pausa.dart';
import '../domain/coverage.dart';
import '../domain/coverage_event.dart';
import '../domain/cut_point.dart';
import '../domain/ensaio_final_plan.dart';
import '../domain/scene_question.dart';
import '../domain/scene_rehearsal.dart';
import '../domain/session_snapshot.dart';
import '../domain/halt.dart';
import '../domain/hand_reply.dart';
import '../domain/machine.dart';
import '../domain/session_state.dart';
import '../domain/station.dart';
import '../domain/spoken_line.dart';
import '../domain/turn_clock.dart';
import '../domain/turn_result.dart';
import '../domain/ports.dart';
import 'connectivity_service.dart';
import 'device_identity.dart';
import 'effect_runner.dart';
import 'facilitator_voice_service.dart';
import 'failure_log.dart';
import 'hand_inbox_repository.dart';
import 'mic_permission.dart';
import 'playback_repository.dart';
import 'port_adapters.dart';
import 'raised_hand.dart';
import 'recording_repository.dart';
import 'room_answer.dart';
import 'room_client.dart';
import 'room_language_ledger.dart';
import 'room_repository.dart';
import 'take_upload_queue.dart';
import 'work_in_progress.dart';

typedef _Passage = ({String book, String? pericope});

typedef _HeldFrase = ({
  String sessionId,
  String path,
  int startsMs,
  int endsMs,
  String? afterRestart,
  String? replaces,
});

/// The frases a life holds, by rehearsal, and how many posts of each file are in the
/// air: the upload reads the file while it is sent. A file is deleted once, by whichever
/// comes last of its letting go and the landing of its last post.
final class _FraseKeep {
  final Future<void> Function(String path) _delete;
  final Map<String, _HeldFrase> _held = {};
  final Map<String, int> _flying = {};

  _FraseKeep(this._delete);

  _HeldFrase? of(String rehearsalId) => _held[rehearsalId];

  void hold(String rehearsalId, _HeldFrase frase) => _held[rehearsalId] = frase;

  void takeOff(String path) =>
      _flying.update(path, (posts) => posts + 1, ifAbsent: () => 1);

  void land(String path) {
    final posts = (_flying.remove(path) ?? 1) - 1;
    if (posts > 0) _flying[path] = posts;
    _deleteOnceIdle(path);
  }

  /// An answer lets go of the frase it answers, never of another one its rehearsal
  /// holds since; its landing deletes the file.
  void letGo(String rehearsalId, _HeldFrase frase) {
    if (_held[rehearsalId] == frase) _held.remove(rehearsalId);
  }

  void letGoOf(String rehearsalId) {
    if (_held.remove(rehearsalId) case final frase?) {
      _deleteOnceIdle(frase.path);
    }
  }

  void letGoOfTheSession(String? sessionId) {
    for (final MapEntry(key: rehearsalId, value: frase) in [..._held.entries]) {
      if (frase.sessionId == sessionId) letGoOf(rehearsalId);
    }
  }

  void letGoOfAll() {
    for (final rehearsalId in [..._held.keys]) {
      letGoOf(rehearsalId);
    }
  }

  void _deleteOnceIdle(String path) {
    if (_flying.containsKey(path) ||
        _held.values.any((frase) => frase.path == path)) {
      return;
    }
    unawaited(_delete(path));
  }
}

/// The launch sweep of the recordings a killed app left on the tablet runs once per
/// process: a life rebuilt after a revocation must not delete a file another
/// continuation still holds.
bool _theRecordingsLeftBehindWereSwept = false;

final roomPollDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

final roomInboxWatchProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

final watchesWithoutAHaltProvider = Provider<bool>((ref) => true);

/// Reads a scene take's loudness off the UI thread: the whole file is walked, and a
/// take may be as large as the room keeps.
final sceneEnvelopeReaderProvider =
    Provider<Future<Envelope?> Function(String path)>(
      (ref) =>
          (path) => Isolate.run(() => _theLoudnessOf(path)),
    );

Envelope? _theLoudnessOf(String path) {
  try {
    return envelopeOf(File(path).readAsBytesSync());
  } on FileSystemException {
    return null;
  }
}

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

const _sendsWhileInFlight = 3;

const _takeHead = 64 * 1024;

/// How many times in a row the room may answer broken while resuming a stored session
/// before the id is dropped, the way a 404 drops it.
const _resumeFailuresBeforeForgetting = 2;

const _gestureChain = #gestureChain;

const _umInstanteOuvido = Duration(milliseconds: 400);

/// How long her «a tradução do ensaio da cena foi para a voz» stays before the scene
/// screen closes, as on hers (REH_SENT_MS).
const _theSceneStaysAfterItWent = Duration(milliseconds: 1400);

/// The parts of the rehearsal the room could hand back, whether that was all of them, the
/// pass the room holds for each part number, and the whole set aside that only the room
/// holds.
typedef _PartesDaSala = ({
  List<KeptTake> partes,
  bool inteiro,
  Map<int, int> passadas,
  Set<String> deLado,
});

/// The room's current parts read against the files the tablet holds: each current part,
/// the whole set aside that only the room holds, and the take ids still to come down.
typedef _AListagem = ({
  List<KeptTake> partes,
  Set<String> deLado,
  Set<String> aBuscar,
});

/// What a reopening found where the team left off.
enum _Resume {
  /// The station they left, standing again, with the rehearsal under it.
  landed,

  /// The room no longer has one of the parts: the Ensaio stands again with that scene's row
  /// not recorded and every other row holding its own part.
  landedShort,

  /// Nothing behind this passage to come back to: it opens at the conversa.
  nothingToRestore,

  /// The row held no parts, and the session read it asked landed the team on the approved
  /// draft (ADR 0106).
  onTheApprovedDraft,

  /// The room could not hand the rehearsal back: the team is back on the Choice and the
  /// resume point is left exactly as it was, so the next opening tries again.
  failed,

  /// The room no longer holds the session the row remembers.
  gone,

  /// Nobody is waiting for this answer any more — the team left the passage, or the
  /// container went. It is not a reading of what the room holds and must not be read as
  /// one.
  abandoned,
}

final busyStateCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 330),
);

final lookAgainIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
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

final sentenceGraceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

final playbackCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 6),
);

/// The tap boundary the conversa recorder is held to: a take under 700 ms or 800 bytes
/// never becomes a question for the room.
final captureGuardProvider = Provider<CaptureGuard>(
  (ref) => const CaptureGuard(),
);

final roomLanguageProvider = NotifierProvider<RoomLanguage, String>(
  RoomLanguage.new,
);

class RoomLanguage extends Notifier<String> {
  @override
  String build() {
    final chosen = ref.read(roomLanguageLedgerProvider).chosen;
    return languages.contains(chosen) ? chosen! : floorLanguage;
  }

  String get next =>
      languages[(languages.indexOf(state) + 1) % languages.length];

  bool choose(String language) {
    if (!languages.contains(language) || language == state) return false;
    state = language;
    unawaited(
      ref.read(roomLanguageLedgerProvider).choose(language).catchError((_) {}),
    );
    return true;
  }
}

final fimLingerProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 14),
);

/// The room's refusals of a moved pause, each with her line for why.
const _aMoveRefused = {
  RefusalCode.pauseOnlyOnTheLastFrase: SceneLine.pauseOnlyOnTheLast,
  RefusalCode.pausePastTheEnd: SceneLine.pausePastTheEnd,
  RefusalCode.pauseCannotStandThere: SceneLine.pauseCannotStandThere,
};

final restartWakeProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 600),
);

final restartLapseProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 6),
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
  late Map<String, Timer> _timers;
  late int _readsSent;
  late int _readsApplied;
  late int _stretchesAt;
  late Map<String, Set<String>> _perdidasNoTrecho;
  late Map<String, int> _resumeFailures;

  /// The pass the room holds for each part number, kept only while the rehearsal stands
  /// short of a part the room no longer has, so a part recorded there goes up above the
  /// room's own pass for its number and is the current one on the server.
  late Map<int, int>? _passadasDaSala;
  late Set<String> _goneSessions;

  /// The fetch of the parts on their way, which belongs to the passage it started in.
  late Completer<void>? _partesDescendo;

  /// Whether the Session read of this opening has said where the team stands, which a part
  /// the room lost waits for before it leaves the Rehearsal.
  late bool _aLeituraDecidiu;

  /// The station this opening last wrote in the Resume point, so the parts coming down
  /// never write back a station the team has left.
  late Station? _aLinhaDiz;

  /// When and in what language the session now open was created, so a row rewritten by
  /// a later stage advance carries them instead of going blank the moment the team leaves
  /// the conversa. A resume judges by the language; the date is the record of when the
  /// session was born, and nothing decides by it (ADR 0031).
  late DateTime? _sessionSavedAt;
  late String? _sessionLanguage;
  late CurrentSession? _landingOn;

  /// What plays the reply of the turn the machine holds in flight, and the gestures that
  /// wait on it, until the look the machine asks for comes back (ENG-1444 moves it).
  late Map<Turn, _AwaitedReply> _awaitedReplies;
  late Map<String, String> _stretchKeys;
  late bool _personAsked;
  late int _lastAcknowledgement;
  final _random = Random();
  late DateTime? _listeningSince;
  late bool _recordingStarting;

  /// The attempt of a «Novo ouvinte» no answer has landed for, with the version it asks
  /// of: kept across a way back and a way in, so a lost answer never mints a second
  /// listener.
  late ({String sessionId, int version, String attempt})? _listenerAttempt;

  /// Whether one of her lines for the listener is said or waits to be: a line still in the
  /// queue when the room is back is said then, never asked again.
  late bool _listenerLineAwaited;
  late _Passage? _emCurso;
  Trecho? get _trechoTraduzidoDeNovo => state.btTrechoTraduzidoDeNovo;
  set _trechoTraduzidoDeNovo(Trecho? trecho) => state = trecho == null
      ? state.copyWith(clearTrechoTraduzidoDeNovo: true)
      : state.copyWith(btTrechoTraduzidoDeNovo: trecho);
  late BtPhase? _faseAntesDeTraduzirDeNovo;

  late Set<String> _traducoesGuardadas;

  /// The outbox row a guarded translation landed on, by the path it was guarded for.
  ///
  /// Populated once `_guard` has actually enqueued the file, so a discard that races
  /// ahead of that enqueue finds nothing to withdraw — the same window `_semNome`
  /// already lives with for the rehearsal's own rows.
  late Map<String, PendingTake> _traducaoNaFila;

  late Map<MicOwner, int> _captureFails;

  /// Whether the part currently chosen has ever actually gone in the air.
  ///
  /// False only between the entry picking a part and `_tocarParteDaRetro` landing it —
  /// the one window nothing else in state tells apart from a part a hold left silent
  /// partway through.
  late bool _parteJaTocou;

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

  /// The part in the air is one the room named — by a refusal, unheard or untold, or as
  /// unheard after a part was recorded again — and hearing the last of them to its end
  /// hands the finish back.
  ///
  /// The finish was already the team's — it is how the refusal was asked for — and the
  /// refusal only takes it away for the length of these parts. Without this, a refusal
  /// naming any part but the last made the team cross and listen through everything after
  /// it to get the press back, which is hearing the story again: the very thing the jump
  /// over the ground already told exists to spare them.
  late _OQueFaltaOuvir? _oQueFaltaOuvir;

  /// The parts the First listen put in the air, so a listen whose last report found no
  /// answer plays them again.
  late List<int> _partesDaEscuta;

  /// How long each part of the rehearsal turned out to be, by the file the part is kept
  /// as and never by where the part sits in the row.
  ///
  /// A mend hands a part a new file, and a length written down under the old one's place
  /// would outlive it. Keyed by the file, a swapped part needs only its own measurement,
  /// and the listening ledger — keyed by the file too — cannot disagree with the ruler
  /// about which recording a length belongs to.
  late Map<String, int> _tamanhoDaParteMs;
  late Map<String, Envelope?> _envelopes;
  late EscutaDasPartes _escuta;
  late int _desdeMs;

  /// The opening turn this instance is asking for, minted once and carried across every
  /// retry of it — a resend under a fresh id is a fresh id the server has never seen, so
  /// it runs the whole pipeline again instead of answering with what it already produced.
  late String? _openTurnId;
  late bool _openingOwed;
  late TurnClock? _pendingClock;
  late TurnClock? _coverageClock;

  late String? _pendingTakePath;
  late StreamSubscription<void> _outboxFalls;
  late StreamSubscription<String> _outboxGone;
  late EffectRunner _runner;
  late RaisedHand _hand;

  /// The frases this life holds and the posts of their files in the air. A post keeps
  /// the one of the life that sent it, whatever life is current when it lands.
  late _FraseKeep _frases;
  late StreamSubscription<CoverageEvent>? _coverageWatch;
  late String? _coverageSessionId;
  late String? _awaitingCoverageTurnId;
  late String? _resolvedCoverageTurnId;
  late String? _coverageReopenedForTurnId;
  late Coverage? _heldCoverage;
  late TurnClock? _heldCoverageClock;
  int _lines = 0;
  int _gestures = 0;
  late Map<int, int> _handedOff;
  late Set<int> _waitingOnTheGeneration;
  late Map<Line, Completer<Said>> _sayings;
  late List<Completer<MicOutcome>> _closings;
  late VoidCallback? _onPlaybackComplete;
  late VoidCallback? _onPlaybackFailed;

  FacilitatorVoiceService get _voice => ref.read(facilitatorVoiceProvider);
  SoundPort get _sound => ref.read(soundPortProvider);
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);
  PlaybackRepository get _playback => ref.read(playbackRepositoryProvider);
  RoomRepository get _room => ref.read(roomRepositoryProvider);
  TakeUploadQueue get _takes => ref.read(takeUploadQueueProvider);
  ConnectivityService get _network => ref.read(connectivityServiceProvider);
  WorkInProgress get _emAberto => ref.read(workInProgressProvider);
  StorePort get _store => ref.read(storePortProvider);
  CaptureGuard get _captureGuard => ref.read(captureGuardProvider);

  String get _lingua => ref.read(roomLanguageProvider);

  String get _inTheSessionsLanguage => switch (state.station) {
    Menu() => _lingua,
    Panorama() => state.machine.panorama?.language ?? _lingua,
    _ => _sessionLanguage ?? _lingua,
  };

  /// The room is gone and its providers with it.
  ///
  /// Half this class is fire-and-forget: `_guard` queues a take and counts what is left
  /// long after the gesture that started it returned. Reading a provider once the
  /// container is disposed throws, and the throw lands in no one's `catch` — it showed up
  /// as two tests that failed only on a slower machine, which is the same thing happening
  /// where nobody was looking.
  late bool _gone;

  int _highestGeneration = 0;
  int _firstGeneration = 0;

  /// The outside listener this tablet has in progress, as its Resume point names them.
  late ({int version, int number})? _listenerInProgress;

  void _aNewLife() {
    _timers = {};
    _armHandedOver = null;
    _readsSent = 0;
    _readsApplied = 0;
    _stretchesAt = 0;
    _perdidasNoTrecho = {};
    _resumeFailures = {};
    _passadasDaSala = null;
    _goneSessions = {};
    _partesDescendo = null;
    _aLeituraDecidiu = false;
    _aLinhaDiz = null;
    _sessionSavedAt = null;
    _sessionLanguage = null;
    _landingOn = null;
    _awaitedReplies = {};
    _stretchKeys = {};
    _personAsked = false;
    _lastAcknowledgement = 0;
    _listeningSince = null;
    _recordingStarting = false;
    _listenerAttempt = null;
    _listenerLineAwaited = false;
    _emCurso = null;
    _listenerInProgress = null;
    _faseAntesDeTraduzirDeNovo = null;
    _traducoesGuardadas = {};
    _traducaoNaFila = {};
    _captureFails = {};
    _parteJaTocou = false;
    _oQueFaltaOuvir = null;
    _partesDaEscuta = const [];
    _tamanhoDaParteMs = {};
    _envelopes = {};
    _frases = _FraseKeep(_recorder.delete);
    _escuta = EscutaDasPartes();
    _desdeMs = 0;
    _openTurnId = null;
    _openingOwed = false;
    _pendingClock = null;
    _coverageClock = null;
    _pendingTakePath = null;
    _outboxFalls = _apart(
      () => ref
          .read(takeUploadQueueProvider)
          .fallsOnTheNetwork
          .listen((_) => _theNetworkFailedAt(Door.outbox)),
    );
    _outboxGone = _apart(
      () => ref
          .read(takeUploadQueueProvider)
          .sessionsGone
          .listen(_theSessionIsGone),
    );
    _coverageWatch = null;
    _coverageSessionId = null;
    _awaitingCoverageTurnId = null;
    _resolvedCoverageTurnId = null;
    _coverageReopenedForTurnId = null;
    _heldCoverage = null;
    _heldCoverageClock = null;
    _handedOff = {};
    _waitingOnTheGeneration = {};
    _sayings = {};
    _closings = [];
    _onPlaybackComplete = null;
    _onPlaybackFailed = null;
    _launching = null;
    _launched = false;
    _hand = RaisedHand(
      host: _HandHost(this),
      inbox: () => ref.read(handInboxRepositoryProvider),
      recorder: () => _recorder,
    );
    _semNome = {};
    _rowsOfThisVisit = {};
    _plansOpened = 0;
    _notQueued = {};
    _keepsInFlight = {};
    _lengths = {};
    _newestCount = 0;
    _fraseNaFila = null;
    _regravacoes = 0;
    _regravouNestaVisita = false;
  }

  @override
  SalaSessionState build() {
    _aNewLife();
    _gone = false;
    final frases = _frases;
    if (!_theRecordingsLeftBehindWereSwept) {
      _theRecordingsLeftBehindWereSwept = true;
      unawaited(_recorder.sweepTheRecordingsLeftBehind());
    }
    listenSelf((_, now) {
      if (now.anArmedKnotLapsed) state = now.copyWith(noteMode: false);
      _highestGeneration = max(_highestGeneration, now.machine.generation);
    });
    _runner = EffectRunner(
      room: ref.read(roomPortProvider),
      sound: ref.read(soundPortProvider),
      recorder: ref.read(recorderPortProvider),
      store: ref.read(storePortProvider),
      host: _NotifierHost(this),
      watchPeriod: () => ref.read(roomPollDelayProvider),
      retryDelay: _onTheLadder,
      partCeiling: () => ref.read(playbackCeilingProvider),
      clipGrace: () => ref.read(clipGraceProvider),
      lookAgainAfter: () => ref.read(lookAgainIntervalProvider),
      generation: () => _generation,
    );
    ref.onDispose(() {
      _firstGeneration = _highestGeneration + 1;
      _gone = true;
      frases.letGoOfAll();
      _cancelTimers();
      _runner.run(const [DiscardTheMic(), StopTheSound()]);
      _runner.dispose();
      unawaited(_outboxFalls.cancel());
      unawaited(_outboxGone.cancel());
      unawaited(_coverageWatch?.cancel());
    });
    return SalaSessionState(machine: Machine(generation: _firstGeneration));
  }

  Future<bool> _sayALine(
    LineKind kind, {
    String? url,
    String? asset,
    FixedLine? fixedLine,
    void Function()? onSoundStart,
  }) => _sayTheLine(
    kind,
    url: url,
    asset: asset,
    fixedLine: fixedLine,
    onSoundStart: onSoundStart,
  ).then((said) => said.heard);

  Future<Said> _sayTheLine(
    LineKind kind, {
    String? url,
    String? asset,
    FixedLine? fixedLine,
    void Function()? onSoundStart,
    Source? source,
  }) {
    final line = _newLine(
      kind,
      url: url,
      asset: asset,
      fixedLine: fixedLine,
      onSoundStart: onSoundStart,
      source: source,
    );
    final ended = Completer<Said>();
    _sayings[line] = ended;
    _dispatch(LineArrived(line, by: _chain, generation: _generation));
    return ended.future;
  }

  Line _newLine(
    LineKind kind, {
    String? url,
    String? asset,
    FixedLine? fixedLine,
    void Function()? onSoundStart,
    Source? source,
  }) => Line(
    kind,
    ++_lines,
    source:
        source ??
        switch (kind) {
          LineKind.guide || LineKind.approved => Source.guide,
          _ => Source.aside(kind.name),
        },
    url: url,
    asset: asset,
    fixedLine: fixedLine,
    onSoundStart: onSoundStart,
  );

  void _theLineEnded(LineOutcome outcome) {
    final ended = _sayings.remove(outcome.line);
    if (ended == null) return;
    final because = outcome.because;
    if (because != null) return ended.completeError(because);
    ended.complete(outcome.said);
  }

  void _after(String key, Duration delay, VoidCallback fn) {
    _timers[key]?.cancel();
    final generation = _waitOnTheGeneration;
    _timers[key] = _apart(
      () => Timer(delay, () {
        if (!_abandoned(generation)) fn();
      }),
    );
  }

  void _cancelTimers() {
    if (!_gone) {
      state = state.copyWith(
        machine: moveTheGeneration(state.machine),
        clearArmedTap: true,
      );
    }
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _endTheGesturesAbandoned();
  }

  int get _waitOnTheGeneration {
    _waitingOnTheGeneration.addAll(_chain);
    return _generation;
  }

  int get _generation => state.machine.generation;

  bool _abandoned(int generation) => _gone || generation != _generation;

  int? get _thisLife => _gone ? null : _firstGeneration;

  bool _endedSince(int? life) => _gone || life != _firstGeneration;

  void _endTheGesturesAbandoned() {
    final waiting = _waitingOnTheGeneration;
    _waitingOnTheGeneration = {};
    _endTheGesturesOf(waiting);
  }

  void _endTheGesturesOf(Set<int> waiting) {
    final abandoned = waiting.difference(_chain.toSet());
    if (_gone) return;
    for (final gesture in abandoned.intersection(state.machine.onTheirWay)) {
      _endTheGesture(gesture, _thisLife);
    }
  }

  void _leaveTheStepFor(Station next) {
    if (state.station == next) return;
    if (state.station is Retro) {
      _relatarAEscuta();
    }
    _dispatch(const StepLeft());
    state = state.copyWith(awaitingTheGuide: false, endOfThePassage: false);
  }

  /// Dispatches an event that may move the Station. A gesture that waited on the
  /// generation it moves from is ended; one its hand-offs begin on the new one waits on.
  void _arriveAt(MachineEvent arrival) {
    final generation = _generation;
    final waiting = _waitingOnTheGeneration;
    _waitingOnTheGeneration = {};
    try {
      _dispatch(arrival);
    } finally {
      if (_generation != generation) {
        _endTheGesturesOf(waiting);
      } else {
        _waitingOnTheGeneration.addAll(waiting);
      }
    }
  }

  void _clearAll() {
    _cancelTimers();
    _awaitedReplies.clear();
    _openTurnId = null;
    _openingOwed = false;
    _heldCoverage = null;
    _heldCoverageClock = null;
    state = state.copyWith(
      clearLastSpoken: true,
      roomSaysItAgain: false,
      clearParteARegravar: true,
      clearHomeSheet: true,
      clearSwapLine: true,
      clearSwapping: true,
    );
    _silenceTheRoom();
    _dispatch(const MicDiscarded());
  }

  void _gesture(void Function() act) {
    final gesture = _startAGesture();
    _theDiskWordGoes();
    try {
      runZoned(
        act,
        zoneValues: {
          _gestureChain: [..._chain, gesture],
        },
      );
    } finally {
      _theSyncPartEnded(gesture);
    }
  }

  void _handOff(Future<void> next) {
    final reported = _reportingAnError(next);
    final gesture = _chain.lastOrNull;
    if (gesture == null) return unawaited(reported);
    _handedOff.update(gesture, (pending) => pending + 1, ifAbsent: () => 1);
    final life = _thisLife;
    unawaited(
      reported.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        final pending = (_handedOff[gesture] ?? 1) - 1;
        if (pending > 0) {
          _handedOff[gesture] = pending;
          return;
        }
        _handedOff.remove(gesture);
        _endTheGesture(gesture, life);
      }),
    );
  }

  Future<void> _gestureThen(Future<void> Function() act) {
    final gesture = _startAGesture();
    final life = _thisLife;
    final next = _reportingAnError(
      runZoned(
        act,
        zoneValues: {
          _gestureChain: [..._chain, gesture],
        },
      ),
    );
    unawaited(
      next
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() => _endTheGesture(gesture, life)),
    );
    return next;
  }

  Future<void> _reportingAnError(Future<void> next) {
    final life = _thisLife;
    return next.catchError(
      (Object error, StackTrace stack) =>
          _theBuildCannotReachTheRoom(error, stack, life),
      test: (error) => error is Error,
    );
  }

  int _startAGesture() {
    final gesture = ++_gestures;
    _armHandedOver = state.armedTap;
    _dispatch(GestureStarted(gesture));
    if (_armHandedOver != null) state = state.copyWith(clearArmedTap: true);
    return gesture;
  }

  late ArmedTap? _armHandedOver;

  void _armedTap(
    String control, {
    required bool needs,
    required void Function() then,
  }) {
    final armed = _armHandedOver;
    if (!needs) return then();
    if (armed?.control != control) {
      state = state.copyWith(
        armedTap: ArmedTap(control, BtRecomeco.armado),
        clearAviso: true,
      );
      _after('armedTapWakes', ref.read(restartWakeProvider), () {
        if (state.armedTap?.control != control) return;
        state = state.copyWith(armedTap: ArmedTap(control, BtRecomeco.pronto));
      });
      _after('armedTapLapses', ref.read(restartLapseProvider), () {
        if (state.armedTap?.control != control) return;
        state = state.copyWith(clearArmedTap: true);
      });
      return;
    }
    if (armed?.phase == BtRecomeco.armado) {
      state = state.copyWith(armedTap: armed);
      return;
    }
    _timers.remove('armedTapLapses')?.cancel();
    then();
  }

  void _theSyncPartEnded(int gesture) {
    if (!_handedOff.containsKey(gesture)) _endTheGesture(gesture, _thisLife);
  }

  void _endTheGesture(int gesture, int? life) {
    if (!_endedSince(life)) _dispatch(GestureEnded(gesture));
  }

  T _apart<T>(T Function() flow) =>
      runZoned(flow, zoneValues: {_gestureChain: const <int>[]});

  Machine get _gesturesOnTheirWay => Machine(
    onTheirWay: state.machine.onTheirWay.intersection(_chain.toSet()),
    generation: state.machine.generation,
    station: state.machine.station,
  );

  List<int> get _chain => Zone.current[_gestureChain] as List<int>? ?? const [];

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
  /// circle's three taps and telling a stretch again. A hold silences the rehearsal just
  /// as well and is what keeps the clip open: stopped, the room loses the length that the
  /// listening ceiling and the end of the part are both measured against.
  ///
  /// It never cancels the room's timers, never moves the generation and never touches the
  /// recorder: those belong to [_clearAll], which leaves a passage rather than moving
  /// inside one.
  void _silenceTheRoom({bool holdTheClip = false}) {
    _quietTheRoom(holdTheClip: holdTheClip);
    _dispatch(GestureSilenced(keepingTheHold: holdTheClip));
    state = state.copyWith(clearContaEscolhida: true);
  }

  void _quietTheRoom({bool holdTheClip = false}) {
    _anotarOQueFoiOuvido();
    if (holdTheClip) {
      _holdClip();
    } else {
      _onPlaybackComplete = null;
      _onPlaybackFailed = null;
      _timers.remove('cursor')?.cancel();
    }
  }

  String _stamp() => clock.now().millisecondsSinceEpoch.toString();

  void _play(
    Sound sound, {
    VoidCallback? onComplete,
    VoidCallback? onFailed,
    Paused? beneath,
  }) => _playAll(
    [sound],
    onComplete: onComplete,
    onFailed: onFailed,
    beneath: beneath,
  );

  void _playAll(
    List<Sound> sounds, {
    VoidCallback? onComplete,
    VoidCallback? onFailed,
    Paused? beneath,
  }) {
    _onPlaybackComplete = onComplete;
    _onPlaybackFailed = onFailed;
    _dispatch(BeadTapped(sounds, beneath: beneath));
  }

  void _thePartFailed() {
    _onPlaybackComplete = null;
    final undo = _onPlaybackFailed;
    _onPlaybackFailed = null;
    if (state.channel is Playing) undo?.call();
  }

  void _thePartEnded() {
    _escutarOFimNoEnsaio();
    final next = switch (state.channel) {
      Playing(:final next) || Paused(:final next) => next,
      _ => null,
    };
    if (next == null || next.isNotEmpty) return;
    final callback = _onPlaybackComplete;
    _onPlaybackComplete = null;
    _onPlaybackFailed = null;
    callback?.call();
  }

  void _escutarNoEnsaio(Machine antes, Machine depois) {
    final soava = _aParteDoEnsaioQueSoa(antes);
    final soa = _aParteDoEnsaioQueSoa(depois);
    if (soava == soa) return;
    if (soava != null) _fecharNoEnsaio(soava, _ondeOSomEstaNoArquivo(soava));
    if (soa != null) {
      final de = switch (antes.channel) {
        Paused(:final what) when what == soa => _ondeOSomEstaNoArquivo(soa),
        _ => soa.from,
      };
      _escuta.abrir(soa.path, de.inMilliseconds);
    }
  }

  PartSound? _aParteDoEnsaioQueSoa(Machine machine) =>
      switch (machine.channel) {
        PartPlaying(opened: true, :final part)
            when machine.station is Ensaio &&
                state.partes.any((parte) => parte.path == part.path) =>
          part,
        _ => null,
      };

  Duration _ondeOSomEstaNoArquivo(PartSound som) =>
      som.to == null ? _playback.position : som.from + _playback.position;

  void _escutarOFimNoEnsaio() {
    final soa = _aParteDoEnsaioQueSoa(state.machine);
    if (soa == null) return;
    final ate = soa.to ?? _playback.playingLength;
    if (ate == null) return;
    _fecharNoEnsaio(soa, ate);
    _relatarAEscuta();
  }

  void _fecharNoEnsaio(PartSound som, Duration ate) {
    final tamanho = som.to == null ? _playback.playingLength : null;
    final medido = tamanho?.inMilliseconds ?? 0;
    if (medido > 0) _escuta.medida(som.path, medido);
    _escuta.fechar(som.path, ate.inMilliseconds);
  }

  void _cortarAEscutaNoAr() {
    if (state.station is Retro) {
      if (state.channel case PartPlaying(opened: true)) {
        final arquivo = _parteNoAr?.path;
        _anotarOQueFoiOuvido();
        if (arquivo != null) {
          _escuta.abrir(arquivo, _playback.position.inMilliseconds);
        }
      }
      return;
    }
    final soa = _aParteDoEnsaioQueSoa(state.machine);
    if (soa == null) return;
    final ate = _ondeOSomEstaNoArquivo(soa);
    _fecharNoEnsaio(soa, ate);
    _escuta.abrir(soa.path, ate.inMilliseconds);
  }

  void _relatarAEscuta() {
    final sessionId = state.sessionId;
    final relato = _escuta.relato(state.partes);
    if (sessionId == null || relato.isEmpty) return;
    unawaited(_room.reportTheListening(sessionId, playedByTake: relato));
  }

  void _theRunHeard() {
    if (state.btClipRodando) _armCursorDeadline();
  }

  void _thePartOpened() {
    _medirAParteNoAr();
    if (state.btClipRodando) _armCursorDeadline();
  }

  void _holdClip() {
    if (state.channel is Playing) _dispatch(const PauseTapped());
  }

  void _letTheClipRun() {
    if (state.channel case Paused() || GuideSpeaking(held: Paused())) {
      _dispatch(const PauseTapped());
    }
  }

  /// What a gesture waits on after a sound: the line it said, and the part that opened.
  void _followTheSound(Machine before, Machine after) {
    final outcome = after.lastLine;
    if (outcome != null && !identical(outcome, before.lastLine)) {
      _theLineEnded(outcome);
    }
    if ((before.channel, after.channel) case (
      Playing(opened: false, :final sound),
      Playing(opened: true, sound: final opened),
    ) when opened == sound) {
      _thePartOpened();
    }
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
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    await (fixedLine.isEmpty
        ? _voice.ready(url)
        : _voice.readyFixedLine(fixedLine, _inTheSessionsLanguage));
  }

  /// Say a line, and remember it as the one "ouvir de novo" gives back, whether it was
  /// said whole or cut by the team.
  ///
  /// [remember] is false for a canned line. A fail-safe is what the room says when it could
  /// not compose an answer, and letting it take the place of the last real line meant the
  /// replay handed a team "vamos parar um instante aqui" instead of the scene they were
  /// asking to hear again. The room repeats what it actually told them.
  Future<Said> _speak(
    String url,
    String fixedLine, {
    bool remember = true,
    void Function()? onSoundStart,
    String? checkAt,
  }) async {
    final generation = _waitOnTheGeneration;
    final room = _room;
    final session = state.sessionId;
    final said = await _sayTheLine(
      LineKind.guide,
      url: fixedLine.isEmpty ? url : null,
      fixedLine: fixedLine.isEmpty
          ? null
          : (name: fixedLine, language: _inTheSessionsLanguage),
      onSoundStart: onSoundStart,
    );
    if (said.heard && remember && !_abandoned(generation)) {
      state = state.copyWith(
        lastSpoken: SpokenLine(
          url: url,
          fixedLine: fixedLine,
          checkAt: checkAt,
        ),
      );
    }
    if ((said, checkAt, session) case (
      Said.said,
      final checkAt?,
      final sessionId?,
    ) when !_abandoned(generation)) {
      unawaited(room.reportTheVerdictHeard(sessionId, checkAt));
    }
    return said;
  }

  Future<void> hearAgain() async {
    if (!state.canHearAgain) return;
    if (state.channel is PartPlaying) _silenceTheRoom();
    final line = state.lastSpoken;
    if (line != null) return _repeatLastSpoken(line);
    await _askTheRoomToSayItAgain();
  }

  /// A session the team walked back into holds no line of its own here, so the room is
  /// asked for its last one, under a turn id of its own: nothing is written, and a lost or
  /// slow answer is looked at once (ADR 0097).
  Future<void> _askTheRoomToSayItAgain() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final generation = _waitOnTheGeneration;
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    final turnId = _stamp();
    await _sendATurn(
      Turn(sessionId, turnId),
      generation,
      () => _room.openSession(sessionId, turnId: turnId),
      keeps: const TheLineSaidAgain(),
      play: (line) async {
        if (_abandoned(generation)) return;
        await _readyToSpeak(line.audioUrl, line.fixedLine);
        if (_abandoned(generation)) return;
        _watchBusyState();
        final played = await _speak(
          line.audioUrl,
          line.fixedLine,
          remember: !line.usedFailSafe,
        );
        if (_abandoned(generation)) return;
        if (!played.heard) {
          return _registerUnplayableTurn(leavesTeamTalk: false);
        }
        state = state.copyWith(awaitingTheGuide: false);
      },
      failed: (failure) {
        if (_abandoned(generation)) return;
        _decideTheFailure(failure);
      },
    );
  }

  Future<void> _repeatLastSpoken(SpokenLine line) async {
    final generation = _waitOnTheGeneration;
    await _readyToRepeat(line.url, line.fixedLine);
    if (_abandoned(generation)) return;
    _watchBusyState();
    try {
      final played = await _speak(
        line.url,
        line.fixedLine,
        checkAt: line.checkAt,
      );
      if (_abandoned(generation)) return;
      if (!played.heard) return _registerUnplayableTurn(leavesTeamTalk: false);
      state = state.copyWith(awaitingTheGuide: false);
      _landTheHeldCoverage();
    } on RoomFailure catch (failure) {
      if (_abandoned(generation)) return;
      _decideTheFailure(failure);
    }
  }

  Future<void> _voiceTurn(
    TurnResult turn,
    int generation, {
    TurnClock? clock,
    void Function()? onSoundStart,
  }) async {
    if (_abandoned(generation)) return;
    _paintCoverage(turn.coverage);
    state = state.copyWith(
      moment: turn.moment,
      clearMoment: turn.moment == null,
    );
    clock?.mark('answer');
    _awaitCoverageSettle(turn, clock: clock);
    _scheduleInboxPoll();
    await _readyToSpeak(turn.audioUrl, turn.fixedLine);
    if (_abandoned(generation)) return;
    clock?.mark('clip');
    if (_answeredWithNothingToPlay(turn)) return;
    _watchBusyState();
    final played = await _speak(
      turn.audioUrl,
      turn.fixedLine,
      remember: !turn.usedFailSafe,
      onSoundStart: onSoundStart,
    );
    if (_abandoned(generation)) return;
    if (!played.heard) {
      _registerUnplayableTurn();
      return;
    }
    _resumeFailures.clear();
    _openTurnId = null;
    _openingOwed = false;
    state = state.copyWith(
      awaitingTheGuide: false,
      endOfThePassage: turn.done ? true : null,
      peerCue: played == Said.said ? turn.peerCue : null,
    );
    _landTheHeldCoverage();
    _awaitCoverageSettle(turn, clock: clock);
    _scheduleInboxPoll();
  }

  bool _answeredWithNothingToPlay(TurnResult turn) {
    if (turn.audioUrl.isNotEmpty || turn.fixedLine.isNotEmpty) return false;
    _dispatch(decided(const RoomAnsweredWithoutAReply(), _failureContext()));
    _registerUnplayableTurn();
    return true;
  }

  void _registerUnplayableTurn({bool leavesTeamTalk = true}) {
    _openTurnId = null;
    _openingOwed = false;
    state = state.copyWith(
      awaitingTheGuide: false,
      peerCue: leavesTeamTalk ? false : null,
    );
    _landTheHeldCoverage();
  }

  /// The build has no address or no key, so nothing the team does can work.
  ///
  /// Reached before the room opens, because the alternative is discovering it one failed
  /// request at a time — and `Env`'s throw is an `Error`, which the network layer's
  /// catches all miss. That is why this halt never asks: touching `Env` for a device-scoped
  /// ask would throw that same uncatchable `Error`, and this method is itself the only
  /// signal that there is no server to reach.
  void haltForABrokenBuild() => _dispatch(
    decidedOnTheTablet(const TheBuildCannotReachTheRoom(), _failureContext()),
  );

  void _theBuildCannotReachTheRoom(Object error, StackTrace stack, int? life) {
    if (_endedSince(life)) return;
    debugPrint('$error\n$stack');
    haltForABrokenBuild();
  }

  void _logTheGuidesSound(MachineEvent event, Machine before, Machine after) {
    if (event is! PlayerFailed ||
        event.source != Source.guide ||
        identical(before, after) ||
        after.failing != Source.guide) {
      return;
    }
    decidedOnTheTablet(TheSoundFailed(after.failures), _failureContext());
  }

  Kept _whatIsSounding({bool theOpening = true}) {
    if (state.machine.keptInFlight case final TheLineSaidAgain line) {
      return line;
    }
    if (state.station is Retro &&
        (state.channel is Playing || !_parteJaTocou)) {
      return const ThePart();
    }
    if (theOpening && _openingOwed && _openTurnId != null) {
      return const TheOpening();
    }
    return const NothingKept();
  }

  void _dispatch(MachineEvent event) {
    final before = state.machine;
    final (machine, effects) = reduce(before, event);
    final leavesTheScene =
        before.station is SceneRehearsal && machine.station is! SceneRehearsal;
    if (machine.halt is Blocking && before.halt is! Blocking) {
      _anotarOQueFoiOuvido();
    }
    state = state.copyWith(
      machine: machine,
      arrivedAtTheChoice: machine.station is Menu ? null : false,
      scene: leavesTheScene ? const SceneScreen() : null,
      sceneRehearsals: leavesTheScene ? const [] : null,
      clearSceneTurn: leavesTheScene,
      clearArmedTap: machine.generation != before.generation,
    );
    _escutarNoEnsaio(before, machine);
    _runner.run(effects, micWasOpen: before.channel is Microphone);
    _logTheGuidesSound(event, before, machine);
    _followTheSound(before, machine);
    _followTheMicrophone(before, machine);
    _followTheListener(before, machine);
    _stampTheQuestion();
  }

  bool get _watchIsWanted =>
      !((state.halt is NoHalt && !ref.read(watchesWithoutAHaltProvider)) ||
          _sessionId == null);

  String? get _sessionId => state.stationSessionId;

  void _letTheOpeningGo() {
    _openingOwed = false;
    _openTurnId = null;
    _leaveThinking();
    state = state.copyWith(awaitingTheGuide: false, peerCue: false);
  }

  void _silenceTheHaltedRoom() {
    _openTurnId = null;
    _quietTheRoom();
    state = state.copyWith(clearContaEscolhida: true);
    _leaveThinking();
    state = state.copyWith(awaitingTheGuide: false, peerCue: false);
  }

  SentRead _theReadSent() => (order: ++_readsSent, row: state.btTrechos);

  void _theSessionReadHeard(SessionSnapshot snapshot, SentRead sent) {
    _applyTheSessionRead(snapshot, sent.order, rowWhenSent: sent.row);
    _applyWhatOnlyGrows(snapshot);
  }

  void _takeTheStretches(BackTranslationProgress told, int sent) {
    if (state.station is! Retro ||
        state.btPhase == BtPhase.thinking ||
        told.nothingTold) {
      return;
    }
    _stretchesAt = max(_stretchesAt, sent);
    state = state.copyWith(btTrechos: _trechosFrom(told.segments));
  }

  bool _applyWhatOnlyGrows(SessionSnapshot snapshot, {TurnClock? clock}) {
    final advanced =
        state.station is! Panorama &&
        _applyCoverage(snapshot.coverage, clock: clock);
    if (!state.needsPerson &&
        snapshot.done &&
        (state.station is Canvas || state.sceneRehearsalIsOpen)) {
      state = state.copyWith(endOfThePassage: true);
    }
    return advanced;
  }

  void _applyTheSessionRead(
    SessionSnapshot snapshot,
    int sent, {
    List<Trecho>? rowWhenSent,
  }) {
    if (sent <= _readsApplied) return;
    _readsApplied = sent;
    state = state.copyWith(
      keptRetellings: snapshot.keptRetellings,
      toBringBack: snapshot.backTranslation.bringBack,
      btChecked: snapshot.backTranslation.checked,
      btRascunhoAprovado: snapshot.approved,
      clearBtRascunhoAprovado: snapshot.approved == null,
    );
    if (rowWhenSent != null && identical(state.btTrechos, rowWhenSent)) {
      _takeTheStretches(snapshot.backTranslation, sent);
    }
    _dispatch(SessionRead(snapshot, generation: _generation));
  }

  void _stopCallingForAPerson() {
    _personAsked = false;
    _resumeFailures.clear();
  }

  void _theSignCleared() {
    if (_emCurso case final passage?
        when state.sessionId == null && state.station is Canvas) {
      _handOff(_enterThePassage(passage));
    }
    if (state.rodaPorLer) _handOff(abrirEscolha());
  }

  bool get _aPersonIsNeeded => !_gone && state.needsPerson;

  bool get _callIsWanted => _aPersonIsNeeded && !_personAsked;

  void _theCallLanded() => _personAsked = true;

  void _theCallOfAnEarlierSession(String sessionId, RoomResult result) {
    switch (result) {
      case RoomRefused(code: RefusalCode.passageClosed):
        _theSessionIsClosed(sessionId);
      case RoomSessionGone():
        _theSessionIsGone(sessionId);
      case _:
        break;
    }
  }

  void _theSessionIsClosed(String sessionId) {
    if (_gone) return;
    if (sessionId == _sessionId) {
      return _dispatch(ThePassageClosed(generation: _generation));
    }
    _letGoOf(sessionId);
  }

  /// [rule] is [RefusalRule.aSpokenTurn] for a turn the team spoke, which brings the
  /// person sign; any other refusal lets its Step go.
  void _decideTheFailure(
    RoomFailure failure, {
    RefusalRule rule = RefusalRule.letsTheStepGo,
    Door door = Door.step,
  }) {
    _leaveThinking();
    _decideAt(failure, door: door, rule: rule);
  }

  void _decideAt(
    RoomFailure failure, {
    Door door = Door.step,
    RefusalRule rule = RefusalRule.letsTheStepGo,
  }) {
    if (_gone) return;
    _dispatch(decided(failure.result, _failureContext(door: door, rule: rule)));
  }

  FailureContext _failureContext({
    Door door = Door.step,
    RefusalRule rule = RefusalRule.letsTheStepGo,
    Turn? turn,
  }) => FailureContext(
    station: state.station,
    step: switch (state.station) {
      Retro() => state.btPhase,
      _ => null,
    },
    generation: _generation,
    turn: turn,
    rule: rule,
    door: door,
    sounding: _whatIsSounding(),
  );

  void _letTheStepGo() {
    _leaveThinking();
    state = state.copyWith(awaitingTheGuide: false, peerCue: false);
  }

  void _refuseThePassage() => unawaited(abrirEscolha());

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
    if (!state.awaitingTheGuide || state.channel is GuideSpeaking) return;
    if (state.machine.halt is Blocking) return _watchBusyState();
    if (state.machine.look case final look? when look.stillAnswering) {
      return _dispatch(
        LookEmpty(
          look.turn,
          sounding: look.sounding,
          theWaitRanOut: true,
          generation: _generation,
        ),
      );
    }
    final turn = state.machine.inFlight;
    if (turn != null) return _giveUpOnTheTurn(turn, const RoomTimedOut());
    _cancelTimers();
    _leaveThinking();
    _dispatch(decided(const RoomTimedOut(), _failureContext()));
  }

  void _giveUpOnTheTurn(Turn turn, RoomResult result) => _dispatch(
    decided(result, _failureContext(turn: turn, rule: RefusalRule.aSpokenTurn)),
  );

  void _playTheReplyTheLookFound(Turn turn, TurnResult reply) {
    final awaited = _awaitedReplies.remove(turn);
    if (awaited != null) _handOff(awaited.play(reply));
  }

  /// An Opening the room was still answering when the look found it: the team rests on it
  /// unheard, and «Ouvir de novo» says it.
  void _keepTheReplyTheLookFound(Turn turn, TurnResult reply) {
    _awaitedReplies.remove(turn);
    _paintCoverage(reply.coverage);
    _openingOwed = false;
    _openTurnId = null;
    _leaveThinking();
    state = state.copyWith(
      moment: reply.moment,
      clearMoment: reply.moment == null,
      endOfThePassage: reply.done ? true : null,
      lastSpoken: reply.usedFailSafe
          ? null
          : SpokenLine(url: reply.audioUrl, fixedLine: reply.fixedLine),
      roomSaysItAgain: reply.usedFailSafe ? true : null,
      awaitingTheGuide: false,
    );
  }

  void _waitOnTheLookAgain() {
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
  }

  void _letTheLineGo() {
    _leaveThinking();
    state = state.copyWith(awaitingTheGuide: false);
  }

  /// One turn, sent once. A network failure, the client's 305 s give-up included, is
  /// looked at once; any other failure goes to [failed]. An answer to a turn the machine
  /// no longer holds in flight was already given up on, and the look decides it.
  Future<void> _sendATurn(
    Turn turn,
    int generation,
    Future<RoomAnswer<TurnResult>> Function() send, {
    required Future<void> Function(TurnResult reply) play,
    required void Function(RoomFailure failure) failed,
    Kept keeps = const NothingKept(),
  }) async {
    Future<void> heard(TurnResult reply) async {
      try {
        await play(reply);
      } on RoomFailure catch (failure) {
        failed(failure);
      }
    }

    _awaitedReplies
      ..clear()
      ..[turn] = (play: heard, gestures: _chain);
    _dispatch(TurnSent(turn, keeps: keeps));
    final answer = await _theTakeGoes(send);
    if (_abandoned(generation)) return;
    if (answer case NetworkFailed() && final fell) {
      return _giveUpOnTheTurn(turn, fell.result);
    }
    if (state.machine.inFlight != turn) return;
    _awaitedReplies.remove(turn);
    switch (answer) {
      case Answered(value: final reply):
        _dispatch(decided(const RoomAnswered(), _failureContext(turn: turn)));
        await heard(reply);
      case final RoomFailure failure:
        _dispatch(TurnFailed(turn, generation: _generation));
        failed(failure);
    }
  }

  Future<RoomAnswer<TurnResult>> _theTakeGoes(
    Future<RoomAnswer<TurnResult>> Function() send,
  ) async {
    try {
      return await send();
    } on FileSystemException catch (error) {
      return NetworkFailed('$error');
    }
  }

  /// The room gave up on a call it was making, however it came to that.
  ///
  /// This is the seam rather than `_decideTheFailure`, because the watchdog that gives up
  /// on a busy state is not a room failure — it is this tablet deciding the wait is over —
  /// and it is the one give-up that fires while a correction's own call is in the air, with
  /// no refusal to show for it. Both stations do all their waiting in this phase.
  void _leaveThinking() {
    if (state.station is Retro && state.btPhase == BtPhase.thinking) {
      state = state.copyWith(btPhase: BtPhase.playing);
    }
  }

  void _theNetworkFailedAt(Door door) => _theNetworkFailedIn(door, _thisLife);

  void _theNetworkFailedIn(Door door, int? life) {
    if (_endedSince(life)) return;
    _dispatch(decided(const RoomNetworkFailed(), _failureContext(door: door)));
  }

  void _theStepsNetworkFailed() => _theNetworkFailedAt(Door.step);

  Duration _onTheLadder(int step) {
    final ladder = ref.read(roomRetryBackoffProvider);
    return ladder[step < ladder.length ? step : ladder.length - 1];
  }

  void beginAgain() => _gesture(() => _handOff(_startOver()));

  void teamTapped() => _gesture(() {
    if (state.needsPerson) _dispatch(const TeamTapped());
  });

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
      unawaited(_hand.pull());
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
    _coverageWatch = _apart(
      () => _room
          .watchCoverage(sessionId)
          .listen(
            _onCoverageFrame,
            onDone: () => _coverageChannelDied(sessionId, reopen: !refused),
            onError: (Object error) {
              switch (error) {
                case NetworkFailed():
                  refused = false;
                  _theNetworkFailedAt(Door.coverage);
                case SessionGone():
                  refused = true;
                  _theSessionIsGone(sessionId);
                case Refused(:final code):
                  refused = RefusalCode.stopsTheRoom.contains(code);
                default:
                  refused = false;
              }
            },
          ),
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
    final advanced = await _pullState(sessionId, clock: _coverageClock);
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

  /// A turn that carried no coverage, or fewer elements than the necklace already
  /// shows, leaves the necklace where it is; an answer without the bead fields keeps the
  /// beads it shows and takes the rest. Reading a missing field as zero emptied the cord
  /// mid-passage — the only record of progress this team can perceive — and a read
  /// that raced ahead of a slower one used to be able to put it back. The same guard
  /// runs whether the number came from the coverage frame or from the state pull that
  /// follows it, so the pull confirming what the frame already painted never re-marks
  /// the clock a second time.
  bool _applyCoverage(Coverage? told, {TurnClock? clock}) {
    final before = state.coverage;
    if (told == null) return false;
    if (const {
      VoiceState.listening,
      VoiceState.thinking,
      VoiceState.speaking,
    }.contains(state.voice)) {
      final held = _grown(told, from: _heldCoverage ?? before);
      if (held != null) {
        _heldCoverage = held;
        _heldCoverageClock = clock ?? _heldCoverageClock;
      }
      return held != null && held.beadsFilled > before.beadsFilled;
    }
    return _paintCoverage(told, clock: clock);
  }

  bool _paintCoverage(Coverage? told, {TurnClock? clock}) {
    final before = state.coverage;
    if (told == null) return false;
    final next = _grown(told, from: before);
    if (next == null) return false;
    final moved = next.beadsFilled > before.beadsFilled;
    if (moved) clock?.mark('beads');
    state = state.copyWith(coverage: next);
    return moved;
  }

  Coverage? _grown(Coverage told, {required Coverage from}) {
    final grows =
        told.engaged > from.engaged ||
        (told.engaged == from.engaged && told.surfaced >= from.surfaced);
    if (!grows) return null;
    return told.beadsTold && told.beadsFilled >= from.beadsFilled
        ? told
        : told.keepingTheBeadsOf(from);
  }

  void _landTheHeldCoverage() {
    final held = _heldCoverage;
    final clock = _heldCoverageClock;
    _heldCoverage = null;
    _heldCoverageClock = null;
    _applyCoverage(held, clock: clock);
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
      unawaited(_pullState(sessionId, clock: clock));
    }
    unawaited(_hand.pull());
  }

  /// Reads the state directly, folding in whatever the coverage channel might have
  /// missed. Reports whether the necklace actually moved, so a caller settling a wait
  /// from this alone — the recovery read after a reopen — knows whether it landed
  /// something, and the clock that measures the trip only marks a beat that happened:
  /// stamping it on a pull that changed nothing timed a turn that never actually landed.
  Future<bool> _pullState(String sessionId, {TurnClock? clock}) async {
    final generation = _waitOnTheGeneration;
    final life = _thisLife;
    final sent = ++_readsSent;
    final row = state.btTrechos;
    switch (await _room.fetchState(sessionId)) {
      case Answered(value: final snapshot):
        if (_abandoned(generation) || state.sessionId != sessionId) {
          return false;
        }
        _applyTheSessionRead(snapshot, sent, rowWhenSent: row);
        return _applyWhatOnlyGrows(snapshot, clock: clock);
      case SessionGone():
        _theSessionIsGoneIn(sessionId, life);
        return false;
      case NetworkFailed():
        _theNetworkFailedIn(Door.coverage, life);
        return false;
      case final Refused refused:
        if (_abandoned(generation)) return false;
        _decideAt(refused, door: Door.coverage, rule: RefusalRule.passes);
        return false;
    }
  }

  late Future<void>? _launching;
  late bool _launched;

  /// Land on the Current session while the room still holds it, and on the Choice
  /// otherwise, unless the team already stands somewhere in the room. The record is read
  /// once per launch: a later call opens the Choice, so a resume never pulls the team into
  /// a passage. A second call while the first is on its way is the first.
  Future<void> openTheRoom() async {
    if (state.station is! Menu || state.naRoda != null || state.needsPerson) {
      return;
    }
    final launching = _launching ??= _gestureThen(
      _launched ? _abrirEscolha : _launch,
    );
    _launched = true;
    try {
      await launching;
    } finally {
      if (identical(_launching, launching)) _launching = null;
    }
  }

  /// Read by its id, never opened: an open would hand back a fresh session after a Desk
  /// reset and hide that this one is gone (ADR 0064).
  Future<void> _launch() async {
    final generation = _waitOnTheGeneration;
    final held = await _store.currentSession();
    if (_abandoned(generation)) return;
    if (held == null) return _abrirEscolha();
    return _landOn(held);
  }

  /// The session read afresh before every landing, the retry's included: a snapshot kept
  /// across a wait would miss a halt the room raised meanwhile.
  Future<void> _landOn(CurrentSession held) async {
    final generation = _waitOnTheGeneration;
    final read = await _room.fetchState(held.sessionId);
    if (_abandoned(generation)) return;
    if (read case Answered(value: final snapshot)) {
      _landingOn = held;
      return _goConversa(
        book: held.book,
        pericope: held.pericope,
        opened: snapshot,
        language: held.language,
      );
    }
    if (read case SessionGone()) _theSessionIsGone(held.sessionId);
    return _abrirEscolha();
  }

  Future<void> Function() _enterAgain(_Passage passage) {
    final landing = _landingOn;
    if (landing == null) return () => _enterThePassage(passage);
    return () => _gestureThen(() => _landOn(landing));
  }

  Future<void> _enterThePassage(_Passage passage) => goConversa(
    book: passage.book,
    pericope: passage.pericope,
    language: _sessionLanguage,
  );

  void _holdTheCurrentSession(
    String sessionId,
    String book,
    String pericope,
    String language,
  ) => unawaited(
    _store
        .holdTheSession(
          CurrentSession(
            sessionId: sessionId,
            book: book,
            pericope: pericope,
            language: language,
          ),
        )
        .catchError((_) {}),
  );

  void _letGoOfTheCurrentSession({String? only}) =>
      unawaited(_store.letGoOfTheSession(only: only).catchError((_) {}));

  Future<void> _voicePanorama(TurnResult turn) async {
    final generation = _waitOnTheGeneration;
    await _readyToSpeak(turn.audioUrl, turn.fixedLine);
    if (_abandoned(generation)) return;
    if (_answeredWithNothingToPlay(turn)) return;
    _watchBusyState();
    final played = await _speak(turn.audioUrl, turn.fixedLine);
    if (_abandoned(generation)) return;
    if (!played.heard) {
      _registerUnplayableTurn();
      return;
    }
    _resumeFailures.clear();
    _openTurnId = null;
    _openingOwed = false;
    state = state.copyWith(awaitingTheGuide: false, panoramaSaid: true);
  }

  void panoramaTap() => _gesture(() => _panoramaTap());

  void _panoramaTap() {
    final station = state.station;
    if (station is! Panorama) return;
    if (state.needsPerson) return;
    if (state.noteMode) {
      _hand.noteTap();
      return;
    }
    if (state.panoramaSaid) {
      switch (state.voice) {
        case VoiceState.invite:
          _startListening('panorama_${_stamp()}');
        case VoiceState.listening:
          _handOff(_finishPanoramaListening());
        case VoiceState.thinking:
        case VoiceState.speaking:
        case VoiceState.done:
          break;
      }
      return;
    }
    if (state.voice == VoiceState.invite) {
      _silenceTheRoom();
      _handOff(_entrarNoPanorama(station.id, state.machine.panorama?.language));
    }
  }

  Future<void> _finishPanoramaListening() async {
    final generation = _waitOnTheGeneration;
    final path = (await _closeTheMicrophone()).take;
    if (_abandoned(generation)) return;
    final panorama = state.panoramaSessionId!;
    if (path == null || !_hasAudio(path)) {
      state = state.copyWith(awaitingTheGuide: false);
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    await _sendThePanoramaTurn(panorama, path, _stamp());
  }

  Future<void> _sendThePanoramaTurn(
    String panorama,
    String path,
    String turnId,
  ) async {
    final generation = _waitOnTheGeneration;
    _sayImThinking();
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    void failed(RoomFailure failure) {
      if (_abandoned(generation)) return;
      _decideTheFailure(failure, rule: RefusalRule.aSpokenTurn);
    }

    await _sendATurn(
      Turn(panorama, turnId),
      generation,
      () => _room.sendTurn(panorama, File(path), turnId: turnId),
      play: (turn) => _voicePanorama(turn),
      failed: failed,
    );
  }

  Future<void> abrirEscolha() => _gestureThen(_abrirEscolha);

  Future<void> _abrirEscolha() async {
    if (state.station is! Menu) {
      _forgetThePassage();
    }
    _leaveTheStepFor(const Menu());
    _clearAll();
    _arriveAt(const TheChoiceOpened());
    final generation = _waitOnTheGeneration;
    state = state.copyWith(
      arrivedAtTheChoice: true,
      awaitingTheGuide: true,
      peerCue: false,
      clearRoda: true,
    );
    _watchBusyState();
    final language = _lingua;
    final List<String> books;
    switch (await _room.servedBooks()) {
      case Answered(value: final served):
        books = served;
      case final RoomFailure failure:
        if (_abandoned(generation)) return;
        _decideTheFailure(failure);
        return;
    }
    if (_abandoned(generation)) return;
    final lists = await Future.wait([
      for (final book in books) _room.passagesOf(book, language: language),
    ]);
    final todas = <Passagem>[];
    for (final list in lists) {
      switch (list) {
        case Answered(value: final passagens):
          todas.addAll(passagens);
        case final RoomFailure failure:
          if (_abandoned(generation)) return;
          _decideTheFailure(failure);
          return;
      }
    }
    if (_abandoned(generation)) return;
    // Held before the await: a provider read after the container is disposed throws,
    // and this method is reached from a fire-and-forget touch.
    final open = _emAberto;
    final comecadas = {
      for (final book in books) ...await open.startedIn(book, language),
    };
    if (_abandoned(generation)) return;
    state = state.copyWith(
      naRoda: todas,
      comecadas: comecadas,
      awaitingTheGuide: false,
    );
  }

  void escolhaTap() => _gesture(() => _escolhaTap());

  void _escolhaTap() {
    if (state.station is! Menu) return;
    if (state.needsPerson) return;
    if (state.voice != VoiceState.invite) return;
    final roda = state.naRoda;
    if (roda == null || roda.isEmpty) {
      // The wheel never loaded, or offers nothing. There is nothing to say and nothing to
      // enter, so the touch is the retry — otherwise this screen has no live gesture at all.
      _handOff(abrirEscolha());
    }
  }

  void openTheEntry(Passagem entry) => _gesture(() => _openTheEntry(entry));

  void _openTheEntry(Passagem entry) {
    if (!state.entriesOpen || !state.naRoda!.contains(entry)) return;
    if (state.isTheEntryLeft(entry, language: _lingua)) {
      _returnToTheLeftEntry();
      return;
    }
    _silenceTheRoom();
    state = state.copyWith(clearLeftEntry: true);
    if (entry.isPanorama) {
      _leaveTheStepFor(Panorama(entry.pericope));
      _clearAll();
      _arriveAt(ThePanoramaChosen(entry.pericope));
      _handOff(_entrarNoPanorama(entry.pericope));
      return;
    }
    _handOff(goConversa(book: entry.book, pericope: entry.pericope));
  }

  /// Open the Panorama's session and voice its opening. It has no foreseen end, and
  /// nothing here schedules one: the team leaves it the way it leaves any session.
  ///
  /// The session is reused for the same Panorama in the same language rather than asked
  /// for again on every tap: a retried touch would otherwise mint one abandoned panorama
  /// session per attempt.
  Future<void> _entrarNoPanorama(String id, [String? language]) async {
    final speaking = language ?? _lingua;
    _dispatch(ThePanoramaAsked(id, speaking));
    _letGoOfTheCurrentSession();
    final generation = _waitOnTheGeneration;
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    void failed(RoomFailure failure) {
      if (_abandoned(generation)) return;
      _decideTheFailure(failure);
    }

    SessionSnapshot? created;
    if (state.panoramaSessionId == null) {
      switch (await _room.createSession(pericope: id, language: speaking)) {
        case Answered(value: final session):
          created = session;
        case final RoomFailure failure:
          return failed(failure);
      }
    }
    if (_abandoned(generation)) return;
    final panorama = state.panoramaSessionId ?? created!.sessionId;
    _dispatch(TheSessionOpened(panorama, generation: generation));
    _warmHerLines();
    _openingOwed = true;
    final turnId = _openTurnId ??= _stamp();
    await _sendATurn(
      Turn(panorama, turnId),
      generation,
      () => _room.openSession(panorama, turnId: turnId),
      play: _voicePanorama,
      failed: failed,
    );
  }

  /// Leave a passage part-way and go pick another one.
  ///
  /// There was no way out at all: a team that entered the wrong passage was held there
  /// until it was checked, or had to have the app killed. The passage was never finished,
  /// so it stays in the wheel, and the upload queue keeps whatever it was already holding.
  void leaveThePassage() => _gesture(() => _leaveThePassage());

  void _leaveThePassage() {
    final left = _whatTheLeaveLeaves();
    _clearAll();
    _dropThePendingTake();
    _forgetThePassage();
    _openTheChoice();
    if (left != null) state = state.copyWith(leftEntry: left);
  }

  LeftEntry? _whatTheLeaveLeaves() {
    final station = state.station;
    final session = _sessionId;
    if (station is Panorama) {
      if (session == null) return null;
      return LeftEntry(
        pericope: station.id,
        panorama: true,
        session: session,
        language: state.machine.panorama?.language,
        said: state.panoramaSaid,
      );
    }
    final passage = _emCurso;
    if (passage == null || (session == null && passage.pericope == null)) {
      return null;
    }
    return LeftEntry(
      pericope: passage.pericope,
      book: passage.book,
      session: session,
      language: _sessionLanguage,
      held: _theTakeTheLeaveHolds(),
    );
  }

  /// A kept take sounding in the Rehearsal, as it will be laid back: paused where it was.
  /// The place is the channel's head, never the player's position while its clip has not
  /// opened. The pending take dies with the leave, so neither it nor what follows it is held.
  Paused? _theTakeTheLeaveHolds() {
    if (state.station is! Ensaio) return null;
    final kept = state.partes.length;
    final pending = _pendingTakePath;
    bool isKept(Sound sound) =>
        sound is PartSound && sound.part < kept && sound.path != pending;
    final PartSound part;
    final List<Sound> next;
    final Duration? head;
    switch (state.channel) {
      case PartPlaying(
        part: final playing,
        next: final following,
        head: final playingHead,
      ):
        (part, next, head) = (playing, following, playingHead);
      case Paused(
        what: final PartSound held,
        next: final following,
        head: final heldHead,
      ):
        (part, next, head) = (held, following, heldHead);
      default:
        return null;
    }
    if (!isKept(part)) return null;
    final position = _playback.position;
    final at = head ?? (part.to == null ? position : part.from + position);
    return Paused(
      PartSound(part.part, part.path, from: at, to: part.to),
      next: next.takeWhile(isKept).toList(),
      started: false,
      opened: false,
    );
  }

  /// The way back to the entry the team left: a return, not a new entry. The Panorama
  /// comes back silent once its line was said; a passage comes back through the resume.
  Future<void> returnToTheLeftEntry() async => _gesture(_returnToTheLeftEntry);

  void _returnToTheLeftEntry() {
    if (!state.theWayBackIsLive) return;
    final left = state.leftEntry!;
    state = state.copyWith(clearLeftEntry: true);
    if (left case LeftEntry(panorama: true, pericope: final id?)) {
      _silenceTheRoom();
      _leaveTheStepFor(Panorama(id));
      _clearAll();
    }
    _arriveAt(TheWayBackTaken(left));
  }

  void _returnToThePanorama() {
    state = state.copyWith(panoramaSaid: true);
    unawaited(_hand.pull());
  }

  Future<void> _enterThePassageLeft(LeftEntry left) async {
    await goConversa(
      book: left.book!,
      pericope: left.pericope,
      language: left.language,
    );
    final held = left.held;
    if (held != null &&
        state.sessionId == left.session &&
        state.station is Ensaio) {
      _dispatch(TheHeldPartReturns(held));
    }
  }

  void _theSessionIsGone([String? sessionId]) =>
      _theSessionIsGoneIn(sessionId, _thisLife);

  void _theSessionIsGoneIn(String? sessionId, int? life) {
    if (_endedSince(life)) return;
    if (sessionId != null && sessionId != _sessionId) {
      return _letGoOf(sessionId);
    }
    _dispatch(decided(const RoomSessionGone(), _failureContext()));
  }

  void _letGoOf(String? sessionId, {List<String> kept = const []}) {
    final life = _thisLife;
    if (sessionId != null) {
      _goneSessions.add(sessionId);
      _frases.letGoOfTheSession(sessionId);
      _dispatch(TheSessionLetGo(sessionId));
    }
    if (sessionId != null && state.leftEntry?.session == sessionId) {
      state = state.copyWith(clearLeftEntry: true);
    }
    unawaited(
      _mindingThePlace(
        () => _forgetTheSessionOnDisk(sessionId, kept),
      ).whenComplete(() => _countUnsentIn(life)),
    );
  }

  Future<RoomAnswer<SessionSnapshot>> _createThePassage(
    String book,
    String? pericope,
    String language,
    int generation,
  ) async {
    final after = state.thePanoramaSessionOf(book);
    final life = _thisLife;
    final answer = await _room.createSession(
      pericope: pericope,
      afterSession: after,
      language: language,
    );
    if (answer case SessionGone() when after != null) {
      if (_endedSince(life)) return answer;
      _letGoOf(after);
      if (_abandoned(generation)) return answer;
      return _room.createSession(pericope: pericope, language: language);
    }
    return answer;
  }

  void _discardTheSession() {
    final sessionId = _sessionId;
    final kept = [for (final take in state.keptTakes) take.path];
    _clearAll();
    _dropThePendingTake();
    _forgetThePassage();
    _letGoOf(sessionId, kept: kept);
  }

  Future<void> _forgetTheSessionOnDisk(
    String? sessionId,
    List<String> kept,
  ) async {
    final open = _emAberto;
    final queue = _takes;
    final recorder = _recorder;
    if (sessionId != null) {
      _letGoOfTheCurrentSession(only: sessionId);
      await queue.discardTheSession(sessionId);
    }
    for (final path in kept) {
      await recorder.delete(path);
    }
    if (sessionId == null) return;
    for (final row in await open.forgetTheSession(sessionId)) {
      for (final take in row.takes) {
        if (!kept.contains(take.path)) await recorder.delete(take.path);
      }
    }
  }

  void _openTheChoice() {
    _partesDescendo = null;
    _aLinhaDiz = null;
    state = SalaSessionState(
      machine: state.machine.withNoPassage(_gesturesOnTheirWay.onTheirWay),
    );
    _letGoOfTheCurrentSession();
    _arriveAt(const TheRoomStartedOver());
    _handOff(abrirEscolha());
  }

  /// Everything of the session before this one stays behind.
  ///
  /// Only what the book knows crosses over — the wheel and the passages started — and
  /// entering the passage says the rest again.
  /// Built from an empty state rather than cleared field by field, so a fact the session
  /// gains tomorrow is born clean here without anybody remembering this branch; the
  /// counters and latches with no home in the state go through [_forgetThePassage],
  /// which is already where they live.
  void _startTheSessionClean(_Passage passage) {
    final livro = state;
    _dropThePendingTake();
    _forgetThePassage();
    _emCurso = passage;
    state = SalaSessionState(
      machine: _gesturesOnTheirWay.copyWith(panorama: livro.machine.panorama),
      awaitingTheGuide: true,
      naRoda: livro.naRoda,
      comecadas: livro.comecadas,
    );
    _arriveAt(const PassageChosen());
    _stringTheNecklaceEarly(passage.pericope);
  }

  /// Enter a passage, resuming the session this tablet left in it when there is one.
  ///
  /// `fresh` skips the resume.
  ///
  /// `opened` is a session the room already holds for this passage, entered as it came
  /// back rather than asked for again, and never asked its Opening: the launch hands it
  /// the session it read (ADR 0064).
  Future<void> goConversa({
    required String book,
    String? pericope,
    bool fresh = false,
    SessionSnapshot? opened,
    String? language,
  }) => _gestureThen(
    () => _goConversa(
      book: book,
      pericope: pericope,
      fresh: fresh,
      opened: opened,
      language: language,
    ),
  );

  Future<void> _goConversa({
    required String book,
    String? pericope,
    bool fresh = false,
    SessionSnapshot? opened,
    String? language,
  }) async {
    final speaking = language ?? _lingua;
    _sessionLanguage = speaking;
    _leaveTheStepFor(const Canvas());
    _clearAll();
    _emCurso = (book: book, pericope: pericope);
    if (opened == null) _landingOn = null;
    _arriveAt(const PassageChosen());
    var generation = _waitOnTheGeneration;
    void landed() => generation = _waitOnTheGeneration;

    state = state.copyWith(awaitingTheGuide: true, peerCue: false);
    _stringTheNecklaceEarly(pericope);
    _watchBusyState();
    final openingClock = TurnClock();
    _pendingClock = openingClock;
    openingClock.mark('health');
    // Only the passages the wheel already said have work waiting are looked up on disk,
    // so entering a fresh one through the wheel costs no read at all. A door the room
    // opened, and an entry that brings its own language (the way back, a retry, a
    // relaunch), have no wheel of that language behind them, so the row is looked up
    // there whatever the list says (ADR 0033, ADR 0077).
    final waiting =
        !fresh &&
            pericope != null &&
            (opened != null ||
                language != null ||
                state.comecadas.contains(pericope))
        ? await _emAberto.of(book, pericope, speaking)
        : null;
    if (_abandoned(generation)) return;
    _listenerInProgress = waiting?.listener;
    final theResume = '$book/$pericope/$speaking';
    void failed(
      RoomFailure failure, {
      RefusalRule rule = RefusalRule.letsTheStepGo,
      Door door = Door.step,
    }) {
      if (_abandoned(generation)) return;
      if (failure case Refused(:final code)
          when waiting != null &&
              !RefusalCode.stopsTheRoom.contains(code) &&
              code != RefusalCode.canonNotKept) {
        final failures = (_resumeFailures[theResume] ?? 0) + 1;
        _resumeFailures[theResume] = failures;
        if (failures >= _resumeFailuresBeforeForgetting) {
          _resumeFailures.remove(theResume);
          unawaited(
            _mindingThePlace(() => _emAberto.forget(book, pericope!, speaking)),
          );
        }
      }
      _decideTheFailure(failure, rule: rule, door: door);
    }

    final resumed = waiting != null;
    var created = resumed ? null : opened;
    if (!resumed && opened == null) {
      switch (await _createThePassage(book, pericope, speaking, generation)) {
        case Answered(value: final session):
          created = session;
        case final RoomFailure failure:
          return failed(failure);
      }
      openingClock.mark('session');
    }
    final sessionId = waiting?.sessionId ?? created!.sessionId;
    if (_abandoned(generation)) return;
    if (_goneSessions.contains(sessionId)) return _openTheChoice();
    if (!resumed) _startTheSessionClean((book: book, pericope: pericope));
    state = state.copyWith(
      pericope: pericope,
      coverage: created?.coverage,
      moment: created?.moment,
    );
    _dispatch(TheSessionOpened(sessionId, generation: generation));
    // The scenes are the passage's, asked while the session opens on the network it
    // needs anyway, so a Rehearsal the room falls under still knows its rows.
    unawaited(_askForTheScenes());
    if (pericope != null) {
      _holdTheCurrentSession(sessionId, book, pericope, speaking);
    }
    _sessionSavedAt = resumed ? waiting.savedAt : clock.now();
    _warmHerLines();
    if (pericope != null && !resumed) {
      unawaited(
        _mindingThePlace(
          () => _emAberto.remember(
            book,
            pericope,
            speaking,
            ResumePoint(
              sessionId: sessionId,
              stage: const Canvas().stage,
              savedAt: _sessionSavedAt,
              language: _sessionLanguage,
            ),
          ),
        ),
      );
    }
    unawaited(_hand.pull());
    _watchBusyState();
    if (resumed) {
      (SessionSnapshot, int)? lida;
      final onde = await _backToWhereTheyStopped(
        waiting,
        generation,
        landed: landed,
        read: (read, sent) => lida = (read, sent),
      );
      if (_abandoned(generation)) return;
      if (onde == _Resume.failed ||
          onde == _Resume.abandoned ||
          onde == _Resume.gone) {
        return;
      }
      if (onde == _Resume.onTheApprovedDraft) {
        _resumeFailures.remove(theResume);
        return;
      }
      if (onde == _Resume.landed || onde == _Resume.landedShort) {
        final SessionSnapshot snapshot;
        final int sent;
        if (lida case (final read, final enviada)) {
          (snapshot, sent) = (read, enviada);
        } else {
          sent = ++_readsSent;
          switch (await _room.fetchState(sessionId)) {
            case Answered(value: final read):
              snapshot = read;
            case final SessionGone gone:
              return failed(gone);
            case final RoomFailure failure:
              return failed(
                failure,
                rule: RefusalRule.keepsTheResume,
                door: Door.resume,
              );
          }
        }
        if (_abandoned(generation)) return;
        state = state.copyWith(
          coverage: snapshot.coverage,
          moment: snapshot.moment,
          clearMoment: snapshot.moment == null,
        );
        if (onde == _Resume.landed &&
            await _landedOnTheApprovedDraft(
              snapshot,
              sent,
              generation,
              landed,
              resumed: waiting,
            )) {
          _aLeituraDecidiu = true;
          return;
        }
        if (onde == _Resume.landed && Station.stored(waiting.stage) is Retro) {
          _pickTheTellingBackUp(snapshot.backTranslation);
          landed();
          unawaited(_countUnsent());
        } else {
          _keepTheStretchesAlreadyTold(snapshot.backTranslation);
        }
        // The snapshot was fetched here and its halt never read, so a team reopening
        // into a room the server had already stopped met every gesture wide open.
        //
        // After the telling-back is picked up, not before, so that the passage the team
        // comes back to is the one they left: a person resolving the halt finds them in
        // their retro rather than dropped back into the rehearsal.
        _resumeFailures.remove(theResume);
        _applyTheSessionRead(snapshot, sent);
        _aLeituraDecidiu = true;
        _asPartesPerdidasSaem();
        return;
      }
      final SessionSnapshot read;
      final sent = ++_readsSent;
      switch (await _room.fetchState(sessionId)) {
        case Answered(value: final snapshot):
          read = snapshot;
        case final SessionGone gone:
          return failed(gone);
        case final RoomFailure failure:
          return failed(
            failure,
            rule: RefusalRule.keepsTheResume,
            door: Door.resume,
          );
      }
      if (_abandoned(generation)) return;
      state = state.copyWith(
        coverage: read.coverage,
        moment: read.moment,
        clearMoment: read.moment == null,
      );
      if (await _landedOnTheApprovedDraft(
        read,
        sent,
        generation,
        landed,
        resumed: waiting,
      )) {
        return;
      }
      if (Station.stored(waiting.stage) is Retro) {
        final told = read.backTranslation;
        // Only when there is a telling-back to land on. A checked answer carrying no
        // stretch contradicts itself — the check is about what was told — and there is
        // no rehearsal here to land it on either, so this door declines it: landing it
        // left the room standing in the conversa until the watchdog called a person two
        // minutes later. It falls through instead, as every other empty answer does:
        // the room lands quiet on a session it opened and asks the Opening only of one
        // it never opened. Closing would call a passage the team never approved its
        // final draft.
        //
        // Reached only when the room holds no rehearsal of its own to hand back, which
        // is the one way past this door now that a resume fetches the parts.
        if (told.checked && !told.nothingTold) {
          _pickTheTellingBackUp(told);
          landed();
          _resumeFailures.remove(theResume);
          _applyTheSessionRead(read, sent);
          return;
        }
      }
      _applyTheSessionRead(read, sent);
      unawaited(_learnWhetherAPartWasJoined(sessionId, generation));
      if (opened != null || read.opened) return _landWhereTheyStopped();
    } else {
      final sent = ++_readsSent;
      if (await _landedOnTheApprovedDraft(created!, sent, generation, landed)) {
        return;
      }
      if (opened != null || created.opened) {
        _applyTheSessionRead(created, sent);
        return _landWhereTheyStopped();
      }
    }
    await _askForTheOpening(
      sessionId,
      generation,
      play: (opening) {
        openingClock.mark('open');
        return _voiceTurn(
          opening,
          generation,
          onSoundStart: () => openingClock.mark('sound'),
        );
      },
      failed: failed,
    );
  }

  /// The draft the room says is approved is where its passage reopens: its telling-back,
  /// checked, over the parts the room holds, and never the Opening (ADR 0106). Anything of
  /// the session still in the Outbox un-approves the draft once it lands, so the team stays
  /// where it stood. The read keeps the number it was sent under, so a Watch beat sent while
  /// the parts come down outranks it.
  Future<bool> _landedOnTheApprovedDraft(
    SessionSnapshot read,
    int sent,
    int generation,
    void Function() landed, {
    ResumePoint? resumed,
    List<KeptTake>? aqui,
    void Function(RoomFailure failure)? aListaFalhou,
  }) async {
    if (read.approved == null || read.backTranslation.nothingTold) return false;
    final waiting = (await _takes.pending()).any(
      (entry) =>
          entry.sessionId == read.sessionId && entry.kind != sceneTakeKind,
    );
    if (waiting || _abandoned(generation)) return _abandoned(generation);
    if (state.partes.isEmpty) {
      final falhou = await _theRoomsRehearsalUnder(
        read.sessionId,
        aqui ?? const [],
        generation,
      );
      if (_abandoned(generation)) return true;
      if (falhou != null && aqui != null) {
        aListaFalhou?.call(falhou);
        return false;
      }
    }
    final told = read.backTranslation;
    state = state.copyWith(clearBtFraseGuardada: true);
    _pickTheTellingBackUp(
      BackTranslationProgress(
        segments: told.segments,
        checked: true,
        findings: told.findings,
      ),
    );
    landed();
    state = state.copyWith(
      coverage: read.coverage,
      moment: read.moment,
      clearMoment: read.moment == null,
    );
    _applyTheSessionRead(read, sent);
    _rememberWhereTheyAre(const Retro());
    _aLeituraDecidiu = true;
    _bringThePartsDown(const Retro());
    await _countUnsent();
    if ((resumed?.onTheExternalCheck ?? false) && _listenerInProgress != null) {
      await _backToTheCheck(read.sessionId, _waitOnTheGeneration);
    }
    return true;
  }

  /// The row stood on the Checagem externa with a listener: the check is opened again and
  /// the listener found where the room says they stand.
  Future<void> _backToTheCheck(String sessionId, int generation) async {
    final answer = await _room.openTheExternalCheck(sessionId);
    if (_abandoned(generation)) return;
    switch (answer) {
      case Answered(value: final check):
        _resumeFailures.clear();
        await _backToTheListener(sessionId, check, generation);
      case Refused(code: RefusalCode.draftNotApproved):
        _listenerInProgress = null;
        _rememberWhereTheyAre(const Retro());
      case final RoomFailure failure:
        _theCheckDidNotOpen(failure);
    }
  }

  /// Her open-failed words on the Back-translation, or the Choice when the session is gone.
  void _theCheckDidNotOpen(RoomFailure failure) {
    switch (failure) {
      case SessionGone():
        _decideTheFailure(failure);
      case NetworkFailed():
        _theNetworkFailedAt(Door.stretches);
        state = state.copyWith(btAviso: BtAviso.checagemFalhou);
      case Refused():
        state = state.copyWith(btAviso: BtAviso.checagemFalhou);
    }
  }

  /// The room's current parts laid under an approved draft: a part this tablet holds is
  /// kept, every other comes down behind the landing.
  Future<RoomFailure?> _theRoomsRehearsalUnder(
    String sessionId,
    List<KeptTake> aqui,
    int generation,
  ) async {
    _watchBusyState();
    final listagem = await _room.takesOf(sessionId);
    if (listagem case final RoomFailure failure) return failure;
    if (listagem case Answered(value: final guardadas)) {
      if (_abandoned(generation)) return null;
      final lidas = _lerAListagem(guardadas, aqui);
      if (lidas.partes.isEmpty) return null;
      await _medirAsPartes([
        for (final take in lidas.partes)
          if (!lidas.aBuscar.contains(take.takeId)) take,
      ], generation);
      if (_abandoned(generation)) return null;
      state = state.copyWith(
        keptTakes: lidas.partes,
        wholeHeldByTheRoom: lidas.deLado,
        partsAway: {
          for (final takeId in lidas.aBuscar) takeId: PartAway.coming,
        },
      );
      state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
    }
    return null;
  }

  Future<void> _learnWhetherAPartWasJoined(
    String sessionId,
    int generation,
  ) async {
    if (await _room.takesListingOf(sessionId) case Answered(
      value: final listing,
    )) {
      if (_abandoned(generation)) return;
      _theRoomsGrainHeard(listing);
      state = state.copyWith(
        theRoomJoinedParts: _partesJuntadas(listing.takes),
      );
    }
  }

  /// The part numbers whose current take in the room's [guardadas] was laid in from a Scene
  /// rehearsal.
  static Set<int> _partesJuntadas(List<TakeView> guardadas) => {
    for (final MapEntry(:key, :value) in _correntes(guardadas).entries)
      if (key != null && value.origin != null) key,
  };

  /// The rehearsal takes the room [guardadas] lists, keyed by the room's number, which
  /// keeps the first place each number appears in and the last recording made under it.
  static Map<int?, TakeView> _correntes(List<TakeView> guardadas) => {
    for (final guardada in guardadas)
      if (guardada.kind == 'ensaio' && !guardada.setAside)
        guardada.ordinal: guardada,
  };

  /// The highest pass the room [guardadas] holds for each part number.
  static Map<int, int> _passadasMaisAltas(List<TakeView> guardadas) {
    final altas = <int, int>{};
    for (final guardada in guardadas) {
      if (guardada.ordinal case final ordinal? when guardada.kind == 'ensaio') {
        altas[ordinal] = max(altas[ordinal] ?? 0, guardada.pass ?? 1);
      }
    }
    return altas;
  }

  /// A session the room already opened is not opened again: the team lands at rest, and
  /// «Ouvir de novo» asks the room for its last line.
  void _landWhereTheyStopped() {
    _resumeFailures.clear();
    state = state.copyWith(
      awaitingTheGuide: false,
      peerCue: false,
      roomSaysItAgain: true,
    );
  }

  Future<void> _askForTheOpening(
    String sessionId,
    int generation, {
    required Future<void> Function(TurnResult opening) play,
    required void Function(RoomFailure failure) failed,
  }) {
    _openingOwed = true;
    final turnId = _openTurnId ??= _stamp();
    return _sendATurn(
      Turn(sessionId, turnId),
      generation,
      () => _room.openSession(sessionId, turnId: turnId),
      play: play,
      failed: failed,
    );
  }

  void _stringTheNecklaceEarly(String? pericope) {
    if (pericope == null) return;
    for (final passagem in state.naRoda ?? const <Passagem>[]) {
      if (passagem.pericope == pericope && passagem.beads > 0) {
        state = state.copyWith(
          coverage: Coverage(engaged: 0, surfaced: 0, total: passagem.beads),
        );
        return;
      }
    }
  }

  /// Write down where they are, so leaving lands them back here rather than at the start.
  void _rememberWhereTheyAre(Station station) {
    if (_gone) return;
    _aLinhaDiz = station;
    final passage = _emCurso;
    final pericope = passage?.pericope;
    final sessionId = state.sessionId;
    final language = _sessionLanguage;
    if (passage == null ||
        pericope == null ||
        sessionId == null ||
        language == null) {
      return;
    }
    unawaited(
      _mindingThePlace(
        () => _emAberto.remember(
          passage.book,
          pericope,
          language,
          ResumePoint(
            sessionId: sessionId,
            stage: station.stage,
            takes: state.keptTakes,
            savedAt: _sessionSavedAt,
            language: _sessionLanguage,
            partBeingRecordedAgain: state.parteARegravar,
            passesToGoAbove: _passadasDaSala ?? const {},
            listener: _listenerInProgress,
            wholeHeldByTheRoom: [...state.wholeHeldByTheRoom],
            grain: state.grainInForce,
          ),
        ),
      ),
    );
  }

  /// The room's passes for the part numbers that hold no part yet, or null when none is
  /// left.
  Map<int, int>? _aindaPorGravar(Map<int, int> passadas, Set<int> comParte) {
    final resta = {
      for (final MapEntry(:key, :value) in passadas.entries)
        if (!comParte.contains(key)) key: value,
    };
    return resta.isEmpty ? null : resta;
  }

  /// The room's listing did not answer a resume: a session it no longer knows is retired,
  /// anything else leaves the row as it was for the next opening.
  _Resume _aListaFalhou(RoomFailure failure, int generation) {
    if (_abandoned(generation)) return _Resume.abandoned;
    switch (failure) {
      case final SessionGone gone:
        _decideTheFailure(gone);
        return _Resume.gone;
      case NetworkFailed():
        return _theResumeFailed(const RoomNetworkFailed(), generation);
      case final Refused refused:
        return _theResumeFailed(refused.result, generation);
    }
  }

  _Resume _theResumeFailed(RoomResult result, int generation) {
    if (_abandoned(generation)) return _Resume.abandoned;
    _dispatch(
      decided(
        result,
        _failureContext(door: Door.resume, rule: RefusalRule.keepsTheResume),
      ),
    );
    return _Resume.failed;
  }

  /// Put the team back on the stage they left, fetching the rehearsal when it is gone.
  ///
  /// A restore, a reinstall or another tablet leaves the row naming files that are not
  /// here. The rehearsal is not lost: the room is holding it, and the team comes back to
  /// the station they left with the room's own parts under them.
  Future<_Resume> _backToWhereTheyStopped(
    ResumePoint waiting,
    int generation, {
    required void Function() landed,
    required void Function(SessionSnapshot read, int sent) read,
  }) async {
    final stage = Station.stored(waiting.stage);
    final anEmptyEnsaio = stage is Ensaio && waiting.takes.isEmpty;
    final aPartlessRetro = stage is Retro && waiting.takes.isEmpty;
    if (stage is Canvas ||
        (waiting.takes.isEmpty && !anEmptyEnsaio && !aPartlessRetro)) {
      return _Resume.nothingToRestore;
    }
    final aSceneHasItsPart = waiting.takes.any(
      (take) => KeptScope.isParte(take.scopeId),
    );
    var heldByTheRoom = {...waiting.wholeHeldByTheRoom};
    final here = <KeptTake>[];
    var missing = false;
    for (final take in waiting.takes) {
      if (await File(take.path).exists()) {
        here.add(take);
      } else if (aSceneHasItsPart &&
          take.scopeId == KeptScope.whole &&
          take.takeId != null) {
        heldByTheRoom.add(take.takeId!);
      } else {
        missing = true;
      }
    }
    if (_abandoned(generation)) return _Resume.abandoned;
    final faltavam = aPartlessRetro || missing;
    if (stage is Retro && faltavam) {
      final sent = ++_readsSent;
      if (await _room.fetchState(waiting.sessionId) case Answered(
        value: final lida,
      )) {
        if (_abandoned(generation)) return _Resume.abandoned;
        RoomFailure? listaFalhou;
        if (await _landedOnTheApprovedDraft(
          lida,
          sent,
          generation,
          landed,
          aqui: aPartlessRetro ? null : here,
          resumed: waiting,
          aListaFalhou: (failure) => listaFalhou = failure,
        )) {
          return _abandoned(generation)
              ? _Resume.abandoned
              : _Resume.onTheApprovedDraft;
        }
        if (listaFalhou case final failure?) {
          return _aListaFalhou(failure, generation);
        }
        read(lida, sent);
      }
      if (_abandoned(generation)) return _Resume.abandoned;
    }
    List<KeptTake>? takes = here;
    var inteiro = true;
    var aBuscar = const <String>{};
    if (faltavam) {
      // Armed per step, not once around the whole fetch: the ceiling is what a single
      // wait is allowed, and a listing plus a part plus a measurement counted as one wait
      // gives up on a link that is slow but working.
      _watchBusyState();
      switch (await _room.takesOf(waiting.sessionId)) {
        case Answered(value: final guardadas):
          if (_abandoned(generation)) return _Resume.abandoned;
          if (stage is! Retro) {
            final lidas = _lerAListagem(guardadas, here);
            takes = lidas.partes;
            heldByTheRoom = lidas.deLado;
            aBuscar = lidas.aBuscar;
            break;
          }
          switch (await _asPartesDaSala(
            waiting.sessionId,
            guardadas,
            here,
            generation,
          )) {
            case Answered(:final value?):
              takes = value.partes;
              inteiro = value.inteiro;
              heldByTheRoom = value.deLado;
              if (!inteiro) {
                _passadasDaSala = _aindaPorGravar(value.passadas, const {});
              }
            case Answered():
              takes = null;
            case NetworkFailed():
              if (_abandoned(generation)) return _Resume.abandoned;
              return _theResumeFailed(const RoomNetworkFailed(), generation);
            case final RoomFailure failure:
              return _theResumeFailed(failure.result, generation);
          }
        case final RoomFailure failure:
          return _aListaFalhou(failure, generation);
      }
    }
    if (_abandoned(generation)) return _Resume.abandoned;
    if (takes == null) {
      return _theResumeFailed(const RoomFoundNothing(), generation);
    }
    if (!faltavam) {
      _passadasDaSala = _aindaPorGravar(waiting.passesToGoAbove, {
        for (final take in takes) ?KeptScope.numberOf(take.scopeId),
      });
    }
    // A room holding no rehearsal is not a rehearsal to come back to, and it is not a
    // failure either: the conversa is where a passage with nothing behind it starts —
    // unless the row itself stood on the Ensaio with no part yet.
    if (takes.isEmpty && inteiro && !anEmptyEnsaio) {
      return _Resume.nothingToRestore;
    }
    if (faltavam) {
      await _medirAsPartes([
        for (final take in takes)
          if (!aBuscar.contains(take.takeId)) take,
      ], generation);
    }
    if (_abandoned(generation)) return _Resume.abandoned;
    _leaveTheStepFor(const Ensaio());
    _arriveAt(const TheRehearsalOpened());
    landed();
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      awaitingTheGuide: false,
      keptTakes: takes,
      wholeHeldByTheRoom: heldByTheRoom,
      parteARegravar: waiting.partBeingRecordedAgain,
      grainInForce: waiting.grain,
      partsAway: {for (final takeId in aBuscar) takeId: PartAway.coming},
    );
    _readTheScenesForTheRehearsal();
    if (faltavam) {
      state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
      if (aBuscar.isEmpty) {
        _rememberWhereTheyAre(
          inteiro ? Station.stored(waiting.stage) : const Ensaio(),
        );
      } else {
        _aLeituraDecidiu = false;
        _bringThePartsDown(Station.stored(waiting.stage));
      }
    }
    unawaited(_countUnsent());
    return inteiro ? _Resume.landed : _Resume.landedShort;
  }

  /// The room's current parts, kept on a tablet that no longer holds them.
  ///
  /// The current parts are the newest rehearsal recording under each number, in the order
  /// the room lists them — the server's own rule, so a part recorded again is the one the
  /// team gets back (ADR 0020). A telling-back is never one of them: it is the team
  /// explaining the story, not the story.
  ///
  /// Each keeps the number the room holds for it, because part N is Scene N: a room
  /// holding part 3 alone hands it back on row 3, never renumbered by its place in the
  /// listing. A recording the room does not number is the rehearsal an app before
  /// 19 August sent whole: it comes back whole and is no scene's part, and behind a part
  /// of a scene it is set aside: kept by its own file when the tablet holds it, otherwise
  /// known by the room's take id alone and never fetched. Each keeps where the room says it
  /// was joined from.
  ///
  /// A file still on the tablet under a current part's name is kept as it is: it is the
  /// team's own recording, and fetching a copy over the room's link would spend their
  /// network on what they already have.
  ///
  /// A part whose audio the room answers is gone for good (its 404) leaves its number
  /// with no part, and the room's pass for that number is handed back, so a recording
  /// made there goes up above it.
  ///
  /// Null when the room could not hand the rehearsal over otherwise — another refusal of
  /// a part's audio, or the disk. Nothing is written for it: the resume point stays
  /// exactly as it was and the next opening tries again.
  Future<RoomAnswer<_PartesDaSala?>> _asPartesDaSala(
    String sessionId,
    List<TakeView> guardadas,
    List<KeptTake> aqui,
    int generation,
  ) async {
    final recorder = _recorder;
    final lidas = _lerAListagem(guardadas, aqui);
    final semParte = <int, int>{};
    var faltou = false;
    final partes = <KeptTake>[];
    for (final parte in lidas.partes) {
      if (!lidas.aBuscar.contains(parte.takeId)) {
        partes.add(parte);
        continue;
      }
      final String arquivo;
      switch (await _buscarAParte(sessionId, parte, _thisLife)) {
        case Answered(value: final kept?):
          arquivo = kept;
        case Refused(code: RefusalCode.notFound):
          faltou = true;
          if (KeptScope.numberOf(parte.scopeId) case final ordinal?) {
            semParte[ordinal] = parte.pass;
          }
          continue;
        case NetworkFailed() && final fell:
          return fell;
        case Answered() || Refused() || SessionGone():
          return const Answered(null);
      }
      if (_abandoned(generation)) {
        unawaited(recorder.delete(arquivo));
        return const Answered((
          partes: <KeptTake>[],
          inteiro: true,
          passadas: <int, int>{},
          deLado: <String>{},
        ));
      }
      partes.add(parte.at(arquivo));
    }
    return Answered((
      partes: partes,
      inteiro: !faltou,
      passadas: semParte,
      deLado: lidas.deLado,
    ));
  }

  static _AListagem _lerAListagem(
    List<TakeView> guardadas,
    List<KeptTake> aqui,
  ) {
    final correntes = _correntes(guardadas);
    final numeradas = correntes.keys.any((ordinal) => ordinal != null);
    final deLado = <String>{};
    final aBuscar = <String>{};
    final partes = <KeptTake>[];
    for (final MapEntry(key: ordinal, value: corrente) in correntes.entries) {
      final escopo = ordinal == null
          ? KeptScope.whole
          : KeptScope.parte(ordinal);
      final nossa = aqui
          .where((take) => take.takeId == corrente.takeId)
          .firstOrNull;
      if (ordinal == null && numeradas && nossa == null) {
        deLado.add(corrente.takeId);
        continue;
      }
      if (nossa == null) aBuscar.add(corrente.takeId);
      partes.add(
        KeptTake(
          scopeId: escopo,
          path: nossa?.path ?? '$escopo-${corrente.takeId}',
          takeId: corrente.takeId,
          pass: corrente.pass ?? 1,
          origin: corrente.origin,
        ),
      );
    }
    return (partes: partes, deLado: deLado, aBuscar: aBuscar);
  }

  /// One part's recording brought down from the room and kept on the tablet: its file, or
  /// null when it came empty or the disk could not keep it.
  Future<RoomAnswer<String?>> _buscarAParte(
    String sessionId,
    KeptTake parte,
    int? life,
  ) async {
    _watchBusyState();
    final clip = await _room.fetchClip(
      RoomRepository.takeAudioUrl(sessionId, parte.takeId!),
    );
    if (_endedSince(life)) return const Answered(null);
    switch (clip) {
      case Answered(:final value) when value.isNotEmpty:
        try {
          return Answered(
            await _recorder.keepBytes(
              value,
              '${parte.scopeId}-${parte.takeId}-${_stamp()}-${_random.nextInt(1 << 30)}',
            ),
          );
        } on Exception {
          return const Answered(null);
        }
      case Answered():
        return const Answered(null);
      case final RoomFailure failure:
        return failure;
    }
  }

  /// The parts on their way come down behind their rows, one at a time and in part order.
  /// The Resume point then names [ondeFicam] while the team is still on the Rehearsal with
  /// every part the room holds.
  void _bringThePartsDown(Station ondeFicam) {
    if (_partesDescendo case final descendo? when !descendo.isCompleted) return;
    final descem = Completer<void>();
    _partesDescendo = descem;
    unawaited(_asPartesDescem(descem, ondeFicam, _thisLife));
  }

  Future<void> _asPartesDescem(
    Completer<void> descem,
    Station ondeFicam,
    int? life,
  ) async {
    bool minha() => !_endedSince(life) && identical(_partesDescendo, descem);
    final recorder = _recorder;
    while (minha()) {
      final sessionId = state.sessionId;
      final parte = state.partes
          .where((take) => state.partsAway[take.takeId] == PartAway.coming)
          .firstOrNull;
      if (sessionId == null || parte == null) break;
      final busca = await _buscarAParte(sessionId, parte, life);
      final arquivo = switch (busca) {
        Answered(value: final kept?) => kept,
        _ => null,
      };
      final quanto = arquivo == null ? null : await _playback.howLong(arquivo);
      if (!minha() || !_aindaACaminho(sessionId, parte)) {
        if (arquivo != null) unawaited(recorder.delete(arquivo));
        continue;
      }
      final takeId = parte.takeId!;
      if (arquivo != null) {
        if (quanto != null) _marcarOFimDaParte(arquivo, quanto.inMilliseconds);
        state = state.copyWith(
          keptTakes: [
            for (final take in state.keptTakes)
              take.takeId == takeId ? take.at(arquivo) : take,
          ],
          partsAway: {...state.partsAway}..remove(takeId),
        );
      } else if (busca case Refused(code: RefusalCode.notFound)) {
        state = state.copyWith(
          partsAway: {...state.partsAway, takeId: PartAway.lost},
        );
        _asPartesPerdidasSaem();
      } else {
        state = state.copyWith(
          partsAway: {...state.partsAway, takeId: PartAway.missed},
        );
      }
      state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
      _weighTheRehearsal();
      _rememberWhereTheyAre(switch (state.station) {
        Ensaio() => _aLinhaDiz is Ensaio ? const Ensaio() : ondeFicam,
        final onde => onde,
      });
    }
    descem.complete();
  }

  /// The parts the room lost leave the Rehearsal once its Session read has said the team
  /// stays there; under the approved draft they stay, silent. True when one left.
  bool _asPartesPerdidasSaem() {
    if (!_aLeituraDecidiu || state.station is! Ensaio) return false;
    final perdidas = [
      for (final parte in state.partes)
        if (state.partsAway[parte.takeId] == PartAway.lost) parte,
    ];
    for (final parte in perdidas) {
      if (KeptScope.numberOf(parte.scopeId) case final ordinal?) {
        _passadasDaSala = {...?_passadasDaSala, ordinal: parte.pass};
      }
      final fora = state.partes.indexWhere(
        (take) => take.takeId == parte.takeId,
      );
      final regravando = state.parteARegravar;
      state = state.copyWith(
        keptTakes: [
          for (final take in state.keptTakes)
            if (take.takeId != parte.takeId) take,
        ],
        partsAway: {...state.partsAway}..remove(parte.takeId),
        btTrechos: _osTrechosSemAParte(fora),
        parteARegravar: switch (regravando) {
          final at? when at > fora => at - 1,
          _ => regravando,
        },
        clearParteARegravar: regravando == fora,
      );
    }
    if (perdidas.isEmpty) return false;
    state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
    _weighTheRehearsal();
    _rememberWhereTheyAre(const Ensaio());
    return true;
  }

  bool _aindaACaminho(String sessionId, KeptTake parte) =>
      state.sessionId == sessionId &&
      state.partsAway.containsKey(parte.takeId) &&
      state.keptTakes.any(
        (take) => take.takeId == parte.takeId && take.scopeId == parte.scopeId,
      );

  /// The stretches as they stand once the part at [fora] has left the parts: its own go
  /// with it, and each later one moves down to its part's new place (ADR 0022).
  List<Trecho> _osTrechosSemAParte(int fora) => [
    for (final trecho in state.btTrechos)
      if (trecho.parte != fora)
        trecho.parte < fora
            ? trecho
            : Trecho(
                segmentId: trecho.segmentId,
                takeId: trecho.takeId,
                retroPath: trecho.retroPath,
                parte: trecho.parte - 1,
                from: trecho.from,
                to: trecho.to,
                contado: trecho.contado,
                lugarFrom: trecho.lugarFrom,
                lugarTo: trecho.lugarTo,
                frase: trecho.frase,
              ),
  ];

  /// How long each part turned out to be, so the room knows where each part ends.
  ///
  /// A part nobody can measure ends the ruler rather than lengthening it by a guess, which
  /// is the ruler's rule everywhere, and it is not a reason to stop the team.
  Future<void> _medirAsPartes(List<KeptTake> partes, int generation) async {
    for (final parte in partes) {
      if (_tamanhoDaParteMs.containsKey(parte.path)) continue;
      _watchBusyState();
      final quanto = await _playback.howLong(parte.path);
      if (_abandoned(generation)) return;
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
    _leaveTheStepFor(const Retro());
    _arriveAt(const TheBackTranslationResumed());
    _regravouNestaVisita = false;
    final trechos = _trechosFrom(told.segments);
    final achados = _osAchadosQueFicam(told.findings, trechos);
    state = state.copyWith(
      awaitingTheGuide: false,
      btPhase: told.checked ? BtPhase.conferida : BtPhase.playing,
      btTrechos: trechos,
      btTrechosRegravados: const [],
      btFindings: achados,
      btVeredito: told.checked || achados.isNotEmpty,
      btFraseQueAguarda: told.awaitingSegmentId,
      clearBtFraseQueAguarda: told.awaitingSegmentId == null,
      btSoOuvir: false,
    );
    final sessionId = state.sessionId;
    if (sessionId != null) {
      unawaited(
        _porCadaTrechoNaSuaParte(
          sessionId,
          told.segments,
          _generation,
          regravados: told.stale,
        ),
      );
      unawaited(_lembrarDaFraseGuardada(sessionId));
    }
    if (told.checked) return;
    if (told.awaitingSegmentId case final aguardando?) {
      unawaited(_voltarAFraseQueAguarda(aguardando, _generation));
      return;
    }
    unawaited(_ouvirOQueFaltaDepoisDeRegravar(_generation));
  }

  Future<void> _voltarAFraseQueAguarda(
    String aguardando,
    int generation,
  ) async {
    await _medirAsPartes(state.partes, generation);
    if (_abandoned(generation)) return;
    state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
    await _sayALine(
      LineKind.guide,
      fixedLine: (name: sentenceAwaitingLine, language: _inTheSessionsLanguage),
    );
    if (_abandoned(generation)) return;
    _levarAoTrechoNaoTraduzido(aguardando);
  }

  /// A rehearsal picked back up remembers what of it was already told back.
  ///
  /// A team sent back to the rehearsal to record the end of the story leaves its resume
  /// point on the rehearsal, and the stretches it told stay the session's. Landing here
  /// without them, the next telling-back began at nought and sent the room every stretch
  /// a second time — the duplication the way back to the rehearsal exists to avoid, one
  /// leave-and-return later.
  void _keepTheStretchesAlreadyTold(BackTranslationProgress told) {
    state = state.copyWith(btTrechosRegravados: const []);
    final sessionId = state.sessionId;
    if (sessionId != null && told.stale.isNotEmpty) {
      unawaited(
        _porCadaTrechoNaSuaParte(
          sessionId,
          const [],
          _generation,
          regravados: told.stale,
        ),
      );
    }
    if (told.nothingTold) return;
    final trechos = _trechosFrom(told.segments);
    state = state.copyWith(
      btTrechos: trechos,
      btFindings: _osAchadosQueFicam(told.findings, trechos),
    );
  }

  void conversaTap() => _gesture(() => _conversaTap());

  void _conversaTap() {
    if (state.station is! Canvas) return;
    if (state.needsPerson) return;
    if (state.sessionId == null) {
      if (_emCurso case final passage? when !state.awaitingTheGuide) {
        _handOff(_enterAgain(passage)());
      }
      return;
    }
    if (state.noteMode) {
      _hand.noteTap();
      return;
    }
    switch (state.voice) {
      case VoiceState.invite:
      case VoiceState.listening:
      case VoiceState.done:
        _actOnConversaTap();
      case VoiceState.speaking:
        _cutTheVoice();
      case VoiceState.thinking:
        break;
    }
  }

  /// Where the Guide is is read before she stops.
  void _cutTheVoice() {
    if (ref.read(micPermissionProvider) != MicAccess.granted) return;
    final cut = CutPoint(_sound.linePosition, of: _sound.lineLength);
    _quietTheRoom();
    state = state.copyWith(clearContaEscolhida: true);
    _listen(Interrupted(take: 'conversa_${_stamp()}', cut: cut));
  }

  void _actOnConversaTap() {
    if (_recordingStarting) return;
    final isRecording = state.voice == VoiceState.listening;
    switch (_captureGuard.decide(
      isRecording: isRecording,
      elapsed: _listenedFor,
    )) {
      case TapDecision.start:
        _startListening('conversa_${_stamp()}');
      case TapDecision.stop:
        _handOff(_finishListening());
      case TapDecision.cancel:
        _dispatch(const MicDiscarded());
    }
  }

  void _startListening(
    String fileName, {
    MicOwner owner = MicOwner.conversation,
  }) {
    _silenceTheRoom();
    _listen(MicOpened(owner, take: fileName, generation: _generation));
  }

  void _listen(MachineEvent opening) {
    _recordingStarting = true;
    _listeningSince = clock.now();
    state = state.copyWith(peerCue: false);
    _dispatch(opening);
    if (state.channel is! Microphone) {
      _recordingStarting = false;
      return;
    }
    _keepTheConnectionWarm();
  }

  Duration get _listenedFor => _listeningSince == null
      ? Duration.zero
      : clock.now().difference(_listeningSince!);

  bool _theGuardKeeps(String path, Duration listenedFor) =>
      _captureGuard.accepts(duration: listenedFor, bytes: _bytesAt(path));

  bool _hasAudio(String path) => _bytesAt(path) > 0;

  int _bytesAt(String path) =>
      File(path).existsSync() ? File(path).lengthSync() : 0;

  bool _anAccidentalTap(String path) {
    final file = File(path);
    if (!file.existsSync()) return true;
    final wav = path.endsWith('.wav');
    try {
      return isAnAccidentalTap(
        wav: wav,
        head: wav ? _headOf(file) : Uint8List(0),
        length: file.lengthSync(),
      );
    } on FileSystemException {
      return false;
    }
  }

  Uint8List _headOf(File file) {
    final opened = file.openSync();
    try {
      return opened.readSync(_takeHead);
    } finally {
      opened.closeSync();
    }
  }

  void _keepTheConnectionWarm() {
    unawaited(_network.ping());
    final every = ref.read(connectionRewarmIntervalProvider);
    if (every == null) return;
    _after('warm', every, () {
      if (state.voice == VoiceState.listening) _keepTheConnectionWarm();
    });
  }

  Future<void> _finishListening() async {
    final generation = _waitOnTheGeneration;
    final listenedFor = _listenedFor;
    final turnClock = TurnClock()..mark('stop');
    final closed = await _closeTheMicrophone();
    final path = closed.take;
    turnClock.mark('recorder');
    if (_abandoned(generation)) return;
    final sessionId = state.sessionId;
    if (path == null || !_theGuardKeeps(path, listenedFor)) {
      // A take the guard would not have armed in the first place — too short, or too
      // light to be a real recording. Reading that as an ordinary return to the invite
      // is the same silence a phantom tap always deserved, never a fail-safe line.
      if (path != null) unawaited(_recorder.delete(path));
      state = state.copyWith(awaitingTheGuide: false);
      return;
    }
    if (sessionId == null) {
      unawaited(_recorder.delete(path));
      _theStepsNetworkFailed();
      return;
    }
    await _sendTheTurn(sessionId, path, _stamp(), turnClock, cut: closed.cut);
  }

  Future<void> _sendTheTurn(
    String sessionId,
    String path,
    String turnId,
    TurnClock turnClock, {
    CutPoint? cut,
  }) async {
    final generation = _waitOnTheGeneration;
    _sayImThinking();
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    void failed(RoomFailure failure) {
      if (_abandoned(generation)) return;
      _decideTheFailure(failure, rule: RefusalRule.aSpokenTurn);
    }

    final clientTiming = _pendingClock?.clientTiming(_clockSegments);
    _pendingClock = turnClock;
    await _sendATurn(
      Turn(sessionId, turnId),
      generation,
      () => _room.sendTurn(
        sessionId,
        File(path),
        turnId: turnId,
        clientTiming: clientTiming,
        cut: cut,
      ),
      play: (turn) => _voiceTurn(
        turn,
        generation,
        clock: turnClock,
        onSoundStart: () => turnClock.mark('sound'),
      ),
      failed: failed,
    );
  }

  void _warmHerLines() {
    for (final line in [
      ...instantAckLines,
      startLine,
      tellLine,
      unheardLine,
      approvedLine,
    ]) {
      unawaited(_voice.readyFixedLine(line, _inTheSessionsLanguage));
    }
  }

  void _sayImThinking() {
    _lastAcknowledgement = acknowledgementAfter(_lastAcknowledgement, _random);
    final line = instantAckLines[_lastAcknowledgement];
    unawaited(
      _sayALine(
        LineKind.acknowledgement,
        fixedLine: (name: line, language: _inTheSessionsLanguage),
      ),
    );
  }

  SalaSessionState get _current => state;

  set _current(SalaSessionState value) => state = value;

  void lookForReplies() => unawaited(_hand.pull());

  void handTap() => _gesture(_hand.tap);

  void devRecomecarPassagem() => _gesture(() => _devRecomecarPassagem());

  void _devRecomecarPassagem() {
    if (!Env.devPularFases) return;
    final passage = _emCurso;
    final pericope = passage?.pericope;
    if (passage == null || pericope == null) return;
    // The one discarded erasure that stays discarded: this is behind `devPularFases`, on
    // no team's path, and the entry it drops is rewritten by the fresh entry two lines
    // down. There is nobody here to speak to.
    final language = _sessionLanguage ?? _lingua;
    unawaited(
      _emAberto.forget(passage.book, pericope, language).catchError((_) {}),
    );
    _handOff(
      goConversa(
        book: passage.book,
        pericope: pericope,
        fresh: true,
        language: language,
      ),
    );
  }

  void chooseTheLanguage(String language) =>
      _gesture(() => _chooseTheLanguage(language));

  void _chooseTheLanguage(String language) {
    if (ref.read(roomLanguageProvider.notifier).choose(language)) {
      _dispatch(const TheLanguageChosen());
    }
  }

  void goEnsaio() => _gesture(() => _goEnsaio());

  void _goEnsaio() {
    _rememberWhereTheyAre(const Ensaio());
    _leaveTheStepFor(const Ensaio());
    _clearAll();
    _arriveAt(const TheRehearsalOpened());
    _asPartesPerdidasSaem();
    state = state.copyWith(
      awaitingTheGuide: false,
      ensaio: EnsaioStatus.idle,
      peerCue: false,
      clearBringBackFailed: true,
      btSoOuvir: false,
    );
    _readTheScenesForTheRehearsal();
    unawaited(_readWhatComesBack());
  }

  Future<void> _readWhatComesBack({int? laidOn}) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final generation = _generation;
    final life = _thisLife;
    final sent = ++_readsSent;
    final read = await _room.fetchState(sessionId);
    if (_endedSince(life) || _abandoned(generation)) return;
    if (read case Answered(value: final snapshot) when sent > _readsApplied) {
      _applyTheSessionRead(snapshot, sent);
      final told = snapshot.backTranslation;
      if (laidOn != null && !told.bringBack.contains(laidOn)) {
        state = state.copyWith(
          btTrechos: _trechosFrom(told.segments),
          clearBringBackFailed: true,
        );
      }
    }
  }

  void trazerDeVoltaAsTraducoes(int cena) =>
      _gesture(() => _trazerDeVolta(cena));

  void _trazerDeVolta(int cena) {
    final sessionId = state.sessionId;
    if (state.station is! Ensaio || sessionId == null) return;
    if (!state.toBringBack.contains(cena) ||
        state.bringingBack != null ||
        state.ensaio != EnsaioStatus.idle ||
        state.needsPerson) {
      return;
    }
    state = state.copyWith(clearBringBackFailed: true);
    _armedTap(
      'bringBack:$cena',
      needs: true,
      then: () => _handOff(_trazerDeVoltaNaSala(sessionId, cena)),
    );
  }

  Future<void> _trazerDeVoltaNaSala(String sessionId, int cena) async {
    final generation = _waitOnTheGeneration;
    final life = _thisLife;
    _silenceTheRoom();
    state = state.copyWith(bringingBack: cena);
    final sent = ++_readsSent;
    final answer = await _room.bringBackTheTranslations(sessionId, cena);
    if (_endedSince(life)) return;
    state = state.copyWith(clearBringingBack: true);
    if (_abandoned(generation)) return;
    switch (answer) {
      case Answered(value: final segmentos):
        _readsApplied = max(_readsApplied, sent);
        final segurada = state.btFraseGuardada ?? state.btRegravacao?.frase;
        if (segurada != null && _numeroDaParteDe(segurada) == cena) {
          _esquecerAFrase();
        }
        state = state.copyWith(
          btTrechos: _trechosFrom(segmentos),
          toBringBack: [...state.toBringBack]..remove(cena),
        );
      case final SessionGone gone:
        _decideAt(gone, door: Door.stretches);
      case final RoomFailure failure:
        state = state.copyWith(bringBackFailed: cena);
        _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
        unawaited(_readWhatComesBack(laidOn: cena));
    }
  }

  void openTheEnsaioFinal() => _gesture(() => _openTheEnsaioFinal());

  /// The orange dot: the recording home over a passage with a take that came from no
  /// join, otherwise the Ensaio Final plan while the room is read.
  void _openTheEnsaioFinal() {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        state.station is! Canvas ||
        state.machine.inFlight != null ||
        state.awaitingTheGuide ||
        state.orangeDotLook == OrangeDotLook.gone) {
      return;
    }
    if (state.partes.any((part) => part.origin == null)) {
      return _openTheRecordingHome(sessionId);
    }
    _openThePlan(sessionId);
  }

  /// The Ensaio Final plan, «pensando…» while the room is read.
  void _openThePlan(String sessionId) {
    const plan = Ensaio(step: EnsaioStep.plan);
    _plansOpened++;
    _leaveTheStepFor(plan);
    _clearAll();
    _arriveAt(const ThePlanOpened());
    state = state.copyWith(
      ensaioFinalPlan: const PlanAwaited(),
      planChoices: const {},
      joinRows: const {},
      clearJoining: true,
      clearPlanListening: true,
      clearPlanSheet: true,
      labelling: false,
      labelLine: false,
      rehearsalsElsewhere: false,
      peerCue: false,
    );
    _handOff(_readThePlan(sessionId));
  }

  /// The plan stands only over a passage the room says has scenes and whose every take,
  /// on the tablet, in the Outbox or in the room, came from a join, while a scene is left
  /// to join. A read that fails or has not answered within [planReadWait], a passage with
  /// no scenes and rehearsals only in the other language's session ask the grain while
  /// none is in force, and open that grain's recording home otherwise (ADR 0134).
  Future<void> _readThePlan(String sessionId) async {
    final generation = _waitOnTheGeneration;
    final known = state.scenesOfThePassage;
    final reads = (
      _takes.pending(),
      _room.takesListingOf(sessionId).then((listing) {
        if (listing case Answered(:final value) when !_abandoned(generation)) {
          _theRoomsGrainHeard(value);
          if (value.grain case final grain?
              when state.ensaioFinalPlan is GrainAsked &&
                  !state.grainSwitching) {
            _apart(() => _toTheGrainsHome(grain, sessionId));
          }
        }
        return listing;
      }),
      _room.sceneRehearsalsOf(sessionId),
      known == null ? _room.scenesOf(sessionId) : Future.value(Answered(known)),
    ).wait;
    (
      List<PendingTake>,
      RoomAnswer<TakesListing>,
      RoomAnswer<List<SceneRehearsalRecord>>,
      RoomAnswer<List<Scene>>,
    )?
    answered;
    final gate = Completer<void>();
    _after('planRead', planReadWait, gate.complete);
    await Future.any([reads.then((all) => answered = all), gate.future]);
    if (_abandoned(generation)) return;
    _timers.remove('planRead')?.cancel();
    final read = answered;
    if (read == null) return _theGrainOrItsHome(sessionId);
    final (outbox, takes, rehearsals, scenes) = read;
    for (final answer in [takes, rehearsals, scenes]) {
      if (answer case final SessionGone gone) return _decideTheFailure(gone);
    }
    final rows = [
      for (final entry in outbox)
        if (entry.sessionId == sessionId &&
            entry.kind == 'ensaio' &&
            (state.grain == null || state.rowOf(entry.scope) != null))
          entry,
    ];
    switch ((takes, rehearsals, scenes)) {
      case (Answered(value: TakesListing(takes: final guardadas)), _, _)
          when rows.any((row) => row.origin == null) ||
              _correntes(guardadas).entries.any(
                (corrente) =>
                    corrente.key == null || corrente.value.origin == null,
              ):
        state = state.copyWith(theRoomJoinedParts: _partesJuntadas(guardadas));
        _openTheRecordingHome(sessionId, listed: guardadas);
      case (
            Answered(value: TakesListing(takes: final guardadas)),
            Answered(value: final listed),
            _,
          )
          when _correntes(guardadas).isEmpty &&
              rows.isEmpty &&
              state.partes.isEmpty &&
              rehearsalsElsewhere(listed, sessionId):
        state = state.copyWith(rehearsalsElsewhere: true);
        _theGrainOrItsHome(sessionId, listed: guardadas, elsewhere: true);
      case (
            Answered(value: TakesListing(takes: final guardadas)),
            Answered(value: final listed),
            Answered(value: final passage),
          )
          when passage.isNotEmpty:
        final waiting = {
          for (final row in rows)
            if (!row.exhausted) ?KeptScope.numberOf(row.scope): row.origin!,
        };
        final read = PlanRead(
          rehearsals: listed,
          scenes: passage,
          joined: {
            for (final MapEntry(:key, :value) in _correntes(guardadas).entries)
              if ((key, value.origin) case (final n?, final origin?)) n: origin,
          }..removeWhere((n, _) => waiting.containsKey(n)),
          waiting: waiting,
        );
        if ((read.joined.isNotEmpty || read.waiting.isNotEmpty) &&
            !stillToJoin(read, sessionId, state.planChoices)) {
          state = state.copyWith(
            theRoomJoinedParts: _partesJuntadas(guardadas),
          );
          return _openTheRecordingHome(sessionId, listed: guardadas);
        }
        state = state.copyWith(
          ensaioFinalPlan: read,
          scenesOfThePassage: passage,
        );
      default:
        _theGrainOrItsHome(sessionId);
    }
  }

  void _theGrainOrItsHome(
    String sessionId, {
    List<TakeView>? listed,
    bool elsewhere = false,
  }) {
    if (state.grain != null) {
      return _openTheRecordingHome(sessionId, listed: listed);
    }
    state = state.copyWith(ensaioFinalPlan: GrainAsked(elsewhere: elsewhere));
  }

  /// «A passagem inteira» or «Cena por cena» on the grain choice.
  /// Over an approved draft it takes the Armed tap, whose second tap re-opens it.
  void chooseTheGrain(Grain grain) => _gesture(() {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        state.ensaioFinalPlan is! GrainAsked ||
        state.grainSwitching) {
      return;
    }
    _armedTap(
      'choose:${grain.wire}',
      needs: state.overAnApprovedDraft,
      then: () => _handOff(
        _switchTheGrain(
          grain,
          reopens: state.overAnApprovedDraft,
          then: () => _toTheGrainsHome(grain, sessionId),
        ),
      ),
    );
  });

  /// The whole-passage home, or the Ensaio Final plan read again on a new generation, so
  /// a read still in the air from before never decides over it.
  void _toTheGrainsHome(Grain grain, String sessionId) => switch (grain) {
    Grain.whole => _openTheRecordingHome(sessionId),
    Grain.scene => _openThePlan(sessionId),
  };

  bool get _aGrainControlActs =>
      state.sessionId != null &&
      state.station is Ensaio &&
      !state.grainSwitching &&
      state.ensaio == EnsaioStatus.idle &&
      state.joining == null &&
      !state.needsPerson &&
      !state.playPing;

  bool get _onThePlan => switch (state.station) {
    Ensaio(step: EnsaioStep.plan) => true,
    _ => false,
  };

  /// The recording home at the grain just switched to: opened from the plan, redrawn on
  /// the home.
  void _toItsHome() {
    if (_onThePlan) _openTheRecordingHome(state.sessionId!);
  }

  /// «gravar a passagem inteira de uma vez», on the plan and on a scene home over a
  /// joined recording.
  void recordTheWholePassage() => _gesture(() {
    if (!_aGrainControlActs || (state.recordsTheWhole && !_onThePlan)) return;
    _armedTap(
      'whole',
      needs: state.wholeSwitchArms,
      then: () => _handOff(
        _switchTheGrain(
          Grain.whole,
          reopens: state.overAnApprovedDraft,
          then: _toItsHome,
        ),
      ),
    );
  });

  /// Her plain «Gravar a passagem inteira» on a scene home no join touched: one tap.
  void recordTheWholePassageInstead() => _gesture(() {
    if (!_aGrainControlActs || _onThePlan || state.recordsTheWhole) return;
    _handOff(_switchTheGrain(Grain.whole, reopens: true, then: _toItsHome));
  });

  /// «Gravar cena por cena», on the plan and on the whole-passage home: one tap.
  void recordSceneByScene() => _gesture(() {
    if (!_aGrainControlActs ||
        state.planBusy ||
        !(_onThePlan || state.recordsTheWhole)) {
      return;
    }
    _handOff(_switchTheGrain(Grain.scene, reopens: true, then: _toItsHome));
  });

  /// «Ensaio Final: juntar os ensaios das cenas», over an empty whole recording.
  void joinTheScenesAgain() => _gesture(() {
    if (!_aGrainControlActs || !state.offersTheWayBackToTheJoin) return;
    _armedTap(
      'backToJoin',
      needs: state.overAnApprovedDraft,
      then: () => _handOff(
        _switchTheGrain(
          Grain.scene,
          reopens: state.overAnApprovedDraft,
          then: () => _openThePlan(state.sessionId!),
        ),
      ),
    );
  });

  /// Every grain control's one way through the room's grain door: nothing at the new
  /// grain happens before the door answered, and a door that fails changes nothing.
  Future<void> _switchTheGrain(
    Grain grain, {
    required bool reopens,
    required void Function() then,
  }) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    if (state.grainInForce == grain) return then();
    final generation = _waitOnTheGeneration;
    state = state.copyWith(grainSwitching: true);
    final answer = await _room.switchTheGrain(
      sessionId,
      grain,
      reopensTheApprovedDraft: reopens,
    );
    if (_gone) return;
    state = state.copyWith(grainSwitching: false);
    if (_abandoned(generation)) return;
    switch (answer) {
      case Answered(value: final listing):
        _theGrainSwitched(listing, grain);
        then();
      case final Refused refused when refused.code == RefusalCode.draftApproved:
        _decideAt(refused, rule: RefusalRule.passes);
        final sent = ++_readsSent;
        if (await _room.fetchState(sessionId) case Answered(
          value: final read,
        ) when !_abandoned(generation)) {
          _applyTheSessionRead(read, sent);
        }
      case final NetworkFailed failure:
        _decideAt(failure, rule: RefusalRule.passes);
        if (await _room.takesListingOf(sessionId) case Answered(
          value: final listing,
        ) when !_abandoned(generation)) {
          _theRoomsGrainHeard(listing);
          if (listing.grain == grain) then();
        }
      case final RoomFailure failure:
        _decideAt(failure, rule: RefusalRule.passes);
    }
  }

  /// The room's answer to a switch, read as any listing is.
  void _theGrainSwitched(TakesListing listing, Grain asked) =>
      _theRoomsGrainHeard(
        TakesListing(takes: listing.takes, grain: listing.grain ?? asked),
      );

  /// Whichever read tells it, the room's grain is the tablet's: on a new grain every take
  /// of the earlier one leaves the parts, a keep of it the Outbox could not take is set
  /// aside for good, and the telling-back starts over in silence. The Outbox keeps every
  /// row; the room sets a late one aside on arrival (ADR 0134).
  void _theRoomsGrainHeard(TakesListing listing) {
    final grain = listing.grain;
    if (grain == null) return;
    final newGrain = state.grain != grain;
    state = state.copyWith(grainInForce: grain);
    if (!newGrain) return;
    bool leftBehind(String scope) => switch (grain) {
      Grain.whole => KeptScope.isParte(scope),
      Grain.scene => scope == KeptScope.whole,
    };
    _notQueued[state.sessionId]?.removeWhere((scope, _) => leftBehind(scope));
    state = state.copyWith(
      keptTakes: [
        for (final take in state.keptTakes)
          if (!leftBehind(take.scopeId)) take,
      ],
      theRoomJoinedParts: _partesJuntadas(listing.takes),
      wholeHeldByTheRoom: grain == Grain.whole ? const {} : null,
      clearParteARegravar: true,
    );
    _theTellingStartsOver(const []);
    _weighTheRehearsal();
    unawaited(_countUnsent());
    if (state.station is Ensaio) _rememberWhereTheyAre(state.station);
  }

  /// The plan's read and this session, or null off the plan.
  (PlanRead, String)? get _thePlan => switch ((
    state.station,
    state.ensaioFinalPlan,
    state.sessionId,
  )) {
    (Ensaio(step: EnsaioStep.plan), final PlanRead read, final sessionId?) => (
      read,
      sessionId,
    ),
    _ => null,
  };

  /// The plan's rows as they stand, or null off the plan.
  List<PlanRow>? get _planRows => switch (_thePlan) {
    (final read, final sessionId) => planRowsOf(
      read,
      sessionId,
      state.planChoices,
    ),
    null => null,
  };

  PlanRow? _planRowOf(String sceneId) =>
      _planRows?.where((row) => row.scene.sceneId == sceneId).firstOrNull;

  /// «trocar o ensaio desta cena» opens the scene's Rehearsal sheet.
  void swapTheRehearsal(String sceneId) => _gesture(() {
    if (state.planBusy || !(_planRowOf(sceneId)?.canSwap ?? false)) return;
    _silenceThePlan();
    state = state.copyWith(planSheet: sceneId);
  });

  void closeTheRehearsalSheet() => _gesture(() {
    if (state.homeSheet != null) {
      if (state.homeBusy) return;
      _silenceTheRoom();
      state = state.copyWith(clearHomeSheet: true, clearSwapLine: true);
      return;
    }
    if (state.planBusy || _thePlan == null) return;
    _silenceThePlan();
    state = state.copyWith(clearPlanSheet: true);
  });

  /// «usar este»: the team's choice for the open sheet's scene, held for the visit, with
  /// no request.
  void useThisRehearsal(String rehearsalId) => _gesture(() {
    if (state.homeSheet case final sceneId?) {
      return _useAtHome(sceneId, rehearsalId);
    }
    final sceneId = state.planSheet;
    final row = sceneId == null ? null : _planRowOf(sceneId);
    if (sceneId == null ||
        row == null ||
        state.planBusy ||
        !row.candidates.any(
          (candidate) =>
              candidate.rehearsalId == rehearsalId &&
              row.offersToUse(candidate),
        )) {
      return;
    }
    _chooseTheRehearsal(sceneId, rehearsalId);
    _silenceThePlan();
    state = state.copyWith(clearPlanSheet: true);
  });

  (PlanRead, String)? get _theHomeRead => switch ((
    state.station,
    state.ensaioFinalPlan,
    state.sessionId,
  )) {
    (Ensaio(step: EnsaioStep.home), final PlanRead read, final sessionId?) => (
      read,
      sessionId,
    ),
    _ => null,
  };

  bool get _theHomeIsFree =>
      _theHomeRead != null &&
      !state.homeBusy &&
      state.ensaio == EnsaioStatus.idle &&
      !state.needsPerson;

  /// «trocar o ensaio desta cena» or «usar o ensaio desta cena» on Scene row [number]:
  /// its Rehearsal sheet over the recording home.
  void openTheHomeSheet(int number) => _gesture(() {
    final row = state.homeRows[number];
    if (!_theHomeIsFree ||
        row == null ||
        !(row.home.swap || row.home.useScene)) {
      return;
    }
    _silenceTheRoom();
    state = state.copyWith(
      homeSheet: row.plan.scene.sceneId,
      clearSwapLine: true,
    );
  });

  void _useAtHome(String sceneId, String rehearsalId) {
    final row = state.homeRows.values
        .where((row) => row.plan.scene.sceneId == sceneId)
        .firstOrNull;
    if (!_theHomeIsFree ||
        row == null ||
        !(row.home.swap || row.home.useScene)) {
      return;
    }
    final (:plan, :home) = row;
    final number = plan.number;
    final rehearsal = plan.candidates
        .where((r) => r.rehearsalId == rehearsalId && offersToSwapIn(home, r))
        .firstOrNull;
    if (rehearsal == null) return;
    final reopens = state.overAnApprovedDraft;
    _armedTap(
      swapControl(sceneId, rehearsal),
      needs: reopens || state.partIndexOf(number) != null,
      then: () => _handOff(_swapTheScene(number, rehearsal, reopens: reopens)),
    );
  }

  Future<void> _swapTheScene(
    int number,
    SceneRehearsalRecord rehearsal, {
    required bool reopens,
  }) async {
    final sessionId = state.sessionId!;
    final generation = _waitOnTheGeneration;
    final life = _thisLife;
    final id = rehearsal.rehearsalId;
    _silenceTheRoom();
    state = state.copyWith(swapping: id, clearSwapLine: true);
    try {
      final index = state.partIndexOf(number);
      final over = index == null ? null : state.partes[index].path;
      final (:written, :failed) = await _writeTheJoinRow(
        sessionId,
        number,
        rehearsal,
        generation,
        life,
        named: (pass) => 'parte-$number-junta-$id-$pass',
        above: index == null ? 0 : state.partes[index].pass,
        replacing: index == null ? null : state.partes[index].takeId,
        reopens: reopens,
      );
      if (_left(generation, life)) return;
      if (written == null) return _theSwapFailed(id, failed!);
      final (:row, :path, :pass) = written;
      final fate = await _watchTheRow(
        sessionId,
        (number: number, rehearsal: rehearsal, waiting: false),
        row.id,
        null,
        generation,
        life,
      );
      if (_left(generation, life)) return;
      if (fate.row == JoinRow.joined) {
        _semNome[row.id] = path;
        _thePartIsTheSwapped(number, path, pass, id);
        await _adoptTheNames(_takes, life);
        if (_left(generation, life)) return;
        return _theSwapLanded(path);
      }
      _theSwapFailed(id, fate.row);
      state = state.copyWith(clearSwapping: true);
      unawaited(_letGoOfTheSwap(written, number, id, over, generation, life));
      if (fate.row == JoinRow.notThePart) {
        if (_theHomeRead case (final read, _)) {
          await _thePartsTheRoomHolds(
            sessionId,
            read,
            generation,
            life,
            only: number,
          );
        }
      } else if (fate.row != JoinRow.cannotEnter) {
        await _readTheApprovedDraft(sessionId, generation);
      }
    } finally {
      if (!_endedSince(life)) state = state.copyWith(clearSwapping: true);
    }
  }

  Future<void> _letGoOfTheSwap(
    _JoinRowWritten written,
    int number,
    String origin,
    String? over,
    int generation,
    int? life,
  ) async {
    if (_gone) return;
    final (:row, :path, :pass) = written;
    final queue = _takes;
    _semNome.remove(row.id);
    await _theRequestInTheAirAnswers(queue, row);
    if (_gone) return;
    final landed = await queue.takeIdOf(row.id);
    if (_gone) return;
    if (landed == null ||
        _thePartAt(number)?.path != over ||
        !await _theRoomsPartIs(number, landed)) {
      if (!_gone && !state.keptTakes.any((take) => take.path == path)) {
        await _recorder.delete(path);
      }
      return;
    }
    if (_left(generation, life) ||
        !_thePartsMayMove ||
        _thePartAt(number)?.path != over) {
      return;
    }
    _semNome[row.id] = path;
    _thePartIsTheSwapped(number, path, pass, origin);
    await _adoptTheNames(_takes, life);
    if (!_left(generation, life)) _theSwapLanded(path);
  }

  KeptTake? _thePartAt(int number) => switch (state.partIndexOf(number)) {
    final index? => state.partes[index],
    null => null,
  };

  Future<bool> _theRoomsPartIs(int number, String takeId) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return false;
    final listing = await _room.takesOf(sessionId);
    if (_gone) return false;
    switch (listing) {
      case Answered(:final value):
        return _correntes(value)[number]?.takeId == takeId;
      case final SessionGone gone:
        _decideAt(gone, door: Door.sceneRehearsal);
        return false;
      case _:
        return false;
    }
  }

  Future<void> _theRequestInTheAirAnswers(
    TakeUploadQueue queue,
    PendingTake row,
  ) async {
    final withdrawn = Completer<void>();
    void withdraw() {
      if (!withdrawn.isCompleted) withdrawn.complete(queue.withdraw(row));
    }

    final watch = queue.rowsBack.where((id) => id == row.id).listen((_) {
      withdraw();
    });
    if (!queue.inTheAir(row.id)) withdraw();
    try {
      await withdrawn.future;
    } finally {
      await watch.cancel();
    }
  }

  Future<void> _theSwapsLeftBehind(
    String sessionId,
    PlanRead read,
    int generation,
    int? life,
  ) async {
    final left = [
      for (final row in await _takes.pending())
        if (row.sessionId == sessionId &&
            row.kind == 'ensaio' &&
            row.origin != null &&
            _aboveThePart(row))
          row,
    ];
    if (_left(generation, life) || !_thePartsMayMove) return;
    if (left.isEmpty &&
        !read.rehearsals.any((rehearsal) => rehearsal.sessionId == sessionId)) {
      return;
    }
    if (left.isNotEmpty) {
      await _withinTheJoinWait(_takes.flush());
      await _countUnsent();
      if (_left(generation, life)) return;
    }
    await _thePartsTheRoomHolds(sessionId, read, generation, life);
  }

  bool get _thePartsMayMove =>
      !state.homeBusy && state.ensaio == EnsaioStatus.idle;

  Future<void> _thePartsTheRoomHolds(
    String sessionId,
    PlanRead read,
    int generation,
    int? life, {
    int? only,
  }) async {
    final listing = await _room.takesOf(sessionId);
    if (_left(generation, life)) return;
    final List<TakeView> guardadas;
    switch (listing) {
      case Answered(:final value):
        guardadas = value;
      case final SessionGone gone:
        return _decideAt(gone, door: Door.sceneRehearsal);
      case _:
        return;
    }
    var adopted = false;
    for (final MapEntry(key: number, value: current) in _correntes(
      guardadas,
    ).entries) {
      final index = number == null ? null : state.partIndexOf(number);
      if (number == null ||
          index == null ||
          (only != null && number != only) ||
          state.unsentParts.containsKey(number) ||
          !_thePartsMayMove) {
        continue;
      }
      final part = state.partes[index];
      final pass = current.pass ?? 1;
      if (part.takeId == current.takeId ||
          (part.takeId == null && part.pass >= pass)) {
        continue;
      }
      final bytes = await _theBytesOf(sessionId, read, current);
      if (_left(generation, life)) return;
      if (bytes == null || !_thePartsMayMove) continue;
      final origin = current.origin;
      final path = await _recorder.keepBytes(
        bytes,
        origin == null
            ? 'parte-$number-${current.takeId}'
            : 'parte-$number-junta-$origin-$pass',
      );
      if (_left(generation, life) || !_thePartsMayMove) return;
      _thePartIsTheSwapped(number, path, pass, origin);
      state = state.copyWith(
        keptTakes: [
          for (final take in state.keptTakes)
            take.path == path ? take.withTakeId(current.takeId) : take,
        ],
      );
      unawaited(_medirAParteRegravada(path, _generation));
      adopted = true;
    }
    if (adopted) {
      _weighTheRehearsal();
      _rememberWhereTheyAre(const Ensaio());
      state = state.copyWith(hearNewScene: true);
      unawaited(_countUnsent());
    }
  }

  Future<Uint8List?> _theBytesOf(
    String sessionId,
    PlanRead read,
    TakeView take,
  ) async {
    final rehearsal = read.rehearsals
        .where((r) => r.rehearsalId == take.origin && r.sessionId == sessionId)
        .firstOrNull;
    if (rehearsal != null) {
      final (bytes, _) = await _theRehearsalsBytes(
        rehearsal,
        fromTheTablet: true,
      );
      return bytes;
    }
    final clip = await _withinTheJoinWait(
      _room.fetchClip(RoomRepository.takeAudioUrl(sessionId, take.takeId)),
    );
    switch (clip) {
      case Answered(:final value) when value.isNotEmpty:
        return value;
      case final SessionGone gone:
        _decideAt(gone, door: Door.sceneRehearsal);
        return null;
      case _:
        return null;
    }
  }

  bool _aboveThePart(PendingTake row) {
    final number = KeptScope.numberOf(row.scope);
    final index = number == null ? null : state.partIndexOf(number);
    return index != null && (row.passNumber ?? 0) > state.partes[index].pass;
  }

  void _theSwapFailed(String rehearsalId, JoinRow failed) {
    state = state.copyWith(
      swapLine: (
        rehearsalId: rehearsalId,
        cannotEnter: failed == JoinRow.cannotEnter,
      ),
    );
  }

  void _thePartIsTheSwapped(int number, String path, int pass, String? origin) {
    final scope = KeptScope.parte(number);
    if (state.partIndexOf(number) case final index?) {
      _aParteNoLugar(index, path, passada: pass, origin: origin);
    } else {
      final passadas = _passadasDaSala;
      if (passadas != null) {
        _passadasDaSala = _aindaPorGravar(passadas, {number});
      }
      state = state.copyWith(
        keptTakes: [
          ...state.keptTakes,
          KeptTake(scopeId: scope, path: path, pass: pass, origin: origin),
        ],
      );
      _deixarOInteiroDeLado();
    }
  }

  void _theSwapLanded(String path) {
    unawaited(_medirAParteRegravada(path, _generation));
    _weighTheRehearsal();
    _rememberWhereTheyAre(const Ensaio());
    state = state.copyWith(
      hearNewScene: true,
      clearHomeSheet: true,
      clearSwapLine: true,
    );
    _readTheRehearsalsAtHome();
    unawaited(_countUnsent());
  }

  void _readTheRehearsalsAtHome() {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        state.station != const Ensaio() ||
        state.scenes is! ScenesHad) {
      return;
    }
    unawaited(_theRehearsalsAtHome(sessionId));
  }

  Future<void> _theRehearsalsAtHome(String sessionId) async {
    final generation = _generation;
    final life = _thisLife;
    final answer = await _room.sceneRehearsalsOf(sessionId);
    if (_left(generation, life) || state.station != const Ensaio()) return;
    switch ((answer, state.scenes)) {
      case (Answered(:final value), ScenesHad(:final scenes)):
        final read = PlanRead(rehearsals: value, scenes: scenes);
        state = state.copyWith(ensaioFinalPlan: read);
        await _theSwapsLeftBehind(sessionId, read, generation, life);
      case (final SessionGone gone, _):
        _decideAt(gone, door: Door.sceneRehearsal);
      case _:
    }
  }

  /// A play button of the sheet or the card, on one of this session's rehearsals.
  void playARehearsal(String rehearsalId) => _gesture(() {
    final plan = _thePlan ?? _theHomeRead;
    if (plan == null || state.planBusy || state.homeBusy) return;
    final (read, sessionId) = plan;
    final record = read.rehearsals
        .where((r) => r.rehearsalId == rehearsalId && r.sessionId == sessionId)
        .firstOrNull;
    if (record == null) return;
    _handOff(_hearTheSceneRehearsal(record));
  });

  /// «gravar esta cena de novo»: the Scene rehearsal screen with the sheet's scene
  /// highlighted and the question still asked.
  void rehearseThisSceneAgain() => _gesture(() {
    final (sceneId, sessionId) = (state.planSheet, state.sessionId);
    if (sceneId == null ||
        sessionId == null ||
        _thePlan == null ||
        state.planBusy ||
        state.machine.inFlight != null ||
        state.awaitingTheGuide) {
      return;
    }
    _silenceThePlan();
    _hand.cancelQuestion();
    _openTheSceneScreen(sessionId, again: sceneId);
  });

  /// A tap on the card's «cena N»: the Scene label of the Unlabelled rehearsal it shows,
  /// one at a time.
  void labelTheRehearsal(String rehearsalId, String sceneId) => _gesture(() {
    final plan = _thePlan;
    if (plan == null || state.planBusy) return;
    final (read, sessionId) = plan;
    if (unlabelledRehearsalsOf(read, sessionId).firstOrNull?.rehearsalId !=
            rehearsalId ||
        !read.scenes.any((scene) => scene.sceneId == sceneId)) {
      return;
    }
    state = state.copyWith(labelling: true, labelLine: false);
    _handOff(_labelTheRehearsal(sessionId, rehearsalId, sceneId));
  });

  Future<void> _labelTheRehearsal(
    String sessionId,
    String rehearsalId,
    String sceneId,
  ) async {
    final generation = _waitOnTheGeneration;
    final answer = await _room.labelTheSceneRehearsal(
      sessionId,
      rehearsalId,
      scene: sceneId,
    );
    if (_abandoned(generation)) return;
    switch ((answer, state.ensaioFinalPlan)) {
      case (Answered(:final value), final PlanRead read):
        state = state.copyWith(ensaioFinalPlan: read.withRehearsal(value));
        _after(
          'labelWakes',
          ref.read(restartWakeProvider),
          () => state = state.copyWith(labelling: false),
        );
      case (Answered(), _):
        state = state.copyWith(labelling: false);
      case _:
        state = state.copyWith(labelling: false, labelLine: true);
    }
  }

  void _chooseTheRehearsal(String sceneId, String rehearsalId) {
    state = state.copyWith(
      planChoices: {...state.planChoices, sceneId: rehearsalId},
    );
  }

  void playThePlanRow(String sceneId) => _gesture(() {
    if (state.planBusy) return;
    final chosen = _planRowOf(sceneId)?.chosen;
    if (chosen != null) _handOff(_hearTheSceneRehearsal(chosen));
  });

  /// A play button of the plan: a second tap on the rehearsal being heard stops it, and
  /// only the newest tap is ever heard. A tap whose clip never sounds lets the next one
  /// play.
  Future<void> _hearTheSceneRehearsal(SceneRehearsalRecord rehearsal) async {
    final heard = state.planListening;
    _silenceThePlan();
    if (heard?.rehearsalId == rehearsal.rehearsalId) return;
    final asked = PlanListen(rehearsal.rehearsalId);
    state = state.copyWith(planListening: asked);
    final generation = _waitOnTheGeneration;
    bool stillAsked() => !_gone && identical(state.planListening, asked);
    final path = await _fetchTheSceneTake(
      rehearsal,
      () => _abandoned(generation) || !stillAsked(),
      generation,
    );
    void heardOut() {
      if (stillAsked()) state = state.copyWith(clearPlanListening: true);
    }

    if (path == null || _abandoned(generation) || !stillAsked()) {
      return heardOut();
    }
    _play(PartSound(0, path), onComplete: heardOut, onFailed: heardOut);
  }

  void _silenceThePlan() {
    _silenceTheRoom();
    state = state.copyWith(clearPlanListening: true);
  }

  void joinTheScenes() => _gesture(() {
    final rows = _planRows;
    if (rows == null || state.planBusy || !canJoin(rows)) return;
    _handOff(_joinTheScenesNow(rows));
  });

  void retryTheJoin(int number) => _gesture(() {
    final rows = _planRows;
    if (rows == null ||
        state.planBusy ||
        state.joinRows[number] != JoinRow.retry) {
      return;
    }
    _handOff(_joinTheScenesNow(rows));
  });

  /// «juntar as cenas e ouvir»: one scene at a time in passage order, stopping on the
  /// first row that says to try again; a join that went through closes the plan to the
  /// recording home, with the room's joined parts put under their rows.
  Future<void> _joinTheScenesNow(List<PlanRow> rows) async {
    final sessionId = state.sessionId!;
    final generation = _waitOnTheGeneration;
    final life = _thisLife;
    final plan = _plansOpened;
    _silenceThePlan();
    var parou = false;
    for (final step in joinQueue(rows)) {
      state = state.copyWith(
        joining: step.number,
        joinRows: {...state.joinRows, step.number: JoinRow.joining},
      );
      final joined = step.waiting
          ? await _watchTheWaitingPart(sessionId, step, generation, life)
          : await _joinTheScene(sessionId, step, generation, life);
      if (_left(generation, life)) {
        if (!_endedSince(life) && plan == _plansOpened) {
          state = state.copyWith(clearJoining: true);
        }
        return;
      }
      final read = state.ensaioFinalPlan;
      state = state.copyWith(
        joinRows: {...state.joinRows, step.number: joined.row},
        ensaioFinalPlan: read is PlanRead
            ? read.withThePart(
                step.number,
                step.rehearsal.rehearsalId,
                joined.part,
              )
            : read,
      );
      if (joined.row == JoinRow.retry) {
        state = state.copyWith(clearJoining: true);
        return;
      }
      if (joined.row == JoinRow.notThePart) {
        parou = true;
        break;
      }
    }
    state = state.copyWith(clearJoining: true);
    _goEnsaio();
    final home = _generation;
    await _layInTheRoomsListing(sessionId, null, home);
    if (_abandoned(home) || _endedSince(life)) return;
    if (!parou && state.everySceneHasItsPart) _startRetro();
  }

  /// One scene's join: the rehearsal's bytes, kept as the part's own file, written as an
  /// Outbox row under the rehearsal's fingerprint above every pass the room holds for the
  /// part, and watched to its landing.
  Future<JoinOutcome> _joinTheScene(
    String sessionId,
    JoinStep step,
    int generation,
    int? life,
  ) async {
    final (:number, :rehearsal, waiting: _) = step;
    final id = rehearsal.rehearsalId;
    final (:written, :failed) = await _writeTheJoinRow(
      sessionId,
      number,
      rehearsal,
      generation,
      life,
      named: (_) => 'parte-$number-junta-$id',
    );
    if (_left(generation, life)) return _joinLeftBehind;
    if (written == null) return (row: failed!, part: JoinedPart.nowhere);
    final (:row, :path, :pass) = written;
    final scope = KeptScope.parte(number);
    state = state.copyWith(
      keptTakes: [
        for (final take in state.keptTakes)
          if (take.scopeId != scope || take.origin == null) take,
        KeptTake(scopeId: scope, path: path, pass: pass, origin: id),
      ],
    );
    _rememberWhereTheyAre(const Canvas());
    unawaited(_countUnsent());
    return _watchTheRow(sessionId, step, row.id, path, generation, life);
  }

  Future<({_JoinRowWritten? written, JoinRow? failed})> _writeTheJoinRow(
    String sessionId,
    int number,
    SceneRehearsalRecord rehearsal,
    int generation,
    int? life, {
    required String Function(int pass) named,
    int above = 0,
    String? replacing,
    bool reopens = false,
  }) async {
    const leftBehind = (written: null, failed: null);
    var fromTheTablet = true;
    while (true) {
      final (bytes, refused) = await _theRehearsalsBytes(
        rehearsal,
        fromTheTablet: fromTheTablet,
      );
      if (_left(generation, life)) return leftBehind;
      if (bytes == null) return (written: null, failed: refused);
      final stands = await _wherePartStands(sessionId, number);
      if (_left(generation, life)) return leftBehind;
      if (stands == null) return (written: null, failed: JoinRow.retry);
      final pass = max(stands.pass, above + 1);
      final String partPath;
      final PendingTake? row;
      try {
        partPath = await _recorder.keepBytes(bytes, named(pass));
        row = await _takes.enqueueTheJoin(
          File(partPath),
          sessionId: sessionId,
          number: number,
          passNumber: pass,
          origin: rehearsal.rehearsalId,
          fingerprint: rehearsal.sha256,
          reopensTheApprovedDraft: reopens,
          overTake: replacing ?? stands.live,
        );
      } on Exception {
        return (written: null, failed: JoinRow.retry);
      }
      if (_left(generation, life)) return leftBehind;
      if (row == null) {
        await _recorder.delete(partPath);
        if (!fromTheTablet) return (written: null, failed: JoinRow.cannotEnter);
        fromTheTablet = false;
        continue;
      }
      _rowsOfThisVisit.add(row.id);
      _semNome[row.id] = partPath;
      return (written: (row: row, path: partPath, pass: pass), failed: null);
    }
  }

  /// One pass above the highest the room lists for the part as the row is written, and
  /// above every pass this tablet already knew of; and the take the room lists as the
  /// part then, the one the row replaces. None when the room does not list its takes.
  Future<({int pass, String? live})?> _wherePartStands(
    String sessionId,
    int number,
  ) async {
    final known = _passadasDaSala?[number] ?? 0;
    final listing = await _withinTheJoinWait(_room.takesOf(sessionId));
    final guardadas = switch (listing) {
      Answered(:final value) => value,
      _ => null,
    };
    if (guardadas == null) return null;
    return (
      pass: max(known, _passadasMaisAltas(guardadas)[number] ?? 0) + 1,
      live: _correntes(guardadas)[number]?.takeId,
    );
  }

  /// A joined part an earlier try left in the Outbox: sent again now, and watched. Gone
  /// from the Outbox, it landed only if the room says the part is that rehearsal's;
  /// with no part in the room at all, the scene is joined again from the start.
  Future<JoinOutcome> _watchTheWaitingPart(
    String sessionId,
    JoinStep step,
    int generation,
    int? life,
  ) async {
    final scope = KeptScope.parte(step.number);
    final row = (await _takes.pending())
        .where(
          (entry) =>
              entry.sessionId == sessionId &&
              entry.scope == scope &&
              entry.origin != null,
        )
        .lastOrNull;
    if (_left(generation, life)) return _joinLeftBehind;
    final partPath = state.partes
        .where((take) => take.scopeId == scope)
        .firstOrNull
        ?.path;
    if (row != null) {
      if (!row.exhausted) await _takes.dueAgain(row.id);
      return _watchTheRow(sessionId, step, row.id, partPath, generation, life);
    }
    final listing = await _withinTheJoinWait(_room.takesOf(sessionId));
    if (_left(generation, life)) return _joinLeftBehind;
    final guardadas = switch (listing) {
      Answered(:final value) => value,
      _ => null,
    };
    if (guardadas == null) return _givenUpWaiting;
    return switch (_correntes(guardadas)[step.number]) {
      null => _joinTheScene(sessionId, step, generation, life),
      final current when current.origin == step.rehearsal.rehearsalId => (
        row: JoinRow.joined,
        part: JoinedPart.landed,
      ),
      _ => _notThePart(partPath),
    };
  }

  /// The rehearsal's bytes: this tablet's file when [fromTheTablet] and it holds one,
  /// else its audio door's, within [joinAnswerWait]. A recording gone from the room
  /// cannot enter; any other failure says to try again.
  Future<(Uint8List?, JoinRow?)> _theRehearsalsBytes(
    SceneRehearsalRecord rehearsal, {
    required bool fromTheTablet,
  }) async {
    final held = fromTheTablet
        ? await _heldOnTheTablet('cena-${rehearsal.rehearsalId}')
        : null;
    if (held != null) {
      try {
        return (await File(held).readAsBytes(), null);
      } on FileSystemException {
        return _theRehearsalsBytes(rehearsal, fromTheTablet: false);
      }
    }
    final clip = await _withinTheJoinWait(
      _room.fetchClip(
        RoomRepository.sceneRehearsalAudioUrl(
          rehearsal.sessionId,
          rehearsal.rehearsalId,
        ),
      ),
    );
    if (clip case final SessionGone gone) {
      _decideAt(gone, door: Door.sceneRehearsal);
    }
    return switch (clip) {
      Answered(:final value) when value.isNotEmpty => (value, null),
      Answered() ||
      Refused(code: RefusalCode.notFound) => (null, JoinRow.cannotEnter),
      _ => (null, JoinRow.retry),
    };
  }

  /// A join row flushed until it lands. A request of the row's own that has no answer
  /// within [joinAnswerWait] says to try again; a room that asks it to wait is asked
  /// again every [joinQuietPause] until [joinQuietWait] after its first wait; a refusal
  /// that names the rehearsal as not this part's says it cannot enter.
  Future<JoinOutcome> _watchTheRow(
    String sessionId,
    JoinStep step,
    String rowId,
    String? partPath,
    int generation,
    int? life,
  ) async {
    DateTime? firstWait;
    while (true) {
      final leaving = Completer<void>();
      final back = Completer<int>();
      final watching = [
        _takes.rowsLeaving.where((id) => id == rowId).listen((_) {
          if (!leaving.isCompleted) leaving.complete();
        }),
        _takes.rowsBack.where((id) => id == rowId).listen((_) {
          if (!back.isCompleted) back.complete(0);
        }),
      ];
      if (_takes.inTheAir(rowId)) leaving.complete();
      var watched = true;
      final flushed = await _withinTheJoinWait(
        Future.any([
          _takes.flush().then(
            (_) => back.isCompleted || !watched ? 0 : _takes.flush(),
          ),
          back.future,
        ]),
        from: leaving.future,
      );
      watched = false;
      for (final watch in watching) {
        await watch.cancel();
      }
      if (_left(generation, life)) return _joinLeftBehind;
      if (flushed == null) return _givenUpWaiting;
      await _adoptTheNames(_takes, life);
      if (await _takes.takeIdOf(rowId) case final landed?) {
        return _thePartItLandedAs(sessionId, step.number, landed, partPath);
      }
      final row = (await _takes.pending())
          .where((entry) => entry.id == rowId)
          .firstOrNull;
      if (_left(generation, life)) return _joinLeftBehind;
      if (row == null) {
        if (!_takes.movedAway(rowId)) {
          return (row: JoinRow.retry, part: JoinedPart.nowhere);
        }
        _semNome.remove(rowId);
        return _notThePart(partPath);
      }
      if (row.exhausted) {
        await _takes.withdraw(row);
        _semNome.remove(rowId);
        _letGoOfTheJoinedPart(partPath);
        return (
          row: switch (row.refusal) {
            RefusalCode.unknownReference ||
            RefusalCode.takeFingerprintDiffers => JoinRow.cannotEnter,
            _ => JoinRow.retry,
          },
          part: JoinedPart.nowhere,
        );
      }
      if (!back.isCompleted) return _givenUpWaiting;
      final waited = firstWait ??= clock.now();
      if (clock.now().difference(waited) >= joinQuietWait) {
        return _givenUpWaiting;
      }
      final pause = Completer<void>();
      _after('joinPause', joinQuietPause, pause.complete);
      await pause.future;
      await _takes.dueAgain(rowId);
      if (_left(generation, life)) return _joinLeftBehind;
    }
  }

  /// The room answers the take it already holds for the same bytes, whatever part it is
  /// now: a part recorded again by hand since keeps its place, and the join lands
  /// nothing.
  Future<JoinOutcome> _thePartItLandedAs(
    String sessionId,
    int number,
    String landed,
    String? partPath,
  ) async {
    final listing = await _room.takesOf(sessionId);
    if (listing case Answered(
      value: final guardadas,
    ) when _correntes(guardadas)[number]?.takeId != landed) {
      return _notThePart(partPath);
    }
    return (row: JoinRow.joined, part: JoinedPart.landed);
  }

  JoinOutcome _notThePart(String? partPath) {
    _letGoOfTheJoinedPart(partPath);
    return (row: JoinRow.notThePart, part: JoinedPart.nowhere);
  }

  void _letGoOfTheJoinedPart(String? partPath) {
    if (partPath == null) return;
    state = state.copyWith(
      keptTakes: [
        for (final take in state.keptTakes)
          if (take.path != partPath) take,
      ],
    );
    _rememberWhereTheyAre(const Canvas());
    unawaited(_recorder.delete(partPath));
  }

  /// The team recorded the part again by hand: a join of it still in the Outbox would
  /// land later and take the part's place.
  Future<void> _withdrawTheJoinsOf(int number) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    await _takes.withdrawTheJoinsOf(sessionId, KeptScope.parte(number));
  }

  bool _left(int generation, int? life) =>
      _abandoned(generation) || _endedSince(life);

  /// [work]'s answer, or null when it has not come within [joinAnswerWait] of [from].
  Future<T?> _withinTheJoinWait<T>(Future<T> work, {Future<void>? from}) async {
    T? answered;
    var done = false;
    Timer? mine;
    final gate = Completer<void>();
    void arm() {
      if (done) return;
      _after('joinAnswer', joinAnswerWait, gate.complete);
      mine = _timers['joinAnswer'];
    }

    if (from == null) {
      arm();
    } else {
      unawaited(from.then((_) => arm()));
    }
    await Future.any([work.then((value) => answered = value), gate.future]);
    done = true;
    if (mine != null && identical(_timers['joinAnswer'], mine)) {
      _timers.remove('joinAnswer')?.cancel();
    }
    return answered;
  }

  /// The recording home the orange dot leads to, opened at once, with the room's listing
  /// laid in behind its rows.
  void _openTheRecordingHome(String sessionId, {List<TakeView>? listed}) {
    _goEnsaio();
    _handOff(_layInTheRoomsListing(sessionId, listed, _waitOnTheGeneration));
  }

  /// The parts the room holds for numbers the tablet has none of go under their rows as
  /// they arrive, and a part recorded again goes up above every pass the room holds for
  /// it, whether or not its audio could be fetched.
  Future<void> _layInTheRoomsListing(
    String sessionId,
    List<TakeView>? listed,
    int generation,
  ) async {
    var guardadas = listed;
    if (guardadas == null) {
      final listing = await _room.takesListingOf(sessionId);
      if (listing case final SessionGone gone when !_abandoned(generation)) {
        return _decideTheFailure(gone);
      }
      if (listing case Answered(:final value)) {
        guardadas = value.takes;
        if (!_abandoned(generation)) _theRoomsGrainHeard(value);
      }
    }
    if (guardadas == null) return;
    if (_abandoned(generation)) return;
    final held = state.partNumbers;
    final standing = _theRowsStanding;
    final altas = _passadasMaisAltas(guardadas);
    _passadasDaSala = _aindaPorGravar({
      ...?_passadasDaSala,
      for (final MapEntry(:key, :value) in altas.entries)
        key: max(value, _passadasDaSala?[key] ?? 0),
    }, held);
    if (held.isNotEmpty) {
      if (_correntes(guardadas)[null] case final inteiro?) {
        state = state.copyWith(
          wholeHeldByTheRoom: {...state.wholeHeldByTheRoom, inteiro.takeId},
        );
      }
    }
    final faltam = [
      for (final guardada in guardadas)
        if (switch (guardada.ordinal) {
          final ordinal? => !standing.contains(ordinal),
          null => standing.isEmpty,
        })
          guardada,
    ];
    if (await _asPartesDaSala(sessionId, faltam, const [], generation)
        case Answered(value: final laid?)) {
      if (_abandoned(generation)) return;
      final agora = _theRowsStanding;
      final novas = [
        for (final parte in laid.partes)
          if (!agora.contains(state.rowOf(parte.scopeId))) parte,
      ];
      if (novas.isEmpty && laid.deLado.isEmpty) return;
      await _medirAsPartes(novas, generation);
      if (_abandoned(generation)) return;
      state = state.copyWith(
        keptTakes: [...state.keptTakes, ...novas],
        wholeHeldByTheRoom: {...state.wholeHeldByTheRoom, ...laid.deLado},
      );
      state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
      _passadasDaSala = _aindaPorGravar(
        _passadasDaSala ?? const {},
        state.partNumbers,
      );
      _weighTheRehearsal();
      _rememberWhereTheyAre(const Ensaio());
    }
  }

  Set<int> get _theRowsStanding => {
    for (final parte in state.partes) ?state.rowOf(parte.scopeId),
  };

  void openTheSceneRehearsal() => _gesture(() => _openTheSceneRehearsal());

  void _openTheSceneRehearsal() {
    final sessionId = state.sessionId;
    if (sessionId == null ||
        state.station is! Canvas ||
        state.machine.inFlight != null ||
        state.awaitingTheGuide) {
      return;
    }
    _silenceTheRoom();
    _hand.cancelQuestion();
    _openTheSceneScreen(sessionId);
  }

  void _openTheSceneScreen(String sessionId, {String? again}) {
    _arriveAt(const TheSceneRehearsalOpened());
    _timers.remove('sceneListRetry')?.cancel();
    state = state.copyWith(
      scene: SceneScreen(again: again),
      scenes: const ScenesAwaited(),
      clearSceneRestart: true,
      clearSceneLine: true,
    );
    _handOff(_openTheScreen(sessionId, reopensTheUnsent: again == null));
  }

  /// The record step shows nothing until this session's rehearsals and the scene list
  /// have answered, or [sceneListWait] has passed since the open. A list that answers
  /// later is still taken.
  Future<void> _openTheScreen(
    String sessionId, {
    required bool reopensTheUnsent,
  }) async {
    final generation = _waitOnTheGeneration;
    final first = _room.scenesOf(sessionId);
    RoomAnswer<List<Scene>>? answered;
    final gate = Completer<void>();
    _after('sceneList', sceneListWait, gate.complete);
    await Future.any([
      Future.wait([
        _reopenTheUnsent(sessionId, reopensTheUnsent: reopensTheUnsent),
        first.then((answer) => answered = answer),
      ]),
      gate.future,
    ]);
    if (_abandoned(generation)) return;
    _timers.remove('sceneList')?.cancel();
    final answer = answered;
    if (answer == null) {
      _theScenesMissed(0);
      unawaited(first.then((late) => _theScenesAnswered(late, generation)));
    } else if (!_theScenesAnswered(answer, generation)) {
      _theScenesMissed(0);
    }
  }

  bool _theScenesAnswered(RoomAnswer<List<Scene>> answer, int generation) {
    if (_abandoned(generation)) return false;
    switch (answer) {
      case Answered(:final value):
        if (state.scenes is! ScenesHad) {
          state = state.copyWith(
            scenes: ScenesHad(value),
            scenesOfThePassage: value,
          );
          _stampTheQuestion();
          _weighTheRehearsal();
          _readTheRehearsalsAtHome();
        }
        return true;
      case final RoomFailure failure:
        _decideAt(failure, door: Door.sceneList);
        return false;
    }
  }

  bool get _readsTheScenes =>
      state.station is SceneRehearsal || state.station is Ensaio;

  /// The Rehearsal draws one row per Scene, so it reads the passage's scenes on every
  /// arrival until the room has answered them.
  void _readTheScenesForTheRehearsal() {
    _weighTheRehearsal();
    unawaited(_countUnsent());
    _readTheRehearsalsAtHome();
    if (state.scenes is ScenesHad) return;
    _timers.remove('sceneListRetry')?.cancel();
    unawaited(_askForTheScenes(onMiss: () => _theScenesMissed(0)));
  }

  /// The Rehearsal opens the Back-translation only as the machine last weighed it, so it
  /// is weighed again whenever its parts or its scene list change.
  void _weighTheRehearsal() {
    if (state.station
        case Ensaio(:final everySceneHasItsPart, :final everyPartIsHere)
        when everySceneHasItsPart != state.everySceneHasItsPart ||
            everyPartIsHere != state.everyPartIsHere) {
      _dispatch(
        TheRehearsalWeighed(
          everySceneHasItsPart: state.everySceneHasItsPart,
          everyPartIsHere: state.everyPartIsHere,
        ),
      );
    }
  }

  void _theScenesMissed(int asked) {
    if (!_readsTheScenes || state.scenes is ScenesHad) return;
    if (state.scenesOfThePassage case final known?) {
      state = state.copyWith(scenes: ScenesHad(known));
      _stampTheQuestion();
      _weighTheRehearsal();
      _readTheRehearsalsAtHome();
      return;
    }
    state = state.copyWith(scenes: const ScenesMissing());
    final wait = sceneListRetryWait(asked);
    if (wait == null) return;
    _after('sceneListRetry', wait, () => _askForTheScenesAgain(asked, wait));
  }

  /// [asked] is how many retries the list has spent; [wait] is the one now due.
  void _askForTheScenesAgain(int asked, Duration wait) {
    final asks = switch (state.station) {
      Ensaio() => true,
      SceneRehearsal() => state.scene.step == SceneStep.record,
      _ => false,
    };
    if (!asks || state.scenes is! ScenesMissing) return;
    if (state.sceneTakeUnderWay) {
      _after('sceneListRetry', wait, () => _askForTheScenesAgain(asked, wait));
      return;
    }
    unawaited(_askForTheScenes(onMiss: () => _theScenesMissed(asked + 1)));
  }

  Future<void> _askForTheScenes({VoidCallback? onMiss}) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final generation = _waitOnTheGeneration;
    final answer = await _room.scenesOf(sessionId);
    if (!_theScenesAnswered(answer, generation) && !_abandoned(generation)) {
      onMiss?.call();
    }
  }

  /// A question that comes on screen sleeps [sceneWake] from now.
  /// A screen that waits on a call is never replaced; it is stamped when the wait ends.
  void _stampTheQuestion() {
    if (!state.sceneQuestionShown ||
        state.scene.waiting ||
        state.scene.askedAt != null) {
      return;
    }
    state = state.copyWith(scene: state.scene.copyWith(askedAt: clock.now()));
  }

  bool _asleep(DateTime? since) => asleepAt(clock.now(), since: since);

  bool _theSceneMovedOn(SceneScreen asked, int generation) =>
      _abandoned(generation) ||
      !identical(state.scene, asked) ||
      state.channel is Microphone;

  /// A take waiting in the Outbox always comes back to the screen; the room's newest
  /// unsent rehearsal only when [reopensTheUnsent], never for a scene asked again.
  Future<void> _reopenTheUnsent(
    String sessionId, {
    required bool reopensTheUnsent,
  }) async {
    final generation = _waitOnTheGeneration;
    var asked = state.scene;
    final waiting = await _takes.sceneWaitingIn(sessionId);
    if (waiting != null) {
      if (_theSceneMovedOn(asked, generation)) return;
      state = state.copyWith(
        scene: SceneScreen(
          label: waiting.scene,
          picked: waiting.scene,
          keep: NotKept(
            row: waiting.id,
            tooLarge: _tooLargeForTheRoom(waiting.path),
          ),
        ),
      );
      asked = state.scene;
    }
    final listed = await _room.sceneRehearsalsOf(sessionId);
    switch (listed) {
      case Answered(:final value):
        if (_abandoned(generation) || state.station is! SceneRehearsal) return;
        state = state.copyWith(
          sceneRehearsals: SceneRehearsalRecord.listedOver(
            state.sceneRehearsals,
            value,
            sessionId,
          ),
        );
        final unsent = SceneRehearsalRecord.toReopen(
          state.sceneRehearsals,
          sessionId,
        );
        if (waiting != null ||
            unsent == null ||
            !reopensTheUnsent ||
            _theSceneMovedOn(asked, generation)) {
          return;
        }
        final take = await _fetchTheSceneTake(
          unsent,
          () => _theSceneMovedOn(asked, generation),
          generation,
        );
        if (take == null || state.scenes is! ScenesAwaited) return;
        await _showTheRehearsal(
          unsent,
          asked,
          generation,
          take: take,
          whileTheOpenWaits: true,
        );
      case final RoomFailure failure:
        if (!_abandoned(generation)) {
          _decideAt(failure, door: Door.sceneRehearsal);
        }
    }
  }

  Future<void> _showTheRehearsal(
    SceneRehearsalRecord rehearsal,
    SceneScreen asked,
    int generation, {
    String? take,
    bool whileTheOpenWaits = false,
  }) async {
    final here =
        take ??
        (asked.rehearsal?.rehearsalId == rehearsal.rehearsalId
            ? asked.take
            : null) ??
        await _fetchTheSceneTake(
          rehearsal,
          () => _theSceneMovedOn(asked, generation),
          generation,
        );
    if (here == null || _theSceneMovedOn(asked, generation)) return;
    final length = await _playback.howLong(here);
    if (_theSceneMovedOn(asked, generation) ||
        (whileTheOpenWaits && state.scenes is! ScenesAwaited)) {
      return;
    }
    final step = switch (rehearsal) {
      SceneRehearsalRecord(unsent: false) => SceneStep.sent,
      _ when rehearsal.placesKnownIn(length) => SceneStep.translate,
      _ => SceneStep.placesUnknown,
    };
    final stillTranslating =
        step == SceneStep.translate &&
        asked.step == SceneStep.translate &&
        asked.rehearsal?.rehearsalId == rehearsal.rehearsalId;
    final pausa = stillTranslating ? asked.pausa : null;
    final armed = stillTranslating ? asked.translatingAgain : null;
    final stillArmed = rehearsal.currentFrases
        .where((frase) => frase.fraseId == armed?.fraseId)
        .firstOrNull;
    final herLineStands = stillArmed != null && asked.notUnderstood;
    final floor = rehearsal.pausaFloor(stillArmed);
    if (armed != null && stillArmed == null) _silenceTheRoom();
    state = state.copyWith(
      scene: SceneScreen(
        step: step,
        rehearsal: rehearsal,
        take: here,
        length: length,
        listened: stillTranslating && asked.listened,
        pausa: pausa != null && pausa > floor ? pausa : null,
        translatingAgain: stillArmed,
        notUnderstood: herLineStands,
      ),
      sceneRehearsals: _listedWith(rehearsal),
    );
    if (step == SceneStep.translate) _handOff(_readTheLoudness(here));
  }

  Future<void> _readTheLoudness(String take) async {
    if (state.sceneLoudness?.take == take) return;
    final life = _thisLife;
    final envelope = await ref.read(sceneEnvelopeReaderProvider)(take);
    if (_endedSince(life) || state.scene.take != take) return;
    state = state.copyWith(sceneLoudness: (take: take, envelope: envelope));
  }

  Envelope? _envelopeOf(String path) => _envelopes.putIfAbsent(path, () {
    try {
      return envelopeOf(File(path).readAsBytesSync());
    } on FileSystemException {
      return null;
    }
  });

  List<SceneRehearsalRecord> _listedWith(SceneRehearsalRecord rehearsal) =>
      SceneRehearsalRecord.ofTheSession([
        for (final row in state.sceneRehearsals)
          if (row.rehearsalId != rehearsal.rehearsalId) row,
        rehearsal,
      ], rehearsal.sessionId);

  Future<String?> _fetchTheSceneTake(
    SceneRehearsalRecord rehearsal,
    bool Function() movedOn,
    int generation,
  ) => _fetchASceneClip(
    'cena-${rehearsal.rehearsalId}',
    RoomRepository.sceneRehearsalAudioUrl(
      rehearsal.sessionId,
      rehearsal.rehearsalId,
    ),
    movedOn,
    generation,
  );

  Future<String?> _fetchASceneClip(
    String name,
    String url,
    bool Function() movedOn,
    int generation,
  ) async {
    final held = await _heldOnTheTablet(name);
    if (held != null || _abandoned(generation)) return held;
    final clip = await _room.fetchClip(url);
    if (_abandoned(generation)) return null;
    switch (clip) {
      case Answered(:final value) when value.isNotEmpty:
        try {
          return await _recorder.keepBytes(value, name);
        } on Exception {
          if (!movedOn()) {
            _dispatch(
              decidedOnTheTablet(
                const TheDiskFailed(),
                _failureContext(door: Door.sceneRehearsal),
              ),
            );
          }
          return null;
        }
      case Answered():
        return null;
      case final RoomFailure failure:
        _decideAt(failure, door: Door.sceneRehearsal);
        return null;
    }
  }

  void playKeptRetelling(int part) =>
      _gesture(() => _handOff(_playKeptRetelling(part)));

  Future<void> _playKeptRetelling(int part) async {
    final take = state.partsToReplay.elementAtOrNull(part - 1);
    final sessionId = state.sessionId;
    if (take == null || sessionId == null) return;
    final generation = _waitOnTheGeneration;
    final path = await _keptRetellingOnTheTablet(
      'kept-$sessionId-${take.scope}-${take.turnNumber}',
      take.audioUrl,
      generation,
    );
    if (path == null || _abandoned(generation) || state.keptRetellingsAreAway) {
      return;
    }
    _silenceTheRoom();
    _play(PartSound(0, path));
  }

  Future<String?> _keptRetellingOnTheTablet(
    String name,
    String url,
    int generation,
  ) async {
    final held = await _heldOnTheTablet(name);
    if (held != null) return held;
    return switch (await _room.fetchKeptRetelling(url)) {
      Answered(:final value) when value.isNotEmpty && !_abandoned(generation) =>
        await _recorder.keepBytes(value, name),
      _ => null,
    };
  }

  Future<String?> _heldOnTheTablet(String name) async {
    try {
      return await _recorder.heldAs(name);
    } on FileSystemException {
      return null;
    }
  }

  void sceneTap() => _gesture(() => _sceneTap());

  void pickTheScene(String sceneId) => _gesture(() => _pickTheScene(sceneId));

  void _pickTheScene(String sceneId) {
    final shown = state.scene;
    if (state.station is! SceneRehearsal ||
        !state.sceneQuestionShown ||
        shown.waiting ||
        state.scenes.numberOf(sceneId) == null ||
        _asleep(shown.askedAt)) {
      return;
    }
    state = state.copyWith(
      scene: shown.copyWith(
        picked: sceneId,
        pickedAt: clock.now(),
        clearAskedAt: true,
      ),
    );
  }

  void backToTheSceneQuestion() => _gesture(_backToTheSceneQuestion);

  void _backToTheSceneQuestion() {
    final shown = state.scene;
    if (state.station is! SceneRehearsal ||
        shown.step != SceneStep.record ||
        shown.picked == null ||
        !state.sceneChipLive ||
        _asleep(shown.pickedAt)) {
      return;
    }
    state = state.copyWith(
      scene: shown.copyWith(
        clearPicked: true,
        clearPickedAt: true,
        clearAskedAt: true,
      ),
    );
    _stampTheQuestion();
  }

  void sendTheSceneTakeAgain() => _gesture(() => _sendTheSceneTakeAgain());

  void _sceneTap() {
    if (_recordingStarting) return;
    if (state.station is! SceneRehearsal ||
        state.scene.step != SceneStep.record ||
        state.scene.waiting ||
        state.scene.keep is Keeping) {
      return;
    }
    switch (state.channel) {
      case Microphone(owner: MicOwner.scene):
        _handOff(_keepTheSceneTake());
      case Microphone():
        return;
      default:
        final shown = state.scene;
        if (state.scenes is ScenesAwaited ||
            state.sceneQuestionShown ||
            _asleep(shown.pickedAt)) {
          return;
        }
        state = state.copyWith(
          scene: switch (state.scenes.labelFor(shown.picked)) {
            final label? => shown.copyWith(label: label),
            null => shown.copyWith(clearLabel: true),
          },
        );
        _startListening('cena_${_stamp()}', owner: MicOwner.scene);
    }
  }

  Future<void> _keepTheSceneTake() async {
    final generation = _waitOnTheGeneration;
    final keeping = state.scene.copyWith(keep: const Keeping());
    state = state.copyWith(scene: keeping);
    final sessionId = state.sessionId;
    final path = (await _closeTheMicrophone()).take;
    if (path == null || _anAccidentalTap(path)) {
      if (path != null) unawaited(_recorder.delete(path));
    } else if (sessionId != null) {
      return _sendTheSceneTake(sessionId, path, keeping, generation);
    }
    if (identical(state.scene, keeping)) {
      state = state.copyWith(scene: keeping.copyWith(clearKeep: true));
      _stampTheQuestion();
    }
  }

  Future<void> _sendTheSceneTake(
    String sessionId,
    String path,
    SceneScreen keeping,
    int generation,
  ) async {
    if (_goneSessions.contains(sessionId)) return;
    final queue = _takes;
    final tooLarge = _tooLargeForTheRoom(path);
    final life = _thisLife;
    final PendingTake row;
    try {
      row = await queue.enqueue(
        File(path),
        sessionId: sessionId,
        kind: sceneTakeKind,
        scope: sceneTakeKind,
        scene: keeping.label,
      );
    } on Object {
      if (_endedSince(life) || _goneSessions.contains(sessionId)) return;
      _showTheTakeNotKept(
        NotKept(take: path, tooLarge: tooLarge),
        keeping,
        generation,
      );
      return;
    }
    if (_endedSince(life)) {
      await queue.flush();
      return;
    }
    if (_goneSessions.contains(sessionId)) {
      return queue.discardTheSession(sessionId);
    }
    await _keepTheRow(
      NotKept(row: row.id, take: path, tooLarge: tooLarge),
      keeping,
      generation,
    );
  }

  Future<void> _keepTheRow(
    NotKept waiting,
    SceneScreen keeping,
    int generation,
  ) async {
    final life = _thisLife;
    final kept = await _takes.keepTheScene(waiting.row!);
    if (kept == null) {
      _showTheTakeNotKept(waiting, keeping, generation);
      return _countUnsentIn(life);
    }
    await _theRoomKept(kept, waiting, keeping, generation, life);
  }

  Future<void> _theRoomKeptWhatWaited(int generation, int? life) async {
    if (_abandoned(generation)) return;
    final asked = state.scene;
    final waiting = asked.keep;
    if (waiting is! NotKept) return;
    final row = waiting.row;
    final kept = row == null ? null : _takes.keptSceneOf(row);
    if (kept == null) return;
    await _theRoomKept(kept, waiting, asked, generation, life);
  }

  Future<void> _theRoomKept(
    SceneRehearsalRecord kept,
    NotKept waiting,
    SceneScreen keeping,
    int generation,
    int? life,
  ) async {
    await _countUnsentIn(life);
    if (_abandoned(generation)) return;
    final named = await _heldOnTheTablet('cena-${kept.rehearsalId}');
    if (_abandoned(generation)) return;
    await _showTheRehearsal(kept, keeping, generation, take: named);
  }

  void _showTheTakeNotKept(
    NotKept waiting,
    SceneScreen keeping,
    int generation,
  ) {
    if (_theSceneMovedOn(keeping, generation)) return;
    state = state.copyWith(scene: keeping.copyWith(keep: waiting));
    _stampTheQuestion();
  }

  bool _tooLargeForTheRoom(String path) {
    try {
      return File(path).lengthSync() > largestTakeTheRoomKeeps;
    } on FileSystemException {
      return false;
    }
  }

  void _sendTheSceneTakeAgain() {
    final asked = state.scene;
    final waiting = asked.keep;
    if (state.station is! SceneRehearsal ||
        asked.step != SceneStep.record ||
        asked.waiting ||
        waiting is! NotKept ||
        state.channel is Microphone) {
      return;
    }
    final keeping = asked.copyWith(keep: const Keeping());
    state = state.copyWith(scene: keeping);
    _handOff(_sendAgain(waiting, keeping));
  }

  Future<void> _sendAgain(NotKept waiting, SceneScreen keeping) async {
    final generation = _waitOnTheGeneration;
    final row = waiting.row;
    if (row != null) {
      await _takes.dueAgain(row);
      return _keepTheRow(waiting, keeping, generation);
    }
    final take = waiting.take;
    final sessionId = state.sessionId;
    if (take == null || sessionId == null) return;
    await _sendTheSceneTake(sessionId, take, keeping, generation);
  }

  /// The circle of the translate step: it marks the pausa while the take plays, opens
  /// the frase's microphone once a pausa waits, and keeps the frase at the stop tap.
  void tapTheTranslateCircle() => _gesture(_tapTheTranslateCircle);

  void _tapTheTranslateCircle() {
    final shown = state.scene;
    if (state.station is! SceneRehearsal ||
        shown.step != SceneStep.translate ||
        shown.take == null ||
        shown.rehearsal == null ||
        shown.waiting ||
        state.theSceneIsSending ||
        state.needsPerson) {
      return;
    }
    _theRefusalLineGoes();
    switch (state.channel) {
      case Microphone(owner: MicOwner.frase):
        _handOff(_keepTheSceneFrase());
      case Microphone():
        return;
      case _ when !shown.listened:
        return;
      case _ when shown.translatingAgain != null || shown.pausa != null:
        final held = _frases.of(shown.rehearsal!.rehearsalId);
        if (held != null) {
          _handOff(_sendTheHeldFrase(held));
        } else {
          state = state.copyWith(scene: shown.copyWith(notUnderstood: false));
          _startListening('frase_${_stamp()}', owner: MicOwner.frase);
        }
      case PartPlaying():
        _markThePausa();
      default:
        _translateOnFrom(shown.rehearsal!.frontier);
    }
  }

  void playTheSceneRehearsal() => _gesture(() => _playTheSceneRehearsal());

  void _playTheSceneRehearsal() {
    final SceneScreen(
      :step,
      :take,
      :rehearsal,
      :waiting,
      :pausa,
      :translatingAgain,
    ) = state.scene;
    if (state.station is! SceneRehearsal ||
        waiting ||
        state.theSceneIsSending ||
        state.channel is Microphone ||
        (step != SceneStep.translate && step != SceneStep.sent) ||
        take == null ||
        rehearsal == null) {
      return;
    }
    final playing = state.channel is PartPlaying;
    if (step == SceneStep.sent) {
      _silenceTheRoom();
      if (!playing) _play(PartSound(0, take));
      return;
    }
    if (_theListFirst(_playTheSceneRehearsal)) return;
    _theRefusalLineGoes();
    final shown = state.scene.nothingAskedAgain;
    state = state.copyWith(scene: shown);
    if (translatingAgain != null) {
      _letItsNewTranslationGo(rehearsal.rehearsalId, translatingAgain);
      state = state.copyWith(scene: shown.copyWith(clearPausa: true));
      _translateOnFrom(rehearsal.frontier);
    } else if (!shown.listened) {
      state = state.copyWith(scene: shown.copyWith(listened: true));
      _translateOnFrom(rehearsal.frontier);
    } else if (playing && pausa != null) {
      _silenceTheRoom();
    } else if (playing) {
      _markThePausa();
    } else if (pausa != null) {
      state = state.copyWith(scene: shown.copyWith(clearPausa: true));
      _translateOnFrom(pausa);
    } else {
      _translateOnFrom(rehearsal.frontier);
    }
  }

  void _translateOnFrom(Duration from) {
    _silenceTheRoom();
    _play(
      PartSound(0, state.scene.take!, from: from),
      onComplete: _theTakeEnded,
    );
  }

  /// The pausa where the tap fell, snapped to the nearest silence of the take; at the
  /// tap for a take with no loudness to read, but never within 0.2 s of the last pausa
  /// (ADR 0076, as amended).
  void _markThePausa() {
    final tap = _playback.position;
    _silenceTheRoom();
    final shown = state.scene;
    final pausa = _thePausaAt(tap, shown);
    if (pausa != null) {
      state = state.copyWith(scene: shown.copyWith(pausa: pausa));
    }
  }

  /// Never behind where the translation stopped nor past the take's end, so the room
  /// can keep the frase.
  Duration? _thePausaAt(Duration tap, SceneScreen shown) {
    final frontier = shown.rehearsal!.frontier;
    final envelope = state.sceneEnvelope;
    final end = shown.takeEnd;
    if (envelope == null || end == null) {
      final raw = end != null && tap > end ? end : tap;
      return raw > frontier ? pauseAtTheTap(raw, frontier, end) : null;
    }
    final bounds = pauseBounds(frontier, end);
    if (bounds == null) return null;
    return placeThePause(envelope, tap, lo: bounds.lo, hi: bounds.hi);
  }

  /// A take heard to its end ends its last frase at the take's end, when a frase is
  /// still left to tell there.
  void _theTakeEnded() {
    final shown = state.scene;
    if (state.station is! SceneRehearsal ||
        shown.step != SceneStep.translate ||
        shown.waiting ||
        shown.pausa != null ||
        !shown.moreToTell) {
      return;
    }
    state = state.copyWith(scene: shown.copyWith(pausa: shown.takeEnd));
  }

  /// The stop tap: the frase goes to the room with its place in the take, and the take
  /// plays on from it once the room kept it. A frase the room did not keep leaves the
  /// pausa waiting for the circle to record it again (ADR 0099).
  Future<void> _keepTheSceneFrase() async {
    final generation = _waitOnTheGeneration;
    final shown = state.scene;
    final waiting = shown.asWaiting;
    state = state.copyWith(scene: waiting);
    final rehearsal = shown.rehearsal!;
    final translatedAgain = shown.translatingAgain;
    final sessionId = state.sessionId;
    final life = _thisLife;
    final MicOutcome closed;
    try {
      closed = await _closeTheMicrophone();
    } on Object {
      if (identical(state.scene, waiting)) state = state.copyWith(scene: shown);
      return;
    }
    final path = closed.take;
    if (path == null ||
        sessionId == null ||
        _endedSince(life) ||
        _theSceneMovedOn(waiting, generation) ||
        _anAccidentalTap(path)) {
      if (path != null) unawaited(_recorder.delete(path));
      if (identical(state.scene, waiting)) state = state.copyWith(scene: shown);
      return;
    }
    final frase = (
      sessionId: sessionId,
      path: path,
      startsMs: translatedAgain?.startsMs ?? rehearsal.frontier.inMilliseconds,
      endsMs: translatedAgain == null
          ? shown.pausa!.inMilliseconds
          : shown.pausa?.inMilliseconds ?? translatedAgain.endsMs!,
      afterRestart: rehearsal.afterRestart,
      replaces: translatedAgain?.fraseId,
    );
    _frases.hold(rehearsal.rehearsalId, frase);
    await _sendTheSceneFrase(frase, shown, waiting, generation);
  }

  /// The frase whose answer was lost goes again as the same bytes over the same span:
  /// the room keeps the same bytes as one frase, whatever happened to the first.
  Future<bool> _sendTheHeldFrase(_HeldFrase frase) {
    final generation = _waitOnTheGeneration;
    final shown = state.scene;
    final waiting = shown.asWaiting;
    state = state.copyWith(scene: waiting);
    return _sendTheSceneFrase(frase, shown, waiting, generation);
  }

  /// Every end lets the frase's file go but SCENE_REHEARSAL_SENDING, which holds it to be
  /// sent again: the team tells a frase the room did not keep again, and the room refuses
  /// it over one it kept. A translation again that was not kept reads the list, which
  /// shows the new one if the room kept it after all. Whether the screen that sent it was
  /// still there to take the answer.
  Future<bool> _sendTheSceneFrase(
    _HeldFrase frase,
    SceneScreen shown,
    SceneScreen waiting,
    int generation,
  ) async {
    final rehearsalId = shown.rehearsal!.rehearsalId;
    final life = _thisLife;
    final frases = _frases..takeOff(frase.path);
    final kept = await _room.keepTheSceneFrase(
      frase.sessionId,
      rehearsalId,
      File(frase.path),
      startsMs: frase.startsMs,
      endsMs: frase.endsMs,
      afterRestart: frase.afterRestart,
      replaces: frase.replaces,
    );
    final stillHeld = switch (kept) {
      Refused(code: RefusalCode.sceneRehearsalSending) => true,
      _ => false,
    };
    if (!stillHeld) frases.letGo(rehearsalId, frase);
    frases.land(frase.path);
    if (_endedSince(life) || _theSceneMovedOn(waiting, generation)) {
      return false;
    }
    switch (kept) {
      case Answered(:final value):
        _theFraseWasKept(shown, value);
      case final Refused refused when _aMoveRefused.containsKey(refused.code):
        _theMoveWasNotKept(refused, shown, _aMoveRefused[refused.code]!);
      case final RoomFailure failure:
        _theFraseWasNotKept(
          failure,
          shown,
          rule: switch (failure) {
            Refused(code: RefusalCode.fraseOutOfPlace) =>
              RefusalRule.readsTheListAgain,
            _ when frase.replaces != null => RefusalRule.readsTheListAgain,
            _ => RefusalRule.letsTheStepGo,
          },
        );
        if (!state.scene.notUnderstood &&
            state.sceneTranslationUnseen &&
            await _theListDecides() &&
            _aMove(shown.translatingAgain, frase.endsMs)) {
          _goOnFromTheMove();
        }
    }
    return true;
  }

  /// Whether a translation again of [again] ending at [endsMs] moved its pause.
  static bool _aMove(SceneFrase? again, int? endsMs) =>
      again != null && endsMs != null && endsMs != again.endsMs;

  /// A moved pause the room kept: the take goes on from its new end.
  void _goOnFromTheMove() {
    if (!state.scene.moreToTell) return;
    _translateOnFrom(state.scene.rehearsal!.frontier);
  }

  /// A moved pause the room refused is dropped with her line for why, and the frases
  /// are read again.
  void _theMoveWasNotKept(Refused refused, SceneScreen shown, SceneLine why) {
    _silenceTheRoom();
    state = state.copyWith(
      scene: shown.nothingAskedAgain.copyWith(clearPausa: true),
      sceneLine: why,
    );
    _decideAt(
      refused,
      door: Door.sceneRehearsal,
      rule: RefusalRule.readsTheListAgain,
    );
  }

  /// A frase refused as out of place may lie over one the room kept while this screen
  /// was away: the list is read again, and the screen shows the kept one.
  void _theFraseWasNotKept(
    RoomFailure failure,
    SceneScreen shown, {
    RefusalRule rule = RefusalRule.letsTheStepGo,
  }) {
    state = state.copyWith(scene: shown);
    _decideAt(failure, door: Door.sceneFrase, rule: rule);
  }

  /// A frase translated again stays paused where it is, unless its pause moved: the take
  /// then plays on from the new end. A pausa the team marked past the kept frase stays
  /// for the circle; otherwise the take plays on from where the translation now stops.
  void _theFraseWasKept(SceneScreen shown, SceneRehearsalRecord kept) {
    if (shown.translatingAgain case final again?) {
      final unseen = state.sceneTranslationsUnseen;
      final moved = _aMove(again, shown.pausa?.inMilliseconds);
      state = state.copyWith(
        scene: shown.nothingAskedAgain.copyWith(
          rehearsal: kept,
          clearPausa: true,
        ),
        sceneRehearsals: _listedWith(kept),
        sceneTranslationsUnseen: unseen[kept.rehearsalId] == again.fraseId
            ? ({...unseen}..remove(kept.rehearsalId))
            : unseen,
      );
      if (moved) _goOnFromTheMove();
      return;
    }
    final pausa = shown.pausa;
    final ahead = pausa != null && pausa > kept.frontier;
    state = state.copyWith(
      scene: shown.copyWith(rehearsal: kept, clearPausa: !ahead),
      sceneRehearsals: _listedWith(kept),
    );
    if (!ahead && state.scene.moreToTell) _translateOnFrom(kept.frontier);
  }

  /// A tap on a frase's bar on the translate step: its stretch of the take plays, and
  /// the next circle records a new translation of it. It waits while a frase waits to be
  /// sent again.
  void translateTheFraseAgain(String fraseId) =>
      _gesture(() => _translateTheFraseAgain(fraseId));

  void _translateTheFraseAgain(String fraseId) {
    final shown = state.scene;
    final take = shown.take;
    final frase = _theFraseShown(fraseId, on: const {SceneStep.translate});
    if (frase == null ||
        take == null ||
        !frase.placedIn(shown.length) ||
        _frases.of(shown.rehearsal!.rehearsalId) != null) {
      return;
    }
    _silenceTheRoom();
    _theRefusalLineGoes();
    final alreadyMoving = state.sceneFraseOnTheMove?.fraseId == fraseId
        ? shown.pausa
        : null;
    state = state.copyWith(
      scene: shown.nothingAskedAgain.copyWith(
        translatingAgain: frase,
        clearPausa: true,
        listened: true,
      ),
    );
    final pausa = state.sceneFraseOnTheMove == null
        ? null
        : alreadyMoving ?? Duration(milliseconds: frase.endsMs!);
    if (pausa != null) {
      state = state.copyWith(scene: state.scene.copyWith(pausa: pausa));
    }
    _play(
      PartSound(
        0,
        take,
        from: Duration(milliseconds: frase.startsMs!),
        to: pausa ?? Duration(milliseconds: frase.endsMs!),
      ),
    );
  }

  /// «um pouco antes» and «um pouco depois»: the pending pausa moves to the next silence
  /// that way within 1.5 s, else by 0.4 s, within its bounds (ADR 0076).
  void pauseEarlier() => _gesture(() => _nudgeTheScenePausa(Nudge.earlier));

  void pauseLater() => _gesture(() => _nudgeTheScenePausa(Nudge.later));

  void _nudgeTheScenePausa(Nudge to) {
    final pausa = state.scene.pausa;
    final envelope = state.sceneEnvelope;
    final bounds = state.scenePausaBounds;
    if (!_thePausaAdjusts ||
        pausa == null ||
        envelope == null ||
        bounds == null) {
      return;
    }
    final nudged = nudgeThePause(
      envelope,
      pausa,
      to,
      lo: bounds.lo,
      hi: bounds.hi,
    );
    if (to == Nudge.later ? nudged <= pausa : nudged >= pausa) return;
    _silenceTheRoom();
    _theRefusalLineGoes();
    state = state.copyWith(scene: state.scene.copyWith(pausa: nudged));
  }

  /// «ouvir a pausa»: up to 1.5 s before the pausa, never from before the previous
  /// pause, stopping at the pausa.
  void hearThePause() => _gesture(_hearThePause);

  void _hearThePause() {
    final SceneScreen(:pausa, :take) = state.scene;
    if (!_thePausaAdjusts || pausa == null || take == null) return;
    final from = theMomentBefore(pausa, state.scenePausaFloor);
    _silenceTheRoom();
    _theRefusalLineGoes();
    _play(PartSound(0, take, from: from, to: pausa));
  }

  /// Whether the row moves the pausa: never while a frase waits to be sent again, which
  /// goes at the pausa it was told at.
  bool get _thePausaAdjusts =>
      state.station is SceneRehearsal &&
      state.scene.step == SceneStep.translate &&
      _frases.of(state.scene.rehearsal!.rehearsalId) == null &&
      !state.scene.waiting &&
      !state.theSceneIsSending &&
      !state.needsPerson &&
      state.channel is! Microphone &&
      state.scenePausaAdjusts;

  /// A refused move's or a failed restart's line goes at the team's next gesture.
  void _theRefusalLineGoes() {
    if (state.sceneLine case null || SceneLine.restarted) return;
    state = state.copyWith(clearSceneLine: true);
  }

  /// «manter a tradução de antes»: the frase being translated again is given up, and so
  /// is its new translation still waiting to be sent again.
  void keepTheEarlierTranslation() => _gesture(_keepTheEarlierTranslation);

  void _keepTheEarlierTranslation() {
    final shown = state.scene;
    if (state.station is! SceneRehearsal ||
        shown.translatingAgain == null ||
        state.sceneTranslationUnseen ||
        shown.waiting ||
        state.theSceneIsSending ||
        state.channel is Microphone) {
      return;
    }
    _letItsNewTranslationGo(
      shown.rehearsal!.rehearsalId,
      shown.translatingAgain!,
    );
    _silenceTheRoom();
    _theRefusalLineGoes();
    state = state.copyWith(
      scene: shown.nothingAskedAgain.copyWith(clearPausa: true),
    );
  }

  /// A new translation of the frase translated again that still waits to be sent again
  /// goes when the team gives that frase up.
  void _letItsNewTranslationGo(String rehearsalId, SceneFrase translatedAgain) {
    if (_frases.of(rehearsalId)?.replaces == translatedAgain.fraseId) {
      _frases.letGoOf(rehearsalId);
    }
  }

  /// Her «não entendi» stands on the translate step until the frase microphone opens
  /// again or the screen moves on.
  void _theFraseNotUnderstood() =>
      state = state.copyWith(scene: state.scene.copyWith(notUnderstood: true));

  /// The disk word stands on the scene screen until the team's next gesture.
  void _theDiskFailed() =>
      state = state.copyWith(sceneLine: SceneLine.diskFailed);

  void _theDiskWordGoes() {
    if (state.sceneLine != SceneLine.diskFailed) return;
    state = state.copyWith(clearSceneLine: true);
  }

  /// The room may have kept the translation again whose answer was lost: that stands with
  /// the rehearsal, and the frase post waits on its list.
  void _theFrasePerhapsKept() {
    final shown = state.scene;
    final told = shown.rehearsal;
    final again = shown.translatingAgain;
    if (told == null || again == null) return _theFraseNotUnderstood();
    state = state.copyWith(
      scene: shown.copyWith(notUnderstood: false),
      sceneTranslationsUnseen: {
        ...state.sceneTranslationsUnseen,
        told.rehearsalId: again.fraseId,
      },
    );
  }

  /// A list the room answered is its word for every rehearsal it names: their rows and
  /// what they may hold unseen change together.
  void _theRoomListed(List<SceneRehearsalRecord> listed, String sessionId) =>
      state = state.copyWith(
        sceneRehearsals: SceneRehearsalRecord.listedOver(
          state.sceneRehearsals,
          listed,
          sessionId,
        ),
        sceneTranslationsUnseen: _settledBy(listed),
      );

  /// What the room may hold unseen, less the rehearsals [listed] settles.
  Map<String, String> _settledBy(List<SceneRehearsalRecord> listed) => {
    for (final MapEntry(key: rehearsalId, value: fraseId)
        in state.sceneTranslationsUnseen.entries)
      if (!listed.any((rehearsal) => rehearsal.rehearsalId == rehearsalId))
        rehearsalId: fraseId,
  };

  /// The screen waits on the list of a rehearsal whose room may hold a new translation the
  /// team has not seen, which shows the new one if the room kept it, and her line with
  /// «manter a tradução de antes» if not. A list read that fails leaves her line, and
  /// what the room holds stays unknown. Whether the room kept it, or nothing was unknown.
  Future<bool> _theListDecides() async {
    final shown = state.scene;
    final sessionId = state.sessionId;
    final told = shown.rehearsal;
    final unseen = state.sceneTranslationsUnseen[told?.rehearsalId];
    if (sessionId == null || told == null || unseen == null) return true;
    final waiting = shown.asWaiting;
    state = state.copyWith(scene: waiting);
    final generation = _waitOnTheGeneration;
    final listed = await _room.sceneRehearsalsOf(sessionId);
    if (_theSceneMovedOn(waiting, generation)) return false;
    switch (listed) {
      case Answered(:final value):
        _theRoomListed(value, sessionId);
        final now = value
            .where((rehearsal) => rehearsal.rehearsalId == told.rehearsalId)
            .firstOrNull;
        if (now == null) {
          state = state.copyWith(scene: shown.copyWith(notUnderstood: true));
          return false;
        }
        final kept = !now.currentFrases.any((frase) => frase.fraseId == unseen);
        final asked = waiting.copyWith(notUnderstood: !kept);
        state = state.copyWith(scene: asked);
        await _showTheRehearsal(now, asked, generation);
        return kept && !identical(state.scene, asked);
      case final RoomFailure failure:
        state = state.copyWith(scene: shown.copyWith(notUnderstood: true));
        _decideAt(failure, door: Door.sceneList);
    }
    return false;
  }

  /// Whether [gesture] waits for the list first: the room may hold a new translation the
  /// team has not seen.
  bool _theListFirst(void Function() gesture) {
    final unseen = state.sceneTranslationUnseen;
    if (unseen) _handOff(_theListBefore(gesture));
    return unseen;
  }

  Future<void> _theListBefore(void Function() gesture) async {
    if (await _theListDecides()) gesture();
  }

  void playTheFrase(String fraseId) => _gesture(() => _playTheFrase(fraseId));

  void _playTheFrase(String fraseId) {
    final SceneScreen(:take, :length) = state.scene;
    final frase = _theFraseShown(fraseId, on: const {SceneStep.sent});
    if (frase == null || take == null || !frase.placedIn(length)) return;
    _silenceTheRoom();
    _play(
      PartSound(
        0,
        take,
        from: Duration(milliseconds: frase.startsMs!),
        to: Duration(milliseconds: frase.endsMs!),
      ),
    );
  }

  SceneFrase? _theFraseShown(String fraseId, {required Set<SceneStep> on}) {
    final SceneScreen(:step, :rehearsal, :waiting) = state.scene;
    if (state.station is! SceneRehearsal ||
        !on.contains(step) ||
        waiting ||
        state.theSceneIsSending ||
        state.channel is Microphone) {
      return null;
    }
    return rehearsal?.currentFrases
        .where((frase) => frase.fraseId == fraseId)
        .firstOrNull;
  }

  void hearTheFraseTranslation(String fraseId) =>
      _gesture(() => _hearTheFraseTranslation(fraseId));

  void _hearTheFraseTranslation(String fraseId) {
    final shown = state.scene;
    final frase = _theFraseShown(
      fraseId,
      on: const {SceneStep.sent, SceneStep.translate},
    );
    if (frase == null) return;
    final waiting = shown.asWaiting;
    _silenceTheRoom();
    state = state.copyWith(scene: waiting);
    _handOff(_hearTheFrase(shown.rehearsal!, frase, shown, waiting));
  }

  Future<void> _hearTheFrase(
    SceneRehearsalRecord rehearsal,
    SceneFrase frase,
    SceneScreen shown,
    SceneScreen waiting,
  ) async {
    final generation = _waitOnTheGeneration;
    final path = await _fetchASceneClip(
      'cena-${rehearsal.rehearsalId}-frase-${frase.fraseId}',
      RoomRepository.sceneFraseAudioUrl(
        rehearsal.sessionId,
        rehearsal.rehearsalId,
        frase.fraseId,
      ),
      () => _theSceneMovedOn(waiting, generation),
      generation,
    );
    if (_theSceneMovedOn(waiting, generation)) return;
    state = state.copyWith(scene: shown);
    if (path != null) _play(PartSound(0, path));
  }

  void recordTheSceneAgain() => _gesture(() => _recordTheSceneAgain());

  void _recordTheSceneAgain() {
    if (state.station is! SceneRehearsal ||
        state.theSceneIsSending ||
        (state.scene.step == SceneStep.translate && state.scene.waiting)) {
      return;
    }
    if (state.channel is Microphone) _dispatch(const MicDiscarded());
    if (state.scene.rehearsal case final rehearsal?) {
      _frases.letGoOf(rehearsal.rehearsalId);
    }
    _silenceTheRoom();
    state = state.copyWith(
      scene: SceneScreen(again: state.scene.rehearsal?.scene),
      clearSceneRestart: true,
      clearSceneLine: true,
    );
    if (state.scenes is ScenesMissing) unawaited(_askForTheScenes());
    _stampTheQuestion();
  }

  void restartTheSceneTranslation() =>
      _gesture(() => _restartTheSceneTranslation());

  /// «recomeçar a tradução» takes two taps: the first arms it, which wakes after
  /// [restartWakeProvider] so a double tap never fires it and lapses after
  /// [restartLapseProvider]; the second sets the frases aside in the room.
  void _restartTheSceneTranslation() {
    final shown = state.scene;
    final sessionId = state.sessionId;
    if (state.station is! SceneRehearsal ||
        !state.sceneRestartShown ||
        shown.waiting ||
        state.theSceneIsSending ||
        state.needsPerson ||
        state.channel is Microphone ||
        sessionId == null) {
      return;
    }
    if (state.sceneRestart == null) {
      _theRefusalLineGoes();
      state = state.copyWith(sceneRestart: BtRecomeco.armado);
      _after('sceneRestartWakes', ref.read(restartWakeProvider), () {
        if (state.sceneRestart != BtRecomeco.armado) return;
        state = state.copyWith(sceneRestart: BtRecomeco.pronto);
      });
      _after(
        'sceneRestartLapses',
        ref.read(restartLapseProvider),
        () => state = state.copyWith(clearSceneRestart: true),
      );
      return;
    }
    if (state.sceneRestart != BtRecomeco.pronto) return;
    _timers.remove('sceneRestartLapses')?.cancel();
    _silenceTheRoom();
    final waiting = shown.asWaiting;
    state = state.copyWith(scene: waiting, clearSceneRestart: true);
    _handOff(_restartTheTranslation(sessionId, shown, waiting));
  }

  Future<void> _restartTheTranslation(
    String sessionId,
    SceneScreen shown,
    SceneScreen waiting,
  ) async {
    final generation = _waitOnTheGeneration;
    final rehearsal = shown.rehearsal!;
    final restarted = await _room.restartTheSceneTranslation(
      sessionId,
      rehearsal.rehearsalId,
      attempt: mintAUuid(),
      closes: rehearsal.afterRestart,
    );
    if (_abandoned(generation)) return;
    final stillShown = !_theSceneMovedOn(waiting, generation);
    if (stillShown) state = state.copyWith(scene: shown);
    switch (restarted) {
      case Answered(:final value):
        _frases.letGoOf(rehearsal.rehearsalId);
        if (stillShown) {
          final fresh = shown.nothingAskedAgain.copyWith(
            listened: false,
            clearPausa: true,
          );
          state = state.copyWith(scene: fresh);
          _sayTheSceneLine(SceneLine.restarted);
          await _showTheRehearsal(value, fresh, generation);
        }
      case final RoomFailure failure:
        if (stillShown) _sayTheSceneLine(SceneLine.restartFailed);
        _decideAt(failure, door: Door.sceneRehearsal);
    }
  }

  /// «tradução recomeçada» stands for [restartLapseProvider]; a failure's line stands
  /// until the team's next gesture.
  void _sayTheSceneLine(SceneLine line) {
    state = state.copyWith(sceneLine: line);
    if (line != SceneLine.restarted) return;
    _after('sceneLine', ref.read(restartLapseProvider), () {
      if (state.sceneLine != SceneLine.restarted) return;
      state = state.copyWith(clearSceneLine: true);
    });
  }

  void _theSceneRehearsalsHeard(List<SceneRehearsalRecord> listed) {
    final asked = state.scene;
    final sessionId = state.sessionId;
    if (sessionId == null || _theSceneMovedOn(asked, _generation)) return;
    _theRoomListed(listed, sessionId);
    final held = state.sceneRehearsals
        .where(
          (rehearsal) => rehearsal.rehearsalId == asked.rehearsal?.rehearsalId,
        )
        .firstOrNull;
    if (held == null || asked.waiting) return;
    _handOff(_showTheRehearsal(held, asked, _generation));
    final turn = state.sceneTurn;
    if (!held.unsent &&
        state.needsPerson &&
        turn != null &&
        turn.rehearsalId == held.rehearsalId) {
      state = state.copyWith(clearSceneTurn: true);
      _handOff(_sendTheScene(sessionId, held, turn.turnId));
    }
  }

  void openTheListedSceneRehearsal(String rehearsalId) =>
      _gesture(() => _openTheListedSceneRehearsal(rehearsalId));

  void _openTheListedSceneRehearsal(String rehearsalId) {
    final shown = state.scene;
    final row = state.sceneRehearsals
        .where((rehearsal) => rehearsal.rehearsalId == rehearsalId)
        .firstOrNull;
    if (state.station is! SceneRehearsal ||
        state.channel is Microphone ||
        shown.waiting ||
        state.theSceneIsSending ||
        state.needsPerson ||
        row == null ||
        rehearsalId == shown.rehearsal?.rehearsalId ||
        rehearsalId == _theRowTheOpenReopens?.rehearsalId) {
      return;
    }
    _silenceTheRoom();
    final waiting = shown.asWaiting;
    state = state.copyWith(
      scene: waiting,
      clearSceneRestart: true,
      clearSceneLine: true,
    );
    _handOff(_openTheRow(row, shown, waiting));
  }

  /// The unsent rehearsal the open is reopening, while the open still waits.
  SceneRehearsalRecord? get _theRowTheOpenReopens => switch (state) {
    SalaSessionState(scenes: ScenesAwaited(), :final sessionId?) =>
      SceneRehearsalRecord.toReopen(state.sceneRehearsals, sessionId),
    _ => null,
  };

  Future<void> _openTheRow(
    SceneRehearsalRecord row,
    SceneScreen shown,
    SceneScreen waiting,
  ) async {
    await _showTheRehearsal(row, waiting, _waitOnTheGeneration);
    if (!identical(state.scene, waiting)) return;
    state = state.copyWith(scene: shown);
  }

  void sendTheSceneRehearsal() => _gesture(() => _sendTheSceneRehearsal());

  void _sendTheSceneRehearsal() {
    final rehearsal = state.scene.rehearsal;
    final sessionId = state.sessionId;
    if (state.station is! SceneRehearsal ||
        !state.scene.sendable ||
        rehearsal == null ||
        sessionId == null ||
        state.theSceneIsSending ||
        state.needsPerson ||
        state.channel is Microphone) {
      return;
    }
    if (_theListFirst(_sendTheSceneRehearsal)) return;
    _theRefusalLineGoes();
    if (_frases.of(rehearsal.rehearsalId) case final frase?) {
      _silenceTheRoom();
      return _handOff(_theHeldFraseBeforeTheSend(frase, rehearsal.rehearsalId));
    }
    final held = state.sceneTurn;
    final turnId = held != null && held.rehearsalId == rehearsal.rehearsalId
        ? held.turnId
        : mintAUuid();
    state = state.copyWith(
      scene: state.scene.nothingAskedAgain,
      sceneTurn: (rehearsalId: rehearsal.rehearsalId, turnId: turnId),
    );
    _silenceTheRoom();
    _handOff(_sendTheScene(sessionId, rehearsal, turnId));
  }

  /// «terminei» never sends a rehearsal with a frase still held: the frase goes first,
  /// and the rehearsal once the room kept it or refused it for its place. A frase the
  /// room did not understand stops the send at her line; the next «terminei» sends
  /// without it.
  Future<void> _theHeldFraseBeforeTheSend(
    _HeldFrase frase,
    String rehearsalId,
  ) async {
    final here = await _sendTheHeldFrase(frase);
    if (here &&
        _frases.of(rehearsalId) == null &&
        !state.scene.notUnderstood &&
        !_aMoveRefused.containsValue(state.sceneLine) &&
        state.scene.rehearsal?.rehearsalId == rehearsalId) {
      _sendTheSceneRehearsal();
    }
  }

  /// «terminei» is a turn on the house path: the screen waits on it, shows her
  /// send-off line on the answer for [_theSceneStaysAfterItWent], then closes, and the
  /// reply plays on the Canvas.
  Future<void> _sendTheScene(
    String sessionId,
    SceneRehearsalRecord rehearsal,
    String turnId,
  ) async {
    final generation = _waitOnTheGeneration;
    if (!state.needsPerson) _sayImThinking();
    state = state.copyWith(awaitingTheGuide: true);
    _watchBusyState();
    await _sendATurn(
      Turn(sessionId, turnId),
      generation,
      () => _theSceneGoes(sessionId, rehearsal, turnId, generation),
      play: (reply) async {
        _frases.letGoOf(rehearsal.rehearsalId);
        state = state.copyWith(
          scene: state.scene.copyWith(wentToTheVoice: true),
        );
        await Future<void>.delayed(_theSceneStaysAfterItWent);
        if (_abandoned(generation)) return;
        _closeTheSceneRehearsal();
        await _voiceTurn(reply, _waitOnTheGeneration);
      },
      failed: (failure) {
        if (_abandoned(generation)) return;
        _registerUnplayableTurn();
        _decideAt(
          failure,
          door: Door.sceneRehearsal,
          rule: RefusalRule.readsTheListAgain,
        );
      },
    );
  }

  /// The send, retried in place under the same turn: while another tablet's send of
  /// this rehearsal is in the air, along the ladder; once, closing the room's attempt,
  /// when the attempt it closed moved on.
  Future<RoomAnswer<TurnResult>> _theSceneGoes(
    String sessionId,
    SceneRehearsalRecord rehearsal,
    String turnId,
    int generation,
  ) async {
    var closes = rehearsal.afterRestart;
    var inFlight = 0;
    var readTheList = false;
    while (true) {
      final answer = await _room.sendTheSceneRehearsal(
        sessionId,
        rehearsal.rehearsalId,
        turnId: turnId,
        closes: closes,
      );
      if (_abandoned(generation)) return answer;
      switch (answer) {
        case Refused(code: RefusalCode.sceneRehearsalSending)
            when ++inFlight < _sendsWhileInFlight:
          await Future<void>.delayed(_onTheLadder(inFlight - 1));
          if (_abandoned(generation)) return answer;
        case Refused(code: RefusalCode.restartOutOfOrder) when !readTheList:
          readTheList = true;
          switch (await _room.sceneRehearsalsOf(sessionId)) {
            case final RoomFailure failure:
              if (!_abandoned(generation)) {
                _decideAt(failure, door: Door.sceneRehearsal);
              }
              return answer;
            case Answered(:final value):
              if (_abandoned(generation)) return answer;
              final held = value
                  .where((row) => row.rehearsalId == rehearsal.rehearsalId)
                  .firstOrNull;
              if (held == null || !held.unsent || held.afterRestart == closes) {
                return answer;
              }
              closes = held.afterRestart;
          }
        default:
          return answer;
      }
    }
  }

  void leaveTheSceneRehearsal() => _gesture(() => _leaveTheSceneRehearsal());

  void _leaveTheSceneRehearsal() {
    if (state.station is! SceneRehearsal || state.theSceneIsSending) return;
    _closeTheSceneRehearsal();
  }

  void _closeTheSceneRehearsal() {
    _silenceTheRoom();
    _dispatch(const MicDiscarded());
    _arriveAt(const TheSceneRehearsalLeft());
  }

  void playTheRehearsal() => _gesture(() => _playTheRehearsal());

  void _playTheRehearsal() {
    if (state.playPing) {
      _holdClip();
      return;
    }
    if (state.takePaused) {
      _letTheClipRun();
      return;
    }
    if (!state.canPlayTheRehearsal) return;
    _playAll(_oEnsaioAteAqui());
  }

  /// One part alone, from its start, stopping at its own end.
  ///
  /// The part already sounding toggles pause the same way the play/pause circle does —
  /// [playTheRehearsal] already carries that logic, and duplicating it here would drift
  /// from it the first time either one changed. A different part stops whatever is in the
  /// air and starts this one instead of resuming it.
  ///
  /// A dimmed row — one of the others while a record-again sent by a finding stands open,
  /// not yet recorded — does not apply, so its listen does nothing (ADR 0040). Once that
  /// recording is pending (waiting for the green check), every row plays as usual: the
  /// team can hear what they recorded before deciding to keep it.
  void _tocarAParte(int indice) {
    if (state.station is! Ensaio) return;
    if (state.needsPerson) return;
    if (state.ensaio == EnsaioStatus.recording) return;
    if (indice < 0 || indice >= state.partes.length) return;
    if (state.partsAway.containsKey(state.partes[indice].takeId)) return;
    if (indice == state.parteDoEnsaioTocando) {
      playTheRehearsal();
      return;
    }
    _silenceTheRoom();
    _playAll(_osSonsDaParte(indice));
  }

  List<PartSound> _osSonsDaParte(int parte) => [
    for (final (path, trecho) in _clipesDaParte(parte))
      PartSound(parte, path, from: trecho?.$1 ?? Duration.zero, to: trecho?.$2),
  ];

  /// The parts in their scenes' order, and a recording waiting for the check for a scene
  /// with no part yet at that scene's place.
  List<PartSound> _oEnsaioAteAqui() {
    final partes = state.partes;
    final pendente = _pendingTakePath;
    final cena = state.cenaDaGravacao ?? 0;
    final daPendente = [
      if (pendente != null && _aParteDaGravacao == null)
        PartSound(partes.length, pendente),
    ];
    final antes = partes.indexWhere(
      (take) => (KeptScope.numberOf(take.scopeId) ?? 0) > cena,
    );
    return [
      for (var parte = 0; parte < partes.length; parte++) ...[
        if (parte == antes) ...daPendente,
        ..._osSonsDaParte(parte),
      ],
      if (antes < 0) ...daPendente,
    ];
  }

  /// What plays for one part of the rehearsal: the pending take standing in its place when
  /// this is the part the team is recording again, or its own recording and the stretches
  /// told back over it otherwise.
  List<(String, (Duration, Duration)?)> _clipesDaParte(int parte) {
    final pendente = _pendingTakePath;
    if (pendente != null && _aParteDaGravacao == parte) {
      return [(pendente, null)];
    }
    return _oQueTocaDaParte(parte);
  }

  /// Where in [SalaSessionState.partes] the part the open recording replaces sits; null
  /// for a recording of a Scene with no part yet.
  int? get _aParteDaGravacao => switch (state.cenaDaGravacao) {
    final cena? => state.partIndexOf(cena),
    null => null,
  };

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

  /// Record on Scene row [cena], record it again, or close its open recording. While a
  /// recording waits for the check, only its own row records over it.
  void gravarACena(int cena) => _gesture(() => _gravarACena(cena));

  void _gravarACena(int cena) {
    if (state.station is! Ensaio || state.needsPerson || state.playPing) {
      return;
    }
    final row = state.sceneRows.where((row) => row.number == cena).firstOrNull;
    if (row == null || row.dimmed) return;
    final daCena = state.cenaDaGravacao == cena;
    switch (state.ensaio) {
      case EnsaioStatus.idle:
        _abrirOMicrofoneDaCena(cena);
      case EnsaioStatus.recorded when daCena:
        _abrirOMicrofoneDaCena(cena);
      case EnsaioStatus.recording when daCena:
        _handOff(_finishTake());
      case EnsaioStatus.recorded || EnsaioStatus.recording:
        return;
    }
  }

  /// Scene row [cena]'s part alone.
  void ouvirACena(int cena) => _gesture(() => _ouvirACena(cena));

  void _ouvirACena(int cena) {
    final indice = state.partIndexOf(cena);
    if (indice == null || state.sceneRowIsDimmed(cena)) return;
    final takeId = state.partes[indice].takeId;
    if (state.partsAway[takeId] == PartAway.missed) {
      state = state.copyWith(
        partsAway: {...state.partsAway, takeId!: PartAway.coming},
      );
      return _bringThePartsDown(const Ensaio());
    }
    _tocarAParte(indice);
  }

  /// The circle records the part a finding sent the team back for, else the first Scene
  /// with no part; with every Scene recorded it records nothing.
  void ensaioTap() => _gesture(() => _ensaioTap());

  void _ensaioTap() {
    if (state.needsPerson || state.playPing) return;
    switch (state.ensaio) {
      case EnsaioStatus.idle:
        _readTheScenesForTheRehearsal();
        final cena = state.sceneForTheCircle;
        if (cena != null) _abrirOMicrofoneDaCena(cena);
      case EnsaioStatus.recorded:
        final cena = state.cenaDaGravacao ?? state.sceneForTheCircle;
        if (cena != null) _abrirOMicrofoneDaCena(cena);
      case EnsaioStatus.recording:
        _handOff(_finishTake());
    }
  }

  void _abrirOMicrofoneDaCena(int cena) {
    _silenceTheRoom();
    state = state.copyWith(
      ensaio: EnsaioStatus.recording,
      cenaDaGravacao: cena,
    );
    _dispatch(
      MicOpened(
        MicOwner.rehearsal,
        take: 'ensaio_tomada_${_stamp()}',
        generation: _generation,
      ),
    );
  }

  EnsaioStatus get _semGravacaoAberta =>
      _pendingTakePath == null ? EnsaioStatus.idle : EnsaioStatus.recorded;

  /// The part is only pending once the recorder has handed the file back.
  ///
  /// Flipping to `recorded` first lit the check while `stop()` was still writing, and a
  /// quick check found no path and dropped the take without a word. Staying in
  /// `recording` for those few frames is also the truer thing to show.
  Future<void> _finishTake() async {
    final generation = _waitOnTheGeneration;
    final path = (await _closeTheMicrophone()).take;
    if (_abandoned(generation)) return;
    if (path == null || _anAccidentalTap(path)) {
      state = state.copyWith(
        ensaio: _semGravacaoAberta,
        clearCenaDaGravacao: _pendingTakePath == null,
      );
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    _pendingTakePath = path;
    state = state.copyWith(ensaio: EnsaioStatus.recorded);
  }

  void takeKeep() => _gesture(() => _takeKeep());

  void _takeKeep() {
    _silenceTheRoom();
    final path = _pendingTakePath;
    _pendingTakePath = null;
    if (path == null) {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      return;
    }
    // Part N is Scene N: the recording is kept under the number of the row it was made
    // from, in place of the part already there.
    final numero = state.cenaDaGravacao ?? state.sceneForTheCircle;
    if (numero == null) {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      return;
    }
    state = state.copyWith(
      clearParteARegravar: true,
      clearCenaDaGravacao: true,
    );
    // A scene list not answered yet is asked again at each keep, the moment the team
    // next needs it to move on.
    _readTheScenesForTheRehearsal();
    if (state.partIndexOf(numero) case final noLugar?) {
      if (!state.recordsTheWhole) unawaited(_withdrawTheJoinsOf(numero));
      _aParteVoltaAoSeuLugar(noLugar, path);
      return;
    }
    if (state.recordsTheWhole) return _keepTheWhole(path);
    unawaited(_withdrawTheJoinsOf(numero));
    final escopo = KeptScope.parte(numero);
    final nova = KeptTake(
      scopeId: escopo,
      path: path,
      pass: (_passadasDaSala?[numero] ?? 0) + 1,
    );
    final passadas = _passadasDaSala;
    if (passadas != null) _passadasDaSala = _aindaPorGravar(passadas, {numero});
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [...state.keptTakes, nova],
    );
    _deixarOInteiroDeLado();
    _weighTheRehearsal();
    unawaited(
      _guard(
        path,
        _thisLife,
        kind: 'ensaio',
        scope: escopo,
        passNumber: nova.pass,
        chunkIndex: numero,
      ),
    );
    _rememberWhereTheyAre(const Ensaio());
  }

  /// The first recording of a passage recorded whole: no scene's part, no number.
  void _keepTheWhole(String path) {
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [
        ...state.keptTakes,
        KeptTake(scopeId: KeptScope.whole, path: path, pass: 1),
      ],
    );
    _weighTheRehearsal();
    unawaited(
      _guard(
        path,
        _thisLife,
        kind: 'ensaio',
        scope: KeptScope.whole,
        passNumber: 1,
      ),
    );
    _rememberWhereTheyAre(const Ensaio());
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
    // Scope and number are read off the same take, because they are the same fact said
    // twice and the room is sent both. Read apart — the scope off the take, the number
    // off the row — a row the two disagree about would send a recording up under one
    // part's name and another part's number.
    final escopo = state.partes[parte].scopeId;
    final numero = KeptScope.numberOf(escopo);
    final passada = state.partes[parte].pass + 1;
    _aParteNoLugar(parte, path, passada: passada);
    unawaited(_medirAParteRegravada(path, _generation));
    unawaited(
      _guard(
        path,
        _thisLife,
        kind: 'ensaio',
        scope: escopo,
        passNumber: passada,
        chunkIndex: numero,
      ),
    );
    _rememberWhereTheyAre(const Ensaio());
  }

  void _aParteNoLugar(
    int parte,
    String path, {
    required int passada,
    String? origin,
  }) {
    final escopo = state.partes[parte].scopeId;
    final trechos = [
      for (final trecho in state.btTrechos)
        if (trecho.parte != parte) trecho,
    ];
    final saem = {
      for (final trecho in state.btTrechos)
        if (trecho.parte == parte && trecho.frase != null) trecho.frase,
    };
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [
        for (final take in state.keptTakes)
          if (take.scopeId == escopo)
            KeptTake(scopeId: escopo, path: path, pass: passada, origin: origin)
          else
            take,
      ],
      partsAway: {...state.partsAway}..remove(state.partes[parte].takeId),
      btTrechos: trechos,
      btTrechosRegravados: [
        ...state.btTrechosRegravados,
        for (final trecho in state.btTrechos)
          if (trecho.parte == parte && trecho.contado) trecho,
      ],
      btFindings: [
        for (final finding in state.btFindings)
          if (!saem.contains(finding.frase)) finding,
      ],
    );
    _weighTheRehearsal();
  }

  /// The parts end where they now do, and this part is a file of its own length. Measured
  /// here rather than left to the next playthrough, because the part must not go on being
  /// read at the length of the recording it replaces.
  Future<void> _medirAParteRegravada(String arquivo, int generation) async {
    final quanto = await _playback.howLong(arquivo);
    if (quanto == null || _abandoned(generation)) return;
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
    if (state.cenaDaGravacao != null) {
      state = state.copyWith(clearCenaDaGravacao: true);
    }
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
  late Map<String, String> _semNome;

  late Set<String> _rowsOfThisVisit;

  /// Each opening of the Ensaio Final plan, so a join left behind by an earlier one
  /// touches nothing of the plan open now.
  late int _plansOpened;

  late Map<String?, Map<String, ({String path, int? pass})>> _notQueued;

  /// This session's keeps the Outbox could not take, by the row of the grain in force; a
  /// keep of another grain stands on no row (ADR 0134).
  Map<int, ({String scope, String path, int? pass})> get _notQueuedRows => {
    for (final MapEntry(key: scope, value: (:path, :pass))
        in (_notQueued[state.sessionId] ?? const {}).entries)
      ?state.rowOf(scope): (scope: scope, path: path, pass: pass),
  };

  late Map<(String?, int), int> _keepsInFlight;

  late Map<String, Duration?> _lengths;

  Future<void> _guard(
    String path,
    int? life, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) => _apart(() async {
    if (_endedSince(life)) return;
    final queue = _takes;
    final sessionId = state.sessionId;
    if (_goneSessions.contains(sessionId)) return;
    final audio = File(path);
    if (!await audio.exists()) return;
    if (sessionId == null) {
      if (!_endedSince(life)) {
        _notInTheOutbox(path, kind, scope, passNumber, sessionId);
      }
      return;
    }
    final inFlight = switch (state.rowOf(scope)) {
      final number? when kind == 'ensaio' => (sessionId, number),
      _ => null,
    };
    if (inFlight != null) {
      _keepsInFlight.update(inFlight, (keeps) => keeps + 1, ifAbsent: () => 1);
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
      _aKeepLeftTheAir(inFlight);
      if (_endedSince(life) || _goneSessions.contains(sessionId)) return;
      _notInTheOutbox(path, kind, scope, passNumber, sessionId);
      return;
    }
    if (kind == 'ensaio') {
      _rowsOfThisVisit.add(linha.id);
      _aKeepLeftTheAir(inFlight);
    }
    if (_endedSince(life)) {
      await queue.flush();
      return;
    }
    if (_goneSessions.contains(sessionId)) {
      return queue.discardTheSession(sessionId);
    }
    if (kind == 'ensaio') {
      _semNome[linha.id] = path;
      _notQueued[sessionId]?.remove(scope);
    }
    if (kind == 'retro') _traducaoNaFila[path] = linha;
    await _countUnsentIn(life);
    await queue.flush();
    await _countUnsentIn(life);
    await _adoptTheNames(queue, life);
  });

  void _notInTheOutbox(
    String path,
    String kind,
    String scope,
    int? pass,
    String? sessionId,
  ) {
    if (kind != 'ensaio' || state.rowOf(scope) == null) return;
    (_notQueued[sessionId] ??= {})[scope] = (path: path, pass: pass);
    unawaited(_countUnsent());
  }

  void enviarACena(int cena) => _gesture(() => _enviarACena(cena));

  void _enviarACena(int cena) {
    if (state.station is! Ensaio ||
        state.ensaio == EnsaioStatus.recording ||
        !state.unsentParts.containsKey(cena)) {
      return;
    }
    _handOff(_enviarAgora(cena));
  }

  Future<void> _enviarAgora(int cena) async {
    final life = _thisLife;
    if (_notQueuedRows[cena] case (:final scope, :final path, :final pass)) {
      _notQueued[state.sessionId]?.remove(scope);
      return _guard(
        path,
        life,
        kind: 'ensaio',
        scope: scope,
        passNumber: pass,
        chunkIndex: KeptScope.numberOf(scope),
      );
    }
    final queue = _takes;
    final tally = await queue.tally(sessionId: state.sessionId);
    for (final row in _theNewestPass(tally.unsentParts)[cena] ?? const []) {
      await queue.dueAgain(row.id);
    }
    await queue.flush();
    await _countUnsentIn(life);
    await _adoptTheNames(queue, life);
  }

  /// Take a guarded translation off the outbox, for a path the room will never send
  /// as a whole-passage take: one recorded over after a refusal, or one told again
  /// that has since landed by its own door.
  Future<void> _retirarDaFilaSeGuardada(String path) async {
    final linha = _traducaoNaFila.remove(path);
    if (linha == null) return;
    final life = _thisLife;
    try {
      await _takes.withdraw(linha);
    } on Object catch (error) {
      // Nothing here is stuck: a manifest write that failed leaves the row pending
      // and it still goes up, an upload the team never asked twice for but Henok
      // accepted; a delete that failed after the write leaves only an orphaned copy
      // behind. This is logged and dropped the way `_porCadaTrechoNaSuaParte`'s own
      // read failure already is.
      debugPrint(
        'Uma tradução guardada não pôde ser retirada da fila ($path): $error',
      );
      return;
    }
    await _countUnsentIn(life);
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
  Future<void> _adoptTheNames(TakeUploadQueue queue, int? life) async {
    for (final linha in _semNome.keys.toList()) {
      final id = await queue.takeIdOf(linha);
      if (_endedSince(life)) return;
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

  /// How the microphone the gesture closes answered: its take, or none, and where the
  /// Guide was cut when it opened. The gesture goes on the moment the recorder answers.
  Future<MicOutcome> _closeTheMicrophone() {
    final closed = Completer<MicOutcome>.sync();
    _closings.add(closed);
    _dispatch(const MicClosing());
    return closed.future;
  }

  /// What the Station does with each answer of the microphone, on the transition the
  /// machine takes.
  void _followTheMicrophone(Machine before, Machine after) {
    final heard = after.lastMic;
    if (heard == null || identical(heard, before.lastMic)) return;
    if (heard.answer != MicAnswer.closed) _recordingStarting = false;
    if ((heard.owner == MicOwner.scene || heard.owner == MicOwner.frase) &&
        (heard.answer == MicAnswer.refused ||
            heard.answer == MicAnswer.failed)) {
      _undoTheListening();
      return;
    }
    switch (heard.answer) {
      case MicAnswer.started:
        _captureFails.remove(heard.owner);
        ref.read(micPermissionProvider.notifier).heard();
      case MicAnswer.refused:
        _undoTheListening();
        ref.read(micPermissionProvider.notifier).refuse();
        _dispatch(
          decidedOnTheTablet(
            TheTabletCannotRecord(owner: heard.owner!),
            _failureContext(),
          ),
        );
      case MicAnswer.failed:
        _theRecorderNeverStarted(heard.owner!);
      case MicAnswer.closed:
        if (_closings.isEmpty) return;
        final closed = _closings.removeAt(0);
        final because = heard.because;
        if (because != null) return closed.completeError(because);
        closed.complete(heard);
      case MicAnswer.discarded:
        _undoTheListening();
      case MicAnswer.abandoned:
        break;
    }
  }

  /// A start that answers after a halt landed, after its microphone was closed, or after
  /// its capture was closed, has no microphone left to record into.
  bool _keepsTheStart(MicOwner owner) =>
      !state.needsPerson &&
      state.channel is Microphone &&
      (state.channel as Microphone).owner == owner &&
      (owner != MicOwner.capture || state.btPhase == BtPhase.capturing);

  void _theMicrophoneChangedHands(bool taken) {
    state = state.copyWith(micTaken: taken);
  }

  /// Put back whatever the caller set before it asked for a microphone.
  void _undoTheListening() {
    final capturing = state.btPhase == BtPhase.capturing;
    _dispatch(MicClosed(generation: _generation));
    state = state.copyWith(
      ensaio: _semGravacaoAberta,
      noteMode: false,
      btPhase: capturing ? BtPhase.playing : state.btPhase,
    );
  }

  /// The screen already said the room was listening, and it was not.
  ///
  /// Every caller sets its own state before this runs, so a recorder that never started
  /// left the circle gathering over a microphone that was off. The team performs the
  /// whole passage into it and loses it.
  void _theRecorderNeverStarted(MicOwner owner) {
    _undoTheListening();
    final inARow = _captureFails[owner] = (_captureFails[owner] ?? 0) + 1;
    _dispatch(
      decidedOnTheTablet(
        TheMicFailedToStart(inARow, owner: owner),
        _failureContext(),
      ),
    );
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
  /// This is not the generation guard below it and does not replace it. That one is about
  /// a session that has ended publishing over the one that replaced it — a different
  /// question, and still asked.
  late int _newestCount;

  Future<void> _countUnsent() => _countUnsentIn(_thisLife);

  Future<void> _countUnsentIn(int? life) => _apart(() async {
    if (_endedSince(life)) return;
    final generation = _waitOnTheGeneration;
    final counting = ++_newestCount;
    final queue = _takes;
    final sessionId = state.sessionId;
    final tally = await queue.tally(sessionId: sessionId);
    if (_endedSince(life)) return;
    _dispatch(OutboxChanged(tally.parts, due: tally.due));
    if (_abandoned(generation) || counting != _newestCount) return;
    final speaking = _theNewestPass(tally.unsentParts);
    if (sessionId != null &&
        state.station is Ensaio &&
        _unsentTakesOf(tally, speaking) < state.unsentTakes) {
      unawaited(_readWhatComesBack());
    }
    state = state.copyWith(unsentParts: _unsentPartsOf(speaking));
    if (sessionId != null) {
      state = state.copyWith(
        unsentTakes: _unsentTakesOf(tally, speaking),
        unsentChunks: tally.unsentChunks,
      );
    }
    if (await _measured(speaking, life) &&
        !_abandoned(generation) &&
        counting == _newestCount) {
      state = state.copyWith(unsentParts: _unsentPartsOf(speaking));
    }
  });

  Map<int, List<PendingTake>> _theNewestPass(
    Map<String, List<PendingTake>> outbox,
  ) {
    final speaking = <int, List<PendingTake>>{};
    for (final MapEntry(key: scope, value: rows) in outbox.entries) {
      final number = state.rowOf(scope);
      if (number == null) continue;
      final held = switch (state.partIndexOf(number)) {
        final index? => state.partes[index].pass,
        null => 0,
      };
      final newest = rows.map((row) => row.passNumber ?? 1).fold(held, max);
      final current = [
        for (final row in rows)
          if ((row.passNumber ?? 1) == newest) row,
      ];
      if (current.isNotEmpty) speaking[number] = current;
    }
    return speaking;
  }

  int _unsentTakesOf(OutboxTally tally, Map<int, List<PendingTake>> speaking) {
    var behindANewerPass = 0;
    for (final MapEntry(key: scope, value: rows) in tally.unsentParts.entries) {
      final number = state.rowOf(scope);
      if (number == null) continue;
      behindANewerPass += rows.length - (speaking[number]?.length ?? 0);
    }
    final notQueued = [
      for (final number in _notQueuedRows.keys)
        if (!speaking.containsKey(number)) number,
    ];
    return tally.unsentTakes - behindANewerPass + notQueued.length;
  }

  void _aKeepLeftTheAir((String?, int)? inFlight) {
    if (inFlight == null) return;
    final keeps = (_keepsInFlight[inFlight] ?? 1) - 1;
    if (keeps > 0) {
      _keepsInFlight[inFlight] = keeps;
    } else {
      _keepsInFlight.remove(inFlight);
    }
  }

  bool _ofThisVisit(int number, PendingTake newest) =>
      _rowsOfThisVisit.contains(newest.id) ||
      _keepsInFlight.containsKey((state.sessionId, number));

  Map<int, UnsentPart> _unsentPartsOf(Map<int, List<PendingTake>> speaking) => {
    for (final MapEntry(key: number, value: rows) in speaking.entries)
      number: UnsentPart(
        fromAnEarlierVisit: !_ofThisVisit(number, rows.last),
        failed: rows.any((row) => row.tries > 0 || row.exhausted || row.lost),
        length: _lengths[rows.last.path],
      ),
    for (final number in _notQueuedRows.keys)
      if (!speaking.containsKey(number))
        number: const UnsentPart(fromAnEarlierVisit: false, failed: true),
  };

  Future<bool> _measured(
    Map<int, List<PendingTake>> speaking,
    int? life,
  ) async {
    var measured = false;
    for (final MapEntry(key: number, value: rows) in speaking.entries) {
      final newest = rows.last;
      if (_ofThisVisit(number, newest) || _lengths.containsKey(newest.path)) {
        continue;
      }
      final length = await _playback.howLong(newest.path);
      if (_endedSince(life)) return false;
      _lengths[newest.path] = length;
      measured = true;
    }
    return measured;
  }

  Future<void> _mindingThePlace(Future<void> Function() write) =>
      _apart(() async {
        try {
          await write();
        } on Object catch (error) {
          debugPrint('O lugar da equipe não pôde ser guardado: $error');
        }
      });

  void theAppWentAway() {
    _cortarAEscutaNoAr();
    _relatarAEscuta();
  }

  void startRetro() => _gesture(() => _startRetro());

  void _startRetro() {
    if (state.station is Ensaio && state.ensaio != EnsaioStatus.idle) {
      return;
    }
    if (state.station.answer(const TheBackTranslationOpened()) is! Retro) {
      return;
    }
    final conferida = state.btPhase == BtPhase.conferida;
    // Before the write, not after: the mark belongs to the Rehearsal alone, and a row
    // saved for the retro must never carry one to restore.
    _leaveTheStepFor(const Retro());
    _clearAll();
    _rememberWhereTheyAre(const Retro());
    _arriveAt(const TheBackTranslationOpened());
    _regravouNestaVisita = false;
    _largarARegravacao();
    state = state.copyWith(
      awaitingTheGuide: false,
      btPhase: BtPhase.playing,
      btChunkFailures: const [],
      btClipEnded: false,
      btPass: 1,
      peerCue: false,
      hearNewScene: false,
      btSoOuvir: false,
    );
    _descartarATraducaoPendente();
    _handOff(
      _ouvirOQueFaltaDepoisDeRegravar(_generation, conferida: conferida),
    );
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
  /// The parts stepped over are reported as heard: the team heard them when it told them
  /// back. The room adds reports up per take (shema-api ADR 0074), so this is redundant
  /// for a round this build reported, and still true for one an older build never did.
  Future<void> _playFromTheUntoldGround(int generation) async {
    if (!await _medirAsPartesDaRetro(generation)) return;
    _sairDaEspera();
    _tocarDoChaoNaoContado();
  }

  Future<void> _ouvirOQueFaltaDepoisDeRegravar(
    int generation, {
    bool conferida = false,
  }) async {
    final life = _thisLife;
    if (!await _medirAsPartesDaRetro(generation)) return;
    final juntada = state.joined;
    if (juntada && state.sessionId != null) {
      await _readTheStretchesBack(state.sessionId!, generation);
      if (_abandoned(generation) || _endedSince(life)) return;
    }
    bool deixou() => _abandoned(generation) || _endedSince(life);
    final ouvida = await _oQueASalaOuviu(generation);
    if (deixou()) return;
    final nomes = ouvida?.unheardTakeIds;
    final naoOuvidas = nomes == null ? null : _asPartesNomeadas(nomes);
    final deFora = juntada && naoOuvidas != null && nomes!.isNotEmpty;
    if (naoOuvidas == null || naoOuvidas.isEmpty && !deFora) {
      if (ouvida case ListenedWhole(
        stretchUntranslated: true,
      ) when !conferida) {
        return _levarAoTrechoSemTraducao(
          ouvida.fixedLine,
          ouvida.untranslated,
          deixou,
        );
      }
      if (naoOuvidas != null &&
          !state.btTrechos.any((trecho) => trecho.contado)) {
        return _dizerComoTraduzir(deixou);
      }
      _sairDaEspera();
      _tocarDoChaoNaoContado();
      return;
    }
    final doComeco = !juntada || naoOuvidas.length == state.partes.length;
    final partes = doComeco || naoOuvidas.isEmpty
        ? [for (var onde = 0; onde < state.partes.length; onde++) onde]
        : naoOuvidas;
    state = state.copyWith(
      btSoOuvir: true,
      btRecusa: doComeco ? null : CheckRefusal.partUnheard,
    );
    _partesDaEscuta = partes;
    await _dizer(
      doComeco ? (juntada ? firstListenLine : startLine) : unheardLine,
    );
    if (_abandoned(generation) || _endedSince(life)) return;
    _sairDaEspera();
    _ouvirAsPartes(partes, paraNaUltima: true);
  }

  Future<void> _dizer(String? linha) async {
    if (linha == null) return;
    try {
      await _sayALine(
        LineKind.guide,
        fixedLine: (name: linha, language: _inTheSessionsLanguage),
      );
    } on RoomFailure catch (failure) {
      _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
    }
  }

  Future<ListenedWhole?> _oQueASalaOuviu(int generation) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return null;
    final resposta = await _room.reportTheListening(
      sessionId,
      playedByTake: _escuta.relato(state.partes),
    );
    if (resposta case Answered(
      value: final ouvida,
    ) when ouvida.unheardTakeIds != null) {
      return ouvida;
    }
    return null;
  }

  List<int> _asPartesNomeadas(List<String> nomes) => [
    for (final (onde, parte) in state.partes.indexed)
      if (parte.takeId == null || nomes.contains(parte.takeId)) onde,
  ];

  /// The last part of the First listen ended: its report is awaited, and the room's
  /// answer says whether translating opens and what follows (ADR 0123).
  Future<void> _depoisDaPrimeiraEscuta(int generation) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final life = _thisLife;
    final resposta = await _room.reportTheListening(
      sessionId,
      playedByTake: _escuta.relato(state.partes),
    );
    if (_abandoned(generation) || _endedSince(life)) return;
    final ouvida = switch (resposta) {
      Answered(:final value) => value,
      _ => null,
    };
    final nomes = ouvida?.unheardTakeIds;
    if (ouvida == null || nomes == null) {
      _oQueFaltaOuvir = _OQueFaltaOuvir(_partesDaEscuta, paraNaUltima: true);
      return;
    }
    final faltam = _asPartesNomeadas(nomes);
    if (nomes.isNotEmpty || faltam.isNotEmpty) {
      if (faltam.isNotEmpty) _partesDaEscuta = faltam;
      _oQueFaltaOuvir = _OQueFaltaOuvir(_partesDaEscuta, paraNaUltima: true);
      state = state.copyWith(btRecusa: CheckRefusal.partUnheard);
      return;
    }
    bool deixou() => _abandoned(generation) || _endedSince(life);
    if (state.btFraseQueAguarda case final aguardando?) {
      await _voltarAFraseQueAguarda(aguardando, generation);
      if (!deixou()) _deixarDeSoOuvir();
      return;
    }
    if (ouvida.stretchUntranslated) {
      return _levarAoTrechoSemTraducao(
        ouvida.fixedLine,
        ouvida.untranslated,
        deixou,
      );
    }
    if (ouvida.automaticCheck) {
      await _dizer(ouvida.fixedLine);
      if (deixou()) return;
      _deixarDeSoOuvir();
      return _finishBackTranslation();
    }
    if (!state.joined || !state.btTrechos.any((trecho) => trecho.contado)) {
      return _dizerComoTraduzir(deixou);
    }
    _deixarDeSoOuvir();
  }

  Future<void> _dizerComoTraduzir(bool Function() deixou) async {
    await _dizer(tellLine);
    if (deixou()) return;
    _deixarDeSoOuvir();
    _sairDaEspera();
    if (state.partes.isEmpty) return;
    _tocarParteDaRetro(0, doComeco: true);
  }

  Future<void> _levarAoTrechoSemTraducao(
    String? linha,
    List<UntranslatedPart> partes,
    bool Function() deixou,
  ) async {
    await _dizer(linha);
    if (deixou()) return;
    _deixarDeSoOuvir();
    _sairDaEspera();
    state = state.copyWith(
      btRecusa: CheckRefusal.stretchUntranslated,
      btCenasSemTraducao: [for (final parte in partes) ?parte.scene],
    );
    final primeira = partes.firstOrNull;
    final onde = state.partes.indexWhere(
      (parte) => parte.takeId == primeira?.takeId,
    );
    if (primeira == null || onde < 0) return _tocarDoChaoNaoContado();
    return _tocarParteDaRetro(onde, desde: primeira.from);
  }

  void _deixarDeSoOuvir() =>
      state = state.copyWith(btSoOuvir: false, clearBtRecusa: true);

  void _ouvirAsPartes(
    List<int> partes, {
    bool semChaoTraduzido = false,
    bool paraNaUltima = false,
  }) {
    _armarAsPartes(partes, paraNaUltima: paraNaUltima);
    _tocarParteDaRetro(
      partes.first,
      doComeco: true,
      semChaoTraduzido: semChaoTraduzido,
    );
  }

  void _armarAsPartes(List<int> partes, {required bool paraNaUltima}) {
    _oQueFaltaOuvir = _OQueFaltaOuvir(
      partes.skip(1).toList(),
      paraNaUltima: paraNaUltima,
    );
  }

  void _atravessar({bool doComeco = false}) {
    final falta = _oQueFaltaOuvir;
    if (falta == null || falta.aFrente.isEmpty) {
      _tocarParteDaRetro(_parteTocando + 1, doComeco: doComeco);
      return;
    }
    _ouvirAsPartes(falta.aFrente, paraNaUltima: falta.paraNaUltima);
  }

  Future<bool> _medirAsPartesDaRetro(int generation) async {
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _parteJaTocou = false;
    _tamanhoDaParteMs.clear();
    _oQueFaltaOuvir = null;
    _desdeMs = 0;
    state = state.copyWith(
      clearFindingSegment: true,
      btParteFronteira: false,
      btFimDasPartesMs: const [],
      btParteNoArMs: 0,
      btOuvidoMs: 0,
    );
    final partes = state.partes;
    if (partes.isEmpty) {
      // No rehearsal to tell back is not a rehearsal that finished playing. Calling it
      // one would open the check over an empty back translation.
      return false;
    }
    // Measuring waits on the player, and the screen it waits under is the retro with its
    // buttons up: a cut landing inside the wait opened the microphone over a clip about to
    // start, with the cursor at nought. Busy is the honest state for it.
    state = state.copyWith(btPhase: BtPhase.thinking, awaitingTheGuide: true);
    await _medirAsPartes(partes, generation);
    return !_abandoned(generation);
  }

  void _sairDaEspera() {
    state = state.copyWith(
      btPhase: BtPhase.playing,
      // Only out of the wait this method itself opened. A halt raised while the player was
      // measuring is the room's state now, and the invite put back over it let a blocked
      // room out of a halt nobody at the desk had attended.
      awaitingTheGuide: false,
      btFimDasPartesMs: _fimDaParteMs,
    );
  }

  void _tocarDoChaoNaoContado() {
    // The row is read again: this runs unawaited, and a part that left it while the player
    // measured would be indexed out of a list that no longer holds it. A row that emptied
    // meanwhile is the same room as one that arrived empty, and gets the same answer.
    final medidas = state.partes;
    if (medidas.isEmpty) return;
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
    final channel = state.channel;
    if (channel is Paused && channel.what is PartSound && channel.started) {
      _desdeMs = _playback.position.inMilliseconds;
      final arquivo = _parteNoAr?.path;
      if (arquivo != null) {
        _escuta.abrir(arquivo, _playback.position.inMilliseconds);
      }
      _letTheClipRun();
      return;
    }
    _tocarParteDaRetro(
      _parteTocando,
      noCursor: true,
      desde:
          _aCabecaDaParte ??
          Duration(
            milliseconds: state.btOuvidoMs - _inicioDaParteMs(_parteTocando),
          ),
    );
  }

  /// Stop the rehearsal and write down how far it got.
  void _pararOClipe() {
    _anotarOQueFoiOuvido();
    _holdClip();
  }

  /// Write down how far the rehearsal got, and close the span the ledger has open on the
  /// part in the air. Shared by a hold and by the one silence, so a transition closes a
  /// span exactly the way a hold does.
  void _anotarOQueFoiOuvido({int? ate}) {
    var ondeParou = state.btOuvidoMs;
    if (state.btClipRodando) {
      final fim = ate ?? _aCabecaMs;
      final arquivo = _parteNoAr?.path;
      if (arquivo != null) _escuta.fechar(arquivo, fim);
      ondeParou = _pontoNoColar(fim > _desdeMs ? fim : _desdeMs);
    }
    state = state.copyWith(btOuvidoMs: ondeParou);
  }

  int get _aCabecaMs => (_aCabecaDaParte ?? _playback.position).inMilliseconds;

  Duration? get _aCabecaDaParte => switch (state.channel) {
    PartPlaying(:final head) => head,
    Paused(what: PartSound(), :final head) => head,
    _ => _aParteSegurada?.head,
  };

  Paused? get _aParteSegurada => switch (state.channel) {
    final Paused paused when paused.what is PartSound && !paused.started =>
      paused,
    Playing(:final held) ||
    Paused(:final held) ||
    Microphone(:final held) ||
    GuideSpeaking(:final held) => held,
    _ => null,
  };

  void _medirAParteNoAr() {
    if (state.station is! Retro) return;
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
  /// What is reported as heard opens where the sound starts, but for one start: at the
  /// cursor, over ground already told back of this part, it opens at the part's nought,
  /// because that ground was heard when it was told, and a session an older build never
  /// reported would otherwise be refused a part it finished telling. The room adds reports
  /// up per take and counts a part heard when at most 0.75 s of it, and at most half, went
  /// unplayed (shema-api ADR 0074).
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
    bool seguir = true,
    Duration? desde,
  }) {
    // Every way a part goes in the air passes here — the crossing at a boundary, the
    // last listening of a checked passage, the next part, the landing on one nobody
    // heard — and none of them may start it under the line the Guide is still saying.
    _silenceTheRoom();
    _parteTocando = parte;
    if (!noCursor) {
      _trechoStart = semChaoTraduzido
          ? Duration.zero
          : _ondeParouNesteArquivo(parte);
    }
    _trechoEnd = _trechoStart;
    final de = desde ?? (doComeco ? Duration.zero : _trechoStart);
    _desdeMs = de.inMilliseconds;
    final arquivo = state.partes[parte].path;
    if (de > Duration.zero &&
        de == _trechoStart &&
        de <= _ondeParouNesteArquivo(parte)) {
      _escuta.abrir(arquivo, 0);
    } else {
      _escuta.abrir(arquivo, de.inMilliseconds);
    }
    state = state.copyWith(
      btParteFronteira: false,
      // A part going in the air is by definition a clip that has not ended. It never had
      // to be said while the only part put in the air after the mark was set was none:
      // landing on a part the room says nobody heard is the first, and it left the finish
      // lit over a part still playing — the same refusal, pressed again, for ever — and
      // the circle dead, because holding the clip and letting it go reads the mark and
      // refuses to start anything.
      btClipEnded: false,
      btOuvidoMs: _pontoNoColar(0),
      btParteNoArMs: 0,
      btOuvidoAlemDoCursor: false,
    );
    _parteJaTocou = true;
    // The deadline is armed once this clip's own `openings` event lands, never here:
    // `_playback.position` still answers for whatever clip was in the air before this
    // one, and a deadline read from it counts against a cursor that is not its own.
    _play(
      PartSound(parte, state.partes[parte].path, from: de),
      onComplete: () => _fimDeParte(seguir: seguir),
    );
  }

  void _fimDeParte({required bool seguir}) {
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
    _anotarOQueFoiOuvido(ate: medido);
    // Whether the rehearsal has played through, which is what the finish waits on, and
    // whether every part has an end on the ruler, which is the ruler's business: one question
    // each. They were one line while the ruler could only fill in order, so the last part
    // ending and the ruler being complete were the same instant. A landing jumps over a
    // part, and a part nothing could measure then held the boundary open past the end of
    // the row: the room offered a crossing into a part that is not there.
    final ultima = _parteTocando >= state.partes.length - 1;
    final falta = _oQueFaltaOuvir;
    final faltaOutra = falta != null && falta.aFrente.isNotEmpty;
    final ouvidas = falta != null && !faltaOutra;
    if (ouvidas) _oQueFaltaOuvir = null;
    state = state.copyWith(
      btClipEnded: ultima || ouvidas,
      btParteFronteira:
          faltaOutra || (!ultima && !(ouvidas && falta.paraNaUltima)),
      clearBtRecusa: ouvidas,
      btFimDasPartesMs: _fimDaParteMs,
      btParteNoArMs: 0,
    );
    if (ouvidas && state.btSoOuvir) {
      _handOff(_depoisDaPrimeiraEscuta(_generation));
    } else {
      _relatarAEscuta();
    }
    if (seguir &&
        state.btParteFronteira &&
        !state.btClipEnded &&
        state.btClipRodando) {
      _atravessar(doComeco: state.btPhase == BtPhase.conferida);
    }
  }

  /// Listen to the rehearsal, hold it, or cross into the next part; once a stretch is
  /// cut, or named by the verdict, hear that stretch again, and once its translation is
  /// pending, hear the translation.
  ///
  /// One gesture with one meaning. It used to share the circle with cutting a stretch and
  /// opening the microphone, which is why the room could only guess how much had been
  /// heard.
  void ouvirGravacao() => _gesture(() => _ouvirGravacao());

  void _ouvirGravacao() {
    if (state.station is! Retro) return;
    final conferida = state.btPhase == BtPhase.conferida;
    if (state.btPhase != BtPhase.playing && !conferida) return;
    if (state.needsPerson || !state.aBackTranslationGestureActs) return;
    if (state.btTrechoTocando || state.btRetroTocando) {
      _holdClip();
      return;
    }
    if (state.btTrechoPausada || state.btRetroPausada) {
      _letTheClipRun();
      return;
    }
    if (state.btClipRodando) {
      _pararOClipe();
      return;
    }
    final pendente = state.btTraducaoPendente;
    if (!conferida && pendente != null) {
      final segurada = _tirarAParteDoPlayer();
      _play(
        StretchSound(pendente, telling: true),
        onComplete: _calarOQueSeOuvia,
        onFailed: _calarOQueSeOuvia,
        beneath: segurada,
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
      _atravessar(doComeco: conferida);
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
    if (state.btSoOuvir && state.btClipEnded) {
      if (_oQueFaltaOuvir case _OQueFaltaOuvir(
        :final aFrente,
      ) when aFrente.isNotEmpty) {
        _ouvirAsPartes(aFrente, paraNaUltima: true);
      }
      return;
    }
    if (state.btClipEnded) return;
    _seguirOClipe();
  }

  void ouvirOTrechoContado(int indice) =>
      _gesture(() => _ouvirOTrechoContado(indice));

  void ouvirAConta(int indice) => _gesture(
    () =>
        state.canRetellAFrase &&
            state.btTrechos.elementAtOrNull(indice)?.segmentId != null
        ? _traduzirAFraseDeNovo(indice)
        : _ouvirOTrechoContado(indice, naGravacao: true),
  );

  void _ouvirOTrechoContado(int indice, {bool naGravacao = false}) {
    if (!state.canHearAFrase) return;
    if (indice < 0 || indice >= state.btTrechos.length) return;
    final trecho = state.btTrechos[indice];
    if (!trecho.contado) return;
    if (state.aParteDoTrecho(trecho) case final parte?) {
      if (state.partsAway[parte.takeId] == PartAway.missed) {
        state = state.copyWith(
          partsAway: {...state.partsAway, parte.takeId!: PartAway.coming},
        );
        _bringThePartsDown(state.station);
      }
      return;
    }
    final traducao = naGravacao ? null : trecho.retroPath;
    final materna = _ondeTocar(trecho);
    if (traducao == null && materna == null) return;
    final segurada = _tirarAParteDoPlayer();
    state = state.copyWith(btContaEscolhida: indice);
    _play(
      traducao != null
          ? StretchSound(traducao, named: trecho.segmentId, telling: true)
          : StretchSound(
              materna!.$1,
              named: trecho.segmentId,
              from: materna.$2,
              to: materna.$3,
            ),
      onComplete: _calarOQueSeOuvia,
      onFailed: _calarOQueSeOuvia,
      beneath: segurada,
    );
  }

  void ouvirOTrechoPendente() => _gesture(() => _ouvirOTrechoPendente());

  void abrirAChecagemExterna() => _gesture(() {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    if ((state.approvedDraftDrawn ?? state.approvedOnTheHome) == null) return;
    if (state.microphoneOpen || !state.aBackTranslationGestureActs) return;
    _handOff(_abrirAChecagemExterna(sessionId));
  });

  Future<void> _abrirAChecagemExterna(String sessionId) async {
    _silenceTheRoom();
    final generation = _waitOnTheGeneration;
    state = state.copyWith(clearAviso: true, btAbrindoAChecagem: generation);
    final RoomAnswer<ExternalCheck> answer;
    try {
      answer = await _room.openTheExternalCheck(sessionId);
    } finally {
      if (!_gone && state.btAbrindoAChecagem == generation) {
        state = state.copyWith(clearBtAbrindoAChecagem: true);
      }
    }
    if (_abandoned(generation)) return;
    switch (answer) {
      case Answered(value: final check):
        if (await _backToTheListener(sessionId, check, generation)) return;
        _arriveAt(TheExternalCheckOpened(check.version));
        state = state.copyWith(
          externalCheck: ExternalCheckScreen(takes: check.takes),
        );
      case Refused(code: RefusalCode.draftNotApproved):
        state = state.copyWith(btAviso: BtAviso.checagemNaoAbre);
        await _readTheStretchesBack(sessionId, generation);
      case final RoomFailure failure:
        _theCheckDidNotOpen(failure);
    }
  }

  /// A listener left before their retelling is stored is let go, and the next entry asks
  /// a new number; one whose retelling is in the air waits on its answer (ADR 0116).
  void leaveTheExternalCheck() => _gesture(() {
    if (state.station is! ChecagemExterna) return;
    final shown = state.externalCheck;
    if (shown.step != ListenerStep.done && !shown.sending) {
      _listenerInProgress = null;
    }
    _leaveTheExternalCheck();
  });

  /// A retelling still in the air when the team left decides the listener: one the room
  /// kept stays in progress, one it did not is let go.
  void _aRetellingLeftBehind(int version, int listener, RoomAnswer<void> sent) {
    if (sent case Answered()) return;
    if (_gone || _listenerInProgress != (version: version, number: listener)) {
      return;
    }
    _listenerInProgress = null;
    _rememberWhereTheyAre(state.station);
  }

  void _leaveTheExternalCheck() {
    final sessionId = state.sessionId;
    _silenceTheRoom();
    _dispatch(const MicDiscarded());
    _arriveAt(const TheExternalCheckLeft());
    _rememberWhereTheyAre(const Retro());
    if (sessionId != null) {
      unawaited(_readTheStretchesBack(sessionId, _waitOnTheGeneration));
    }
  }

  /// The listener this tablet remembers, back where the room's record says they stand,
  /// with nothing said or played. False when there is no one of [check]'s version to go
  /// back to; true when the read was handled, landed or not.
  Future<bool> _backToTheListener(
    String sessionId,
    ExternalCheck check,
    int generation,
  ) async {
    final remembered = _listenerInProgress;
    if (remembered == null) return false;
    if (remembered.version != check.version) {
      _listenerInProgress = null;
      _rememberWhereTheyAre(const Retro());
      return false;
    }
    final answer = await _room.theListener(
      sessionId,
      check.version,
      remembered.number,
    );
    if (_abandoned(generation)) return true;
    switch (answer) {
      case Answered(value: final record):
        _arriveAt(TheExternalCheckOpened(check.version));
        final ends = record.finished || record.hasRetelling;
        state = state.copyWith(
          externalCheck: ExternalCheckScreen(
            takes: check.takes,
            listener: remembered.number,
            step: ends ? ListenerStep.done : ListenerStep.retell,
            retellSaid: !ends,
            completed: ends ? true : null,
            finishAcknowledged: record.finished,
          ),
        );
        _rememberWhereTheyAre(ChecagemExterna(check.version));
        if (ends) unawaited(_sendTheFinish(_waitOnTheGeneration));
      case final RoomFailure failure:
        _theCheckDidNotOpen(failure);
    }
    return true;
  }

  void _showTheListener(ExternalCheckScreen shown) =>
      state = state.copyWith(externalCheck: shown);

  void newListener() => _gesture(() => _handOff(_newListener()));

  Future<void> _newListener() async {
    final sessionId = state.sessionId;
    final station = state.station;
    final shown = state.externalCheck;
    if (sessionId == null ||
        station is! ChecagemExterna ||
        shown.step != ListenerStep.idle ||
        shown.sending) {
      return;
    }
    final generation = _waitOnTheGeneration;
    final attempt = switch (_listenerAttempt) {
      (:final attempt, sessionId: final kept, version: final asked)
          when kept == sessionId && asked == station.version =>
        attempt,
      _ => mintAUuid(),
    };
    _listenerAttempt = (
      sessionId: sessionId,
      version: station.version,
      attempt: attempt,
    );
    _showTheListener(shown.copyWith(sending: true, clearLine: true));
    final answer = await _room.aNewListener(
      sessionId,
      station.version,
      attempt: attempt,
    );
    if (_abandoned(generation)) return;
    final asked = state.externalCheck.copyWith(sending: false);
    switch (answer) {
      case Answered(value: final number):
        _listenerAttempt = null;
        _showTheListener(
          asked.copyWith(listener: number, step: ListenerStep.playing),
        );
        _listenerInProgress = (version: station.version, number: number);
        _rememberWhereTheyAre(station);
        await _sayTheOpenLineThenThePassage(sessionId);
      case SessionGone() && final failure:
        _listenerAttempt = null;
        _decideTheFailure(failure);
      case NetworkFailed():
        _theNetworkFailedAt(Door.stretches);
        _showTheListener(asked.copyWith(line: ListenerLine.openFailed));
      case Refused():
        _listenerAttempt = null;
        _showTheListener(asked.copyWith(line: ListenerLine.openFailed));
    }
  }

  Future<List<String>?> _partsOfTheCheck(
    String sessionId,
    List<String> takes,
    int generation,
  ) async {
    final paths = <String>[];
    for (final take in takes) {
      final name = 'checagem-$take';
      final held = await _heldOnTheTablet(name);
      if (held != null) {
        paths.add(held);
        continue;
      }
      final clip = await _room.fetchClip(
        RoomRepository.takeAudioUrl(sessionId, take),
      );
      if (_abandoned(generation)) return null;
      switch (clip) {
        case Answered(:final value) when value.isNotEmpty:
          try {
            paths.add(await _recorder.keepBytes(value, name));
          } on FileSystemException {
            return null;
          }
        case Answered():
          return null;
        case final RoomFailure failure:
          _decideAt(failure, door: Door.stretches);
          return null;
      }
    }
    return paths;
  }

  void _hearTheWholePassage(List<String>? paths) {
    if (paths == null || paths.isEmpty) return _thePassageStalled();
    _silenceTheRoom();
    _showTheListener(state.externalCheck.copyWith(stalled: false));
    _playAll(
      [for (final (part, path) in paths.indexed) PartSound(part, path)],
      onComplete: _theListenerHeardItAll,
      onFailed: _thePassageStalled,
    );
    if (state.channel is! Playing) _thePassageStalled();
  }

  void _thePassageStalled() =>
      _showTheListener(state.externalCheck.copyWith(stalled: true));

  void _theListenerHeardItAll() {
    if (state.station is! ChecagemExterna ||
        state.externalCheck.step != ListenerStep.playing) {
      return;
    }
    _showTheListener(state.externalCheck.copyWith(step: ListenerStep.retell));
    _handOff(_sayTheRetellLine());
  }

  /// X-retell opens the circle once said, or once it cannot sound (her rule: the screen
  /// says it). A line a person's call cut is said again when the room is back.
  Future<void> _sayTheRetellLine() async {
    final heard = await _theListenerHeard(listenerRetellLine);
    if (!heard ||
        state.station is! ChecagemExterna ||
        state.externalCheck.step != ListenerStep.retell) {
      return;
    }
    _showTheListener(state.externalCheck.copyWith(retellSaid: true));
  }

  /// X-open, the consent, before the passage; a person's call that cuts it has it said
  /// again when the room is back, and only then does the passage play.
  Future<void> _sayTheOpenLineThenThePassage(String sessionId) async {
    final generation = _waitOnTheGeneration;
    final parts = _partsOfTheCheck(
      sessionId,
      state.externalCheck.takes,
      generation,
    );
    final heard = await _theListenerHeard(listenerOpenLine);
    if (!heard ||
        _abandoned(generation) ||
        state.station is! ChecagemExterna ||
        state.externalCheck.step != ListenerStep.playing) {
      return;
    }
    _showTheListener(state.externalCheck.copyWith(openSaid: true));
    final paths = await parts;
    if (_abandoned(generation)) return;
    _hearTheWholePassage(paths);
  }

  /// Whether one of her lines for the listener counts as heard: said, or unable to sound
  /// (her rule: the screen says it). Not when a person's call cut it.
  Future<bool> _theListenerHeard(String line) async {
    Said said;
    _listenerLineAwaited = true;
    try {
      said = await _sayTheLine(
        LineKind.guide,
        fixedLine: (name: line, language: _inTheSessionsLanguage),
      );
    } on RoomFailure catch (failure) {
      _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
      said = Said.failed;
    } finally {
      _listenerLineAwaited = false;
    }
    return said != Said.unsaid || state.halt is! Blocking;
  }

  void _followTheListener(Machine before, Machine after) {
    if (after.station is! ChecagemExterna) return;
    final shown = state.externalCheck;
    final halted = after.halt is Blocking && before.halt is! Blocking;
    final back =
        before.halt is Blocking &&
        after.halt is! Blocking &&
        !_listenerLineAwaited;
    final playing = shown.step == ListenerStep.playing;
    if (halted && playing && shown.openSaid) {
      _showTheListener(shown.copyWith(stalled: true));
    }
    final sessionId = state.sessionId;
    if (back && playing && !shown.openSaid && sessionId != null) {
      _handOff(_sayTheOpenLineThenThePassage(sessionId));
    }
    if (back && shown.step == ListenerStep.retell && !shown.retellSaid) {
      _handOff(_sayTheRetellLine());
    }
  }

  void hearTheWholePassageAgain() =>
      _gesture(() => _handOff(_hearTheWholePassageAgain()));

  Future<void> _hearTheWholePassageAgain() async {
    final sessionId = state.sessionId;
    if (sessionId == null || !state.listenerMayHearItAgain) return;
    final shown = state.externalCheck;
    final generation = _waitOnTheGeneration;
    final paths = await _partsOfTheCheck(sessionId, shown.takes, generation);
    if (_abandoned(generation)) return;
    _hearTheWholePassage(paths);
  }

  void listenerTap() => _gesture(() {
    if (_recordingStarting) return;
    if (state.listenerRecording) return _handOff(_keepTheRetelling());
    if (!state.listenerCircleOpen) return;
    _showTheListener(
      state.externalCheck.copyWith(
        clearLine: true,
        recordingSince: clock.now(),
      ),
    );
    _startListening('ouvinte_${_stamp()}', owner: MicOwner.listener);
  });

  Future<void> _keepTheRetelling() async {
    final generation = _waitOnTheGeneration;
    final sessionId = state.sessionId;
    final station = state.station;
    final listener = state.externalCheck.listener;
    _showTheListener(state.externalCheck.copyWith(sending: true));
    final String? path;
    try {
      path = (await _closeTheMicrophone()).take;
    } on Exception {
      _showTheListener(
        state.externalCheck.copyWith(sending: false, clearRecordingSince: true),
      );
      return;
    }
    final closed = state.externalCheck.copyWith(clearRecordingSince: true);
    if (path == null ||
        station is! ChecagemExterna ||
        sessionId == null ||
        listener == null ||
        _anAccidentalTap(path)) {
      _showTheListener(closed.copyWith(sending: false));
      if (path != null) unawaited(_recorder.delete(path));
      return;
    }
    _showTheListener(closed);
    final sent = await _room.sendTheListenerRecording(
      sessionId,
      station.version,
      listener,
      File(path),
      kind: listenerRetelling,
    );
    unawaited(_recorder.delete(path));
    if (_abandoned(generation)) {
      return _aRetellingLeftBehind(station.version, listener, sent);
    }
    final answered = state.externalCheck.copyWith(sending: false);
    switch (sent) {
      case Answered():
        _showTheListener(answered);
        _theListenerIsDone(completed: true);
      case SessionGone() && final failure:
        _decideTheFailure(failure);
      case NetworkFailed():
        _theNetworkFailedAt(Door.stretches);
        _showTheListener(answered.copyWith(line: ListenerLine.clipFailed));
      case Refused():
        _showTheListener(answered.copyWith(line: ListenerLine.clipFailed));
    }
  }

  /// The listener ends: her thanks, and the room told how they ended.
  void _theListenerIsDone({required bool completed}) {
    if (state.station is! ChecagemExterna ||
        state.externalCheck.listener == null) {
      return;
    }
    _silenceTheRoom();
    _showTheListener(
      state.externalCheck.copyWith(
        step: ListenerStep.done,
        completed: completed,
        finishAcknowledged: false,
        clearLine: true,
      ),
    );
    unawaited(_sendTheFinish(_waitOnTheGeneration));
    _handOff(_sayTheThanks());
  }

  Future<void> _sayTheThanks() async {
    try {
      await _sayALine(
        LineKind.guide,
        fixedLine: (name: listenerThanksLine, language: _inTheSessionsLanguage),
      );
    } on RoomFailure catch (failure) {
      _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
    }
  }

  /// Tells the room the listener finished, unless it already acknowledged it. The end
  /// screen's buttons wait while it is in the air; a send that fails holds no one, and the
  /// next button sends it again.
  Future<void> _sendTheFinish(int generation) async {
    final sessionId = state.sessionId;
    final station = state.station;
    final shown = state.externalCheck;
    final listener = shown.listener;
    final completed = shown.completed;
    if (sessionId == null ||
        station is! ChecagemExterna ||
        listener == null ||
        completed == null ||
        shown.finishAcknowledged) {
      return;
    }
    _showTheListener(shown.copyWith(sending: true));
    final answer = await _room.finishTheListener(
      sessionId,
      station.version,
      listener,
      completed: completed,
    );
    if (_abandoned(generation)) return;
    final sent = state.externalCheck.copyWith(sending: false);
    switch (answer) {
      case Answered():
        _showTheListener(sent.copyWith(finishAcknowledged: true));
      case SessionGone() && final failure:
        _decideTheFailure(failure);
      case NetworkFailed():
        _showTheListener(sent);
        _theNetworkFailedAt(Door.stretches);
      case Refused():
        _showTheListener(sent);
    }
  }

  void anotherListener() => _gesture(() => _handOff(_anotherListener()));

  Future<void> _anotherListener() async {
    final station = state.station;
    final shown = state.externalCheck;
    if (station is! ChecagemExterna ||
        shown.step != ListenerStep.done ||
        shown.sending) {
      return;
    }
    final generation = _waitOnTheGeneration;
    _silenceTheRoom();
    await _sendTheFinish(generation);
    if (_abandoned(generation)) return;
    _listenerInProgress = null;
    _showTheListener(ExternalCheckScreen(takes: shown.takes));
    _rememberWhereTheyAre(station);
    await _newListener();
  }

  void finishTheCheck() => _gesture(() => _handOff(_finishTheCheck()));

  Future<void> _finishTheCheck() async {
    final shown = state.externalCheck;
    if (state.station is! ChecagemExterna ||
        shown.step != ListenerStep.done ||
        shown.sending) {
      return;
    }
    final generation = _waitOnTheGeneration;
    _silenceTheRoom();
    await _sendTheFinish(generation);
    if (_abandoned(generation)) return;
    _listenerInProgress = null;
    _leaveTheExternalCheck();
  }

  void recomecarATraducao() => _gesture(() => _recomecarATraducao());

  void _recomecarATraducao() {
    final sessionId = state.sessionId;
    if (state.station is! Retro || sessionId == null) return;
    if (!state.aBackTranslationGestureActs) return;
    if (state.btPhase == BtPhase.capturing ||
        state.btPhase == BtPhase.thinking) {
      return;
    }
    if (state.btRegravacao?.passo
        case PassoDaRegravacao.gravando || PassoDaRegravacao.enviando) {
      return;
    }
    _armedTap(
      'restart',
      needs: true,
      then: () => _handOff(_recomecarNaSala(sessionId)),
    );
  }

  Future<void> _recomecarNaSala(String sessionId) async {
    final generation = _waitOnTheGeneration;
    final antes = state.btPhase;
    _silenceTheRoom();
    state = state.copyWith(btPhase: BtPhase.thinking);
    final recomecada = await _room.startTheTranslationOver(sessionId);
    if (_abandoned(generation)) return;
    switch (recomecada) {
      case Answered(value: final segmentos):
        _clearAll();
        _theTellingStartsOver(_trechosFrom(segmentos));
        state = state.copyWith(btRecomecada: true);
        _dispatch(const TheTranslationStartedOver());

        _after(
          'recomecada',
          ref.read(restartLapseProvider),
          () => state = state.copyWith(btRecomecada: false),
        );
        final agora = _generation;
        try {
          await _sayALine(
            LineKind.guide,
            fixedLine: (name: tellLine, language: _inTheSessionsLanguage),
          );
        } on RoomFailure catch (failure) {
          _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
        }
        if (_abandoned(agora)) return;
        state = state.copyWith(btPhase: BtPhase.playing);
        await _playFromTheUntoldGround(agora);
      case final RoomFailure failure:
        state = state.copyWith(btPhase: antes, btAviso: BtAviso.recomecoFalhou);
        _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
    }
  }

  void _theTellingStartsOver(List<Trecho> trechos) {
    _descartarATraducaoPendente();
    _esquecerAFrase();
    state = state.copyWith(
      btTrechos: trechos,
      btTrechosRegravados: const [],
      btFindings: const [],
      clearTrechoTraduzidoDeNovo: true,
      btChunkFailures: const [],
      btClipEnded: false,
      clearBtRecusa: true,
    );
  }

  void _ouvirOTrechoPendente() {
    if (state.btContaEscolhida != null) {
      _silenceTheRoom();
      return;
    }
    ouvirGravacao();
  }

  Paused? _tirarAParteDoPlayer() {
    final segurada = _aParteSegurada;
    _silenceTheRoom();
    if (segurada != null) return segurada;
    final parte = _parteNoAr;
    if (parte == null) return null;
    return Paused(
      PartSound(
        _parteTocando,
        parte.path,
        from: Duration(
          milliseconds: state.btOuvidoMs - _inicioDaParteMs(_parteTocando),
        ),
      ),
      started: false,
    );
  }

  void _calarOQueSeOuvia() {
    unawaited(_playback.stop());
    state = state.copyWith(clearContaEscolhida: true);
  }

  void _ouvirOTrechoCortado() {
    final parte = _parteNoAr;
    if (parte == null) return;
    _silenceTheRoom();
    _play(
      StretchSound(parte.path, from: _trechoStart, to: _trechoEnd),
      onComplete: _quietTheStretch,
      onFailed: _quietTheStretch,
    );
  }

  void _quietTheStretch() => unawaited(_playback.stop());

  Duration? _aPausaNo(Duration toque) {
    final noFim = state.btParteFronteira || state.btClipEnded;
    final ondeCabe = noFim ? null : _ondeAPausaCabe();
    state = state.copyWith(btPausaAjustavel: ondeCabe != null);
    if (noFim) return toque;
    if (ondeCabe == null) {
      final parte = _parteNoAr;
      return pauseAtTheTap(
        toque,
        _trechoStart,
        parte == null ? null : _oTamanhoDa(parte),
      );
    }
    final (envelope, :lo, :hi) = ondeCabe;
    return placeThePause(envelope, toque, lo: lo, hi: hi);
  }

  Duration? _oTamanhoDa(KeptTake parte) {
    final medido = _tamanhoDaParteMs[parte.path];
    if (medido != null) return Duration(milliseconds: medido);
    return _envelopeOf(parte.path)?.length;
  }

  (Envelope, {Duration lo, Duration hi})? _ondeAPausaCabe() {
    final parte = _parteNoAr;
    if (parte == null) return null;
    final envelope = _envelopeOf(parte.path);
    final tamanho = _oTamanhoDa(parte);
    if (envelope == null || tamanho == null) return null;
    final limites = pauseBounds(_trechoStart, tamanho);
    if (limites == null) return null;
    return (envelope, lo: limites.lo, hi: limites.hi);
  }

  void pausaUmPoucoAntes() => _gesture(() => _moverAPausa(Nudge.earlier));

  void pausaUmPoucoDepois() => _gesture(() => _moverAPausa(Nudge.later));

  void _moverAPausa(Nudge para) {
    if (!state.canAdjustThePause) return;
    final ondeCabe = _ondeAPausaCabe();
    if (ondeCabe == null) return;
    final (envelope, :lo, :hi) = ondeCabe;
    _semOTrechoNoAr();
    _trechoEnd = nudgeThePause(envelope, _trechoEnd, para, lo: lo, hi: hi);
  }

  void _semOTrechoNoAr() {
    final segurada = _tirarAParteDoPlayer();
    if (segurada != null) _dispatch(TheHeldPartReturns(segurada));
  }

  void ouvirAPausa() => _gesture(() => _ouvirAPausa());

  void _ouvirAPausa() {
    if (!state.canAdjustThePause) return;
    final parte = _parteNoAr;
    if (parte == null) return;
    final segurada = _tirarAParteDoPlayer();
    _play(
      StretchSound(
        parte.path,
        from: theMomentBefore(_trechoEnd, _trechoStart),
        to: _trechoEnd,
      ),
      onComplete: _quietTheStretch,
      onFailed: _quietTheStretch,
      beneath: segurada,
    );
  }

  Duration get _cabeca {
    if (state.btParteFronteira || state.btClipEnded) {
      final medido = _tamanhoDaParteMs[_parteNoAr?.path];
      if (medido != null) return Duration(milliseconds: medido);
    }
    return _aCabecaDaParte ?? _playback.position;
  }

  /// Arm a one-shot deadline for the moment the head will pass the cursor, read from the
  /// position of the clip that has just finished opening — never from whatever the
  /// previous clip's position happened to be, which is still what `_playback.position`
  /// answers for the instant between a new source being asked for and its `openings`
  /// event landing.
  ///
  /// `SalaSessionState.nothingHeardSinceCursor` is what the circle's label reads — a
  /// plain field, the way `canConfirmTranslation` is, because nothing else
  /// in state changes while a part simply plays on, and a label baked from a live read at
  /// the last state change would go stale the moment the room stopped touching state for
  /// it. The pausa and the capture do not read this field: a fact this timer can only
  /// answer to the nearest hundred milliseconds is not the belt a cut's own boundary
  /// needs, so both still read `_cabeca` live, as they always have.
  void _armCursorDeadline() {
    _timers.remove('cursor')?.cancel();
    if (_writeCursorCrossingNow() || _theClipEndsByTheCursor) return;
    final restante = _trechoStart - _cabeca;
    _after(
      'cursor',
      restante > _umInstanteOuvido ? restante : _umInstanteOuvido,
      () => state = state.copyWith(btOuvidoAlemDoCursor: true),
    );
  }

  /// A part told back to its end, landed on again, plays from its own end: its head can
  /// never pass the cursor, so no deadline may say it did.
  bool get _theClipEndsByTheCursor {
    final medido = _tamanhoDaParteMs[_parteNoAr?.path];
    return medido != null && Duration(milliseconds: medido) <= _trechoStart;
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
    int generation,
  ) async {
    // Read before the room is asked, not after. The place is what the successor is found
    // by, and asking for it on the far side of the wait would be asking a list that the
    // wait itself is there to change.
    final lugar = state.btTrechos.indexWhere(
      (trecho) => trecho.segmentId == alvo.segmentId,
    );
    final life = _thisLife;
    final RoomAnswer<TellingAgain> replaced;
    try {
      replaced = await _underItsKey(
        generation,
        path,
        (key) => _room.replaceSegment(
          sessionId,
          alvo.segmentId!,
          File(path),
          takeId: alvo.takeId,
          from: alvo.from,
          to: _trechoEnd,
          idempotencyKey: key,
        ),
      );
    } on FileSystemException {
      _guardarATraducao(path, life);
      if (_abandoned(generation)) return;
      state = state.copyWith(
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      return _theStepsNetworkFailed();
    }
    final TellingAgain told;
    switch (replaced) {
      case Answered(value: final answer):
        if (_abandoned(generation)) return;
        told = answer;
      case Refused(code: RefusalCode.stretchNoLongerCounts):
        if (_abandoned(generation)) return;
        await _readWhatTheRefusalSays(alvo, path, sessionId, generation);
        return;
      case Refused(
        code: final code &&
            (RefusalCode.pauseOnlyOnTheLastFrase ||
                RefusalCode.pausePastTheEnd ||
                RefusalCode.pauseCannotStandThere),
      ):
        if (_abandoned(generation)) return;
        await _aPausaNaoFoi(code, sessionId, generation);
        return;
      case final RoomFailure failure:
        if (failure case NetworkFailed()) {
          (_perdidasNoTrecho[alvo.segmentId!] ??= {}).add(path);
        }
        _guardarATraducao(path, life);
        if (_abandoned(generation)) return;
        _theCorrectionFailed(failure);
        return;
    }

    _theTellingLandedOn(
      told.segments,
      alvo: alvo,
      lugar: lugar,
      path: path,
      needsPerson: told.needsPerson,
    );
  }

  void _theCorrectionFailed(RoomFailure failure) {
    state = state.copyWith(
      btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
    );
    _leaveThinking();
    _decideAt(
      failure,
      door: switch (failure) {
        NetworkFailed(reason: RefusalCode.idempotencyKeyInFlight) => Door.step,
        _ => Door.telling,
      },
    );
  }

  Future<void> _readWhatTheRefusalSays(
    Trecho alvo,
    String path,
    String sessionId,
    int generation,
  ) async {
    final SessionSnapshot snapshot;
    final life = _thisLife;
    final sent = ++_readsSent;
    switch (await _room.fetchState(sessionId)) {
      case Answered(value: final read):
        snapshot = read;
      case final RoomFailure failure:
        _guardarATraducao(path, life);
        if (_abandoned(generation)) return;
        _theCorrectionFailed(failure);
        return;
    }
    if (_abandoned(generation)) return;
    final seguir = _theRefusalLandsOn(snapshot, alvo, sent);
    _applyTheSessionRead(snapshot, sent);
    if (seguir) await _confirmarTraducao();
  }

  Future<void> _readWhatTheChunkRefusalSays(
    Refused refusal,
    String path,
    String sessionId,
    int generation,
  ) async {
    _watchBusyState();
    final life = _thisLife;
    final sent = ++_readsSent;
    switch (await _room.fetchState(sessionId)) {
      case Answered(value: final snapshot):
        final unread = await _keepTheCurrentTakes(
          refusal,
          sessionId,
          generation,
        );
        if (unread != null) {
          return _theRefusalCouldNotBeRead(path, unread, generation, life);
        }
        if (_abandoned(generation)) return;
        _theStretchIsGone(snapshot.backTranslation.segments, sent);
        _applyTheSessionRead(snapshot, sent);
      case final RoomFailure failure:
        _theRefusalCouldNotBeRead(path, failure, generation, life);
    }
  }

  void _theRefusalCouldNotBeRead(
    String path,
    RoomFailure failure,
    int generation,
    int? life,
  ) {
    _guardarATraducao(path, life);
    if (_abandoned(generation)) return;
    _theCorrectionFailed(failure);
  }

  Future<RoomFailure?> _keepTheCurrentTakes(
    Refused refusal,
    String sessionId,
    int generation,
  ) async {
    switch (await _room.takesOf(sessionId)) {
      case Answered(value: final guardadas):
        switch (await _asPartesDaSala(
          sessionId,
          guardadas,
          state.keptTakes,
          generation,
        )) {
          case Answered(value: final lidas?) when lidas.inteiro:
            if (_abandoned(generation)) return null;
            state = state.copyWith(
              keptTakes: lidas.partes,
              wholeHeldByTheRoom: lidas.deLado,
            );
            await _medirAsPartes(lidas.partes, generation);
            return null;
          case Answered():
            return refusal;
          case final RoomFailure failure:
            return failure;
        }
      case final RoomFailure failure:
        return failure;
    }
  }

  Future<void> _aPausaNaoFoi(
    String code,
    String sessionId,
    int generation,
  ) async {
    _trechoTraduzidoDeNovo = null;
    _descartarATraducaoPendente();
    _walkTheCursorBack(state.btTrechos);
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btAviso: switch (code) {
        RefusalCode.pauseOnlyOnTheLastFrase => BtAviso.pausaSoNaUltima,
        RefusalCode.pausePastTheEnd => BtAviso.pausaPassaDoFim,
        _ => BtAviso.pausaNaoFica,
      },
    );
    final sent = ++_readsSent;
    final lido = await _room.fetchState(sessionId);
    if (_abandoned(generation)) return;
    switch (lido) {
      case Answered(value: final snapshot):
        _theStretchIsGone(snapshot.backTranslation.segments, sent);
        _applyTheSessionRead(snapshot, sent);
      case final RoomFailure failure:
        _decideAt(failure, door: Door.stretches, rule: RefusalRule.passes);
    }
  }

  bool _theRefusalLandsOn(SessionSnapshot snapshot, Trecho alvo, int sent) {
    final segments = snapshot.backTranslation.segments;
    final sucessor = segments.indexWhere(
      (segment) =>
          segment.told &&
          segment.segmentId != alvo.segmentId &&
          segment.takeId == alvo.takeId &&
          segment.startsMs == alvo.from.inMilliseconds &&
          segment.endsMs == alvo.to.inMilliseconds,
    );
    for (final perdida in _perdidasNoTrecho.remove(alvo.segmentId) ?? {}) {
      unawaited(_retirarDaFilaSeGuardada(perdida));
    }
    if (sucessor < 0) {
      _theStretchIsGone(segments, sent);
      return false;
    }
    final fresh = sent > _stretchesAt;
    final List<Trecho> trechos;
    final int lugar;
    if (fresh) {
      _stretchesAt = sent;
      trechos = _trechosFrom(segments, lugar: sucessor, noLugarDe: alvo);
      lugar = sucessor;
    } else {
      trechos = state.btTrechos;
      lugar = trechos.indexWhere(
        (trecho) =>
            trecho.segmentId != alvo.segmentId &&
            trecho.takeId == alvo.takeId &&
            trecho.from == alvo.from &&
            trecho.to == alvo.to,
      );
      if (lugar < 0) {
        _theStretchIsGone(segments, sent);
        return false;
      }
    }
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTrechos: trechos,
    );
    _armarOTrecho(trechos[lugar]);
    _rememberWhereTheyAre(const Retro());
    return true;
  }

  void _theStretchIsGone(List<SegmentView> segments, int sent) {
    final fresh = sent > _stretchesAt;
    if (fresh) _stretchesAt = sent;
    final trechos = fresh ? _trechosFrom(segments) : state.btTrechos;
    _walkTheCursorBack(trechos);
    _trechoTraduzidoDeNovo = null;
    _descartarATraducaoPendente();
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTrechos: trechos,
    );
    _rememberWhereTheyAre(const Retro());
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
    _stretchesAt = _readsSent;
    _trechoTraduzidoDeNovo = null;
    unawaited(_retirarDaFilaSeGuardada(path));
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTrechos: trechos.isEmpty ? state.btTrechos : trechos,
      clearTraducaoPendente: true,
      clearBtFraseQueAguarda:
          alvo.segmentId != null && alvo.segmentId == state.btFraseQueAguarda,
      btFindings: [
        for (final finding in state.btFindings)
          if (alvo.frase == null || finding.frase != alvo.frase) finding,
      ],
    );
    if (needsPerson) _dispatch(TheAnswerWarned(generation: _generation));
    _rememberWhereTheyAre(const Retro());
  }

  /// Put the cursor back on the furthest stretch told on the part in the air or after it.
  ///
  /// Telling a stretch again adds no new ground, so the cursor goes back rather than
  /// staying where the excursion left it. The ordinary path walks it forward past what
  /// was just told; here there is nothing to walk past, and a cursor left behind makes
  /// the next cut begin inside ground already explained.
  ///
  /// The furthest stretch of every part used to be the answer, and a frase told again in
  /// the middle of part 2 put the cursor at the end of part 1, where part 2 took no pause
  /// until the head passed it. The part in the air keeps its own ground now, as hers keeps
  /// one frontier per take. A part a later part was already told past still goes back to
  /// the furthest stretch of them all, and a part with nothing told goes back to its start.
  void _walkTheCursorBack(List<Trecho> trechos) {
    final alcancado = trechos.fold(
      Duration.zero,
      (ate, trecho) =>
          trecho.parte >= _parteTocando && trecho.to > ate ? trecho.to : ate,
    );
    _trechoStart = alcancado;
    _trechoEnd = alcancado;
  }

  void regravarAFrase(Trecho trecho) => _gesture(() {
    if (!state.aBackTranslationGestureActs) return;
    final reabre = state.overAnApprovedDraft;
    _armedTap(
      'rerecord:${trecho.frase}',
      needs: reabre && state.btRegravacao == null,
      then: () => _handOff(_regravarAFrase(trecho, reabre: reabre)),
    );
  });

  Future<void> _regravarAFrase(Trecho trecho, {required bool reabre}) async {
    final frase = trecho.frase;
    if (frase == null || !state.fraseRegravavel(trecho)) return;
    final aberta = state.btRegravacao;
    if (aberta != null) {
      if (aberta.frase == frase) _fecharARegravacao();
      return;
    }
    final generation = _waitOnTheGeneration;
    final vez = ++_regravacoes;
    bool largada() => _abandoned(generation) || vez != _regravacoes;
    final primeira = !_regravouNestaVisita;
    _silenceTheRoom();
    state = state.copyWith(
      btRegravacao: RegravacaoDaFrase(
        frase,
        PassoDaRegravacao.ouvindo,
        reabre: reabre,
      ),
    );
    if (primeira) {
      await _sayALine(
        LineKind.guide,
        fixedLine: (name: sentenceListenLine, language: _inTheSessionsLanguage),
      );
    }
    if (largada()) return;
    final ouvida = Completer<void>();
    void ouviu() {
      if (!ouvida.isCompleted) ouvida.complete();
    }

    _tocarOTrecho(trecho, depois: ouviu);
    _after(
      'frase',
      trecho.to - trecho.from + ref.read(sentenceGraceProvider),
      ouviu,
    );
    await ouvida.future;
    _timers.remove('frase')?.cancel();
    if (largada()) return;
    _silenceTheRoom();
    if (primeira) {
      await _sayALine(
        LineKind.guide,
        fixedLine: (name: sentenceRecordLine, language: _inTheSessionsLanguage),
      );
    }
    if (largada()) return;
    _regravouNestaVisita = true;
    state = state.copyWith(
      btRegravacao: state.btRegravacao?.em(PassoDaRegravacao.pronta),
    );
  }

  Future<void> _fecharAFrase(int frase) async {
    final aberta = state.btRegravacao;
    final generation = _waitOnTheGeneration;
    final vez = _regravacoes;
    bool largada() => _abandoned(generation) || vez != _regravacoes;
    final path = (await _closeTheMicrophone()).take;
    if (largada()) return;
    if (path == null || _anAccidentalTap(path)) {
      if (path != null) unawaited(_recorder.delete(path));
      state = state.copyWith(
        btRegravacao: aberta?.em(PassoDaRegravacao.pronta),
      );
      return;
    }
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    if (_fraseNaFila case final antiga?) unawaited(_takes.withdraw(antiga));
    final guardada = await _takes.enqueue(
      File(path),
      sessionId: sessionId,
      kind: sentenceKind,
      scope: '$frase',
    );
    if (largada()) return;
    _fraseNaFila = guardada;
    state = state.copyWith(
      btRegravacao: aberta?.em(PassoDaRegravacao.revendo, path: path),
      clearBtFraseGuardada: true,
    );
  }

  late PendingTake? _fraseNaFila;

  void usarEstaFrase() => _gesture(() => _handOff(_usarEstaFrase()));

  Future<void> _usarEstaFrase() async {
    final guardada = _fraseNaFila;
    if (!state.aBackTranslationGestureActs ||
        state.btRegravacao?.passo != PassoDaRegravacao.revendo ||
        guardada == null) {
      return;
    }
    _silenceTheRoom();
    await _enviarAFrase(guardada, reabre: state.btRegravacao?.reabre ?? false);
  }

  Future<void> _enviarAFrase(
    PendingTake guardada, {
    required bool reabre,
  }) async {
    final frase = int.parse(guardada.scope);
    final generation = _waitOnTheGeneration;
    state = state.copyWith(
      btRegravacao: RegravacaoDaFrase(
        frase,
        PassoDaRegravacao.enviando,
        path: guardada.path,
        reabre: reabre,
      ),
      clearBtFraseGuardada: true,
    );
    if (File(guardada.path).lengthSync() > largestSentenceTheRoomTakes) {
      return _largarAFrase(guardada, PassoDaRegravacao.longaDemais);
    }
    var nome = _aFrase(frase)?.segmentId;
    if (nome == null) {
      await _readTheStretchesBack(guardada.sessionId, generation);
      if (_abandoned(generation)) return;
      nome = _aFrase(frase)?.segmentId;
    }
    if (nome == null) return _guardarAFrase(frase);
    final resposta = await _room.reRecordTheSentence(
      guardada.sessionId,
      nome,
      File(guardada.path),
      sentenceId: guardada.id,
      reopensTheApprovedDraft: reabre,
    );
    if (_abandoned(generation)) return;
    switch (resposta) {
      case Refused(code: RefusalCode.sentenceTooLong):
        _largarAFrase(guardada, PassoDaRegravacao.longaDemais);
      case Refused(
        code: RefusalCode.sentenceTooShort || RefusalCode.sentenceFormatDiffers,
      ):
        _largarAFrase(guardada, PassoDaRegravacao.pronta);
      case Answered(value: final laid):
        await _aFraseNoLugar(guardada, nome, laid.segments, generation);
        if (reabre && !_abandoned(generation)) {
          await _readTheStretchesBack(guardada.sessionId, generation);
        }
      case Refused(code: RefusalCode.draftApproved):
        _guardarAFrase(frase);
        await _readTheStretchesBack(guardada.sessionId, generation);
      case Refused(
        code: RefusalCode.stretchNoLongerCounts ||
            RefusalCode.partNotWav ||
            RefusalCode.sentenceIdReused,
      ):
        _fraseNaFila = null;
        unawaited(_takes.withdraw(guardada));
        state = state.copyWith(clearBtRegravacao: true);
        await _readTheStretchesBack(guardada.sessionId, generation);
      case Refused(code: RefusalCode.anotherSentenceAwaits):
        _guardarAFrase(frase);
        await _readTheStretchesBack(guardada.sessionId, generation);
        if (_abandoned(generation)) return;
        if (state.btFraseQueAguarda case final aguardando?) {
          await _voltarAFraseQueAguarda(aguardando, generation);
        }
      case final RoomFailure failure:
        _guardarAFrase(frase);
        _decideTheFailure(failure);
    }
  }

  Future<void> _aFraseNoLugar(
    PendingTake guardada,
    String nome,
    List<SegmentView> segments,
    int generation,
  ) async {
    _fraseNaFila = null;
    unawaited(_takes.withdraw(guardada));
    _stretchesAt = _readsSent;
    final frase = int.parse(guardada.scope);
    final parte = state.trechoChamado(nome)?.parte;
    final nova = segments.where((segment) => segment.segmentId == nome);
    var trocada = false;
    if (parte != null && nova.isNotEmpty) {
      trocada = await _aParteComAFrase(
        guardada.sessionId,
        parte,
        nova.first.takeId,
        generation,
      );
      if (_abandoned(generation)) return;
    }
    final trechos = _trechosFrom(segments);
    state = state.copyWith(
      clearBtRegravacao: true,
      btFraseQueAguarda: nome,
      btTrechos: trechos.isEmpty ? state.btTrechos : trechos,
      btPhase: BtPhase.playing,
      clearFindingSegment: true,
      btFindings: [
        for (final finding in state.btFindings)
          if (finding.frase != frase) finding,
      ],
    );
    _rememberWhereTheyAre(const Retro());
    await _sayALine(
      LineKind.guide,
      fixedLine: (name: sentenceInPlaceLine, language: _inTheSessionsLanguage),
    );
    if (_abandoned(generation)) return;
    final trecho = _armarOTrecho(state.trechoChamado(nome));
    if (trecho != null && trocada) _tocarAFraseNova(trecho);
  }

  Future<bool> _aParteComAFrase(
    String sessionId,
    int parte,
    String takeId,
    int generation,
  ) async {
    final clip = await _room.fetchClip(
      RoomRepository.takeAudioUrl(sessionId, takeId),
    );
    if (_abandoned(generation)) return false;
    if (clip case Answered(:final value) when value.isNotEmpty) {
      final antiga = state.partes[parte];
      final String arquivo;
      try {
        arquivo = await _recorder.keepBytes(value, '${antiga.scopeId}-$takeId');
      } on Exception {
        return false;
      }
      if (_abandoned(generation)) return false;
      state = state.copyWith(
        keptTakes: [
          for (final take in state.keptTakes)
            identical(take, antiga)
                ? KeptTake(
                    scopeId: antiga.scopeId,
                    path: arquivo,
                    takeId: takeId,
                    pass: antiga.pass,
                    origin: antiga.origin,
                  )
                : take,
        ],
      );
      await _medirAsPartes(state.partes, generation);
      return true;
    }
    return false;
  }

  void _tocarAFraseNova(Trecho trecho) {
    final onde = _ondeTocar(trecho);
    if (onde == null) return;
    final (path, from, to) = onde;
    final de = from > emVoltaDaFraseNova
        ? from - emVoltaDaFraseNova
        : Duration.zero;
    final ate = to + emVoltaDaFraseNova;
    void quiet() => unawaited(_playback.stop());
    _play(
      StretchSound(path, named: trecho.segmentId, from: de, to: ate),
      onComplete: () {
        quiet();
        _escuta.abrir(path, de.inMilliseconds);
        _escuta.fechar(path, ate.inMilliseconds);
        if (_tamanhoDaParteMs[path] case final medido?) {
          _escuta.medida(path, medido);
        }
      },
      onFailed: quiet,
    );
  }

  Future<void> _lembrarDaFraseGuardada(String sessionId) async {
    final guardada = await _takes.sentenceHeldIn(sessionId);
    if (guardada == null || state.sessionId != sessionId) return;
    _fraseNaFila = guardada;
    state = state.copyWith(btFraseGuardada: int.parse(guardada.scope));
  }

  void _esquecerAFrase() {
    if (state.btRegravacao?.path case final path?) {
      unawaited(_recorder.delete(path));
    }
    if (_fraseNaFila case final guardada?) {
      _fraseNaFila = null;
      unawaited(_takes.withdraw(guardada));
    }
    state = state.copyWith(
      clearBtRegravacao: true,
      clearBtFraseQueAguarda: true,
      clearBtFraseGuardada: true,
    );
  }

  void _guardarAFrase(int frase) {
    state = state.copyWith(clearBtRegravacao: true, btFraseGuardada: frase);
  }

  void tentarAFraseDeNovo() => _gesture(() {
    if (!state.aBackTranslationGestureActs) return;
    final reabre = state.overAnApprovedDraft;
    _armedTap(
      'resend:${state.btFraseGuardada}',
      needs: reabre,
      then: () => _handOff(_tentarAFraseDeNovo(reabre: reabre)),
    );
  });

  Future<void> _tentarAFraseDeNovo({required bool reabre}) async {
    final guardada = _fraseNaFila;
    if (!state.aBackTranslationGestureActs ||
        state.btRegravacao != null ||
        state.btFraseGuardada == null ||
        guardada == null) {
      return;
    }
    _silenceTheRoom();
    await _enviarAFrase(guardada, reabre: reabre);
  }

  void _largarAFrase(PendingTake guardada, PassoDaRegravacao passo) {
    _fraseNaFila = null;
    unawaited(_takes.withdraw(guardada));
    state = state.copyWith(btRegravacao: state.btRegravacao?.em(passo));
  }

  int? _numeroDaParteDe(int frase) {
    final parte = _aFrase(frase)?.parte;
    if (parte == null || parte >= state.partes.length) return null;
    return KeptScope.numberOf(state.partes[parte].scopeId) ?? parte + 1;
  }

  Trecho? _aFrase(int frase) =>
      state.btTrechos.where((trecho) => trecho.frase == frase).firstOrNull;

  void ouvirAFraseGravada() => _gesture(() {
    final path = state.btRegravacao?.path;
    if (path == null || !state.aBackTranslationGestureActs) return;
    _silenceTheRoom();
    void quiet() => unawaited(_playback.stop());
    _play(StretchSound(path), onComplete: quiet, onFailed: quiet);
  });

  void gravarAFraseDeNovo() => _gesture(() {
    final regravacao = state.btRegravacao;
    if (!state.aBackTranslationGestureActs ||
        regravacao == null ||
        regravacao.passo != PassoDaRegravacao.revendo) {
      return;
    }
    _silenceTheRoom();
    if (regravacao.path case final path?) unawaited(_recorder.delete(path));
    if (_fraseNaFila case final antiga?) {
      _fraseNaFila = null;
      unawaited(_takes.withdraw(antiga));
    }
    state = state.copyWith(
      btRegravacao: regravacao.em(PassoDaRegravacao.pronta),
    );
  });

  late int _regravacoes;

  late bool _regravouNestaVisita;

  void _fecharARegravacao() {
    _silenceTheRoom();
    _largarARegravacao();
  }

  void _largarARegravacao() {
    _regravacoes++;
    final aberta = state.btRegravacao;
    state = state.copyWith(clearBtRegravacao: true);
    if (aberta case RegravacaoDaFrase(
      passo: PassoDaRegravacao.revendo,
      :final frase,
    ) when _fraseNaFila != null) {
      _guardarAFrase(frase);
    }
  }

  void ouvirARespostaDeNovo() => _gesture(() => _ouvirARespostaDeNovo());

  void _ouvirARespostaDeNovo() {
    final line = state.lastSpoken;
    if (!state.canHearTheVerdictAgain || line == null) return;
    _silenceTheRoom();
    _handOff(_repeatLastSpoken(line));
  }

  void retroTap() => _gesture(() => _retroTap());

  void _retroTap() {
    if (state.station is! Retro) return;
    if (state.needsPerson || !state.aBackTranslationGestureActs) return;
    if (state.btSoOuvir) return;
    if (state.btRegravacao case final regravacao?) {
      switch (regravacao.passo) {
        case PassoDaRegravacao.pronta:
          _silenceTheRoom();
          state = state.copyWith(
            btRegravacao: regravacao.em(PassoDaRegravacao.gravando),
          );
          _dispatch(
            MicOpened(
              MicOwner.rehearsal,
              take: 'frase_${regravacao.frase}_${_stamp()}',
              generation: _generation,
            ),
          );
        case PassoDaRegravacao.gravando:
          _handOff(_fecharAFrase(regravacao.frase));
        case PassoDaRegravacao.ouvindo ||
            PassoDaRegravacao.revendo ||
            PassoDaRegravacao.enviando ||
            PassoDaRegravacao.longaDemais:
          break;
      }
      return;
    }
    switch (state.btPhase) {
      case BtPhase.playing:
        _abrirACaptura();
      case BtPhase.capturing:
        // Held, not stopped: the stretch the team has just told ends inside the part
        // that is still open behind it, and the next listening carries that same part
        // on. Stopped, the room loses the length the end of the part is measured by.
        _silenceTheRoom(holdTheClip: true);
        _handOff(_closeTheCaptureAndSend());
      case BtPhase.thinking:
      case BtPhase.conferida:
        break;
    }
  }

  void _abrirACaptura() {
    if (_trechoTraduzidoDeNovo == null && !state.btCortado) {
      if ((state.btParteFronteira || state.btClipEnded) &&
          isAStub(_trechoStart, _cabeca)) {
        return;
      }
      _silenceTheRoom(holdTheClip: true);
      final pausa = _aPausaNo(_cabeca);
      if (pausa == null) return;
      _trechoEnd = pausa;
      return;
    }
    _silenceTheRoom(holdTheClip: true);
    _startChunkCapture();
  }

  void _startChunkCapture() {
    state = state.copyWith(btPhase: BtPhase.capturing);
    _dispatch(
      MicOpened(
        MicOwner.capture,
        take: 'retro_passada${state.btPass}_pedaco${_stamp()}',
        generation: _generation,
      ),
    );
  }

  Future<bool> _finishChunkCapture() async {
    final generation = _waitOnTheGeneration;
    state = state.copyWith(btPhase: BtPhase.thinking, awaitingTheGuide: true);
    _watchBusyState();
    final path = (await _closeTheMicrophone()).take;
    if (_abandoned(generation)) return false;
    final sessionId = state.sessionId;

    if (path != null && !_hasAudio(path)) {
      _trechoStart = _ondeParouNesteArquivo(_parteTocando);
      state = state.copyWith(btPhase: BtPhase.playing, awaitingTheGuide: false);
      unawaited(_recorder.delete(path));
      return false;
    }

    if (path == null || sessionId == null) {
      state = state.copyWith(btPhase: BtPhase.playing, awaitingTheGuide: false);
      if (path != null) unawaited(_recorder.delete(path));
      return false;
    }

    final substituida = state.btTraducaoPendenteEmprestada
        ? null
        : state.btTraducaoPendente;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTraducaoPendente: path,
    );
    if (substituida != null) {
      unawaited(_retirarDaFilaSeGuardada(substituida));
    }
    return true;
  }

  Future<void> _closeTheCaptureAndSend() async {
    if (await _finishChunkCapture()) await _confirmarTraducao();
  }

  Future<void> _confirmarTraducao() async {
    if (!state.canConfirmTranslation) return;
    final path = state.btTraducaoPendente!;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    state = state.copyWith(clearAviso: true);
    final generation = _waitOnTheGeneration;
    final life = _thisLife;
    _silenceTheRoom(holdTheClip: true);
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      awaitingTheGuide: true,
      clearBtRecusa: _oQueFaltaOuvir == null,
    );
    _watchBusyState();

    final traduzidoDeNovo = _trechoTraduzidoDeNovo;
    if (traduzidoDeNovo != null) {
      await _tellThatStretchAgain(traduzidoDeNovo, path, sessionId, generation);
      if (_abandoned(generation) || state.btTraducaoPendente == null) return;
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
      _guardarATraducao(path, life);
      state = state.copyWith(
        btPhase: BtPhase.playing,
        awaitingTheGuide: false,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      return;
    }

    final RoomAnswer<BackTranslationChunk> sent;
    try {
      sent = await _underItsKey(
        generation,
        path,
        (key) => _room.sendChunk(
          sessionId,
          File(path),
          takeId: gravacao,
          from: _trechoStart,
          to: _trechoEnd,
          idempotencyKey: key,
        ),
      );
    } on FileSystemException {
      _guardarATraducao(path, life);
      if (_abandoned(generation)) return;
      state = state.copyWith(
        btPhase: BtPhase.playing,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      return _theStepsNetworkFailed();
    }
    final int? frase;
    final String? nome;
    switch (sent) {
      case Answered(:final value):
        if (_abandoned(generation)) return;
        frase = value.frase;
        nome = value.segmentId;
      case Refused(code: RefusalCode.stretchNoLongerCounts) && final refused:
        if (_abandoned(generation)) return;
        await _readWhatTheChunkRefusalSays(
          refused,
          path,
          sessionId,
          generation,
        );
        return;
      case final RoomFailure failure:
        _guardarATraducao(path, life);
        if (_abandoned(generation)) return;
        final porta = switch (failure) {
          NetworkFailed(reason: RefusalCode.idempotencyKeyInFlight) =>
            Door.step,
          _ => Door.telling,
        };
        state = state.copyWith(
          btPhase: BtPhase.playing,
          btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
        );
        _leaveThinking();
        _decideAt(failure, door: porta);
        return;
    }

    final trecho = Trecho(
      segmentId: nome,
      takeId: gravacao,
      retroPath: path,
      parte: _parteTocando,
      from: _trechoStart,
      to: _trechoEnd,
      // Nobody has corrected it: the slice it plays is the slice of the part it occupies.
      lugarFrom: _trechoStart,
      lugarTo: _trechoEnd,
      frase: frase,
    );
    _trechoStart = _trechoEnd;
    unawaited(_retirarDaFilaSeGuardada(path));
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTrechos: [
        for (final lido in state.btTrechos)
          if (lido.takeId != trecho.takeId ||
              lido.from != trecho.from ||
              lido.to != trecho.to)
            lido,
        trecho,
      ],
      clearTraducaoPendente: true,
    );
    if (!state.needsPerson) _tocarOProximoTrecho();
  }

  Future<RoomAnswer<T>> _underItsKey<T>(
    int generation,
    String path,
    Future<RoomAnswer<T>> Function(String key) send,
  ) async {
    final key = _stretchKeys.putIfAbsent(path, RoomClient.mintAKey);
    var step = 0;
    while (true) {
      final answer = await send(key);
      if (answer case Refused(
        code: RefusalCode.idempotencyKeyInFlight,
      ) when !_abandoned(generation)) {
        if (step == _sendsWhileInFlight - 1) {
          return const NetworkFailed(RefusalCode.idempotencyKeyInFlight);
        }
        await Future<void>.delayed(_onTheLadder(step++));
        if (!_abandoned(generation)) continue;
      }
      if (answer case Answered() || SessionGone()) _stretchKeys.remove(path);
      if (answer case Refused(
        :final code,
      ) when code != RefusalCode.idempotencyKeyInFlight) {
        _stretchKeys.remove(path);
      }
      return answer;
    }
  }

  void _guardarATraducao(String path, int? life) {
    if (_endedSince(life)) return;
    if (!_traducoesGuardadas.add(path)) return;
    unawaited(
      _guard(
        path,
        life,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ),
    );
  }

  void _letThePendingTranslationGo() {
    final path = state.btTraducaoPendente;
    state = state.copyWith(
      clearTraducaoPendente: true,
      awaitingTheGuide: false,
    );
    if (path != null) unawaited(_recorder.delete(path));
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
      _atravessar();
      return;
    }
    if (state.btClipEnded) return;
    final proxima = _parteTocando + 1;
    _tocarParteDaRetro(
      _parteTocando,
      noCursor: true,
      seguir:
          !state.joined ||
          !state.btTrechos.any((trecho) => trecho.parte == proxima),
    );
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

  Future<void> finishBackTranslation() =>
      _gestureThen(() => _finishBackTranslation());

  Future<void> _finishBackTranslation() async {
    if (!state.canFinishBackTranslation) return;
    _dispatch(const TheVerdictAsked());
    state = state.copyWith(clearAviso: true);
    _silenceTheRoom();
    _oQueFaltaOuvir = null;
    final sessionId = state.sessionId;
    if (sessionId == null) return;

    final generation = _waitOnTheGeneration;
    state = state.copyWith(
      btPhase: BtPhase.thinking,
      awaitingTheGuide: true,
      btConferindo: true,
      clearBtRecusa: true,
      btSoOuvir: false,
    );
    _watchBusyState();
    final BackTranslationVerdict verdict;
    final asked = await _room.finishBackTranslation(
      sessionId,
      playedByTake: _escuta.relato(state.partes),
    );
    if (_abandoned(generation)) return;
    state = state.copyWith(btConferindo: false);
    switch (asked) {
      case Answered(value: final answer):
        verdict = answer;
      case final RoomFailure failure:
        if (failure case NetworkFailed()) {
          state = state.copyWith(btRecusa: CheckRefusal.checkUnavailable);
          _decideAt(failure, door: Door.verdict);
          return;
        }
        _decideTheFailure(failure);
        return;
    }
    if (verdict.refusal
        case CheckRefusal.nothingTranslated || CheckRefusal.checkUnavailable) {
      state = state.copyWith(
        btPhase: BtPhase.playing,
        awaitingTheGuide: false,
        btRecusa: verdict.refusal,
      );
      return;
    }
    if (verdict.refusal == CheckRefusal.partUnheard) {
      state = state.copyWith(btRecusa: verdict.refusal);
    }
    if (verdict.refusal == CheckRefusal.fraseAwaiting &&
        verdict.fixedLine.isEmpty) {
      await _readTheStretchesBack(sessionId, generation);
      if (_abandoned(generation) || state.needsPerson) return;
      if (verdict.untoldSegmentId case final aguardando?) {
        _levarAoTrechoNaoTraduzido(aguardando);
      }
      return;
    }
    if (verdict.refusal == CheckRefusal.stretchUntranslated) {
      return _levarAoTrechoSemTraducao(
        verdict.fixedLine,
        verdict.untranslated,
        () => _abandoned(generation),
      );
    }
    try {
      await _readyToSpeak(verdict.audioUrl, verdict.fixedLine);
      if (_abandoned(generation)) return;
      _watchBusyState();
      final spoke = await _speak(
        verdict.audioUrl,
        verdict.fixedLine,
        remember: !verdict.usedFailSafe,
        checkAt: verdict.checkAt,
      );
      if (_abandoned(generation)) return;
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
      if (!spoke.heard) {
        _leaveThinking();
        return _registerUnplayableTurn();
      }

      final naoContadas = verdict.untoldTakeIds;
      if (naoContadas.isNotEmpty) {
        await _levarAsPartesApontadasPelaRecusa(
          [naoContadas.first],
          generation,
          semChaoTraduzido: true,
        );
        return;
      }

      final naoOuvidas = verdict.unheardTakeIds;
      if (naoOuvidas.isNotEmpty) {
        await _levarAsPartesApontadasPelaRecusa(
          naoOuvidas,
          generation,
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
        await _readTheStretchesBack(sessionId, generation);
        if (_abandoned(generation) || state.needsPerson) return;
        state = state.copyWith(
          btPhase: BtPhase.conferida,
          awaitingTheGuide: false,
          clearFindingSegment: true,
          btFindings: [?verdict.namedNuance, ...verdict.findings],
          btVeredito: true,
        );
        return;
      }
      // The room names the stretch the finding lands on, and the name is the room's to
      // give: nothing in the chunk it answered ever said it. The stretches are read back
      // before the pointer is resolved, so it is resolved against names that exist.
      //
      // The verdict is already in hand and already spoken. Failing to re-read the names
      // costs the pointer, not the verdict, so the findings screen still opens — on the
      // whole recording, which is where an unnamed stretch has always landed.
      await _readTheStretchesBack(sessionId, generation);
      if (_abandoned(generation) || state.needsPerson) return;

      final naoTraduzido = verdict.untoldSegmentId;
      if (naoTraduzido != null) {
        _levarAoTrechoNaoTraduzido(naoTraduzido);
        return;
      }
      state = state.copyWith(
        btPhase: BtPhase.playing,
        awaitingTheGuide: false,
        btFindingSegmentId: verdict.findingSegmentId,
        clearFindingSegment: verdict.findingSegmentId == null,
        btFindings: verdict.findings,
        btVeredito: true,
      );
      // The stretch is no longer played at the team. Which voice needs to speak again is
      // theirs to say, and they say it by comparing the two — so hearing either one is a
      // tap they choose to make, on the screen that asks the question.
    } on RoomFailure catch (failure) {
      if (_abandoned(generation)) return;
      _decideTheFailure(failure);
    }
  }

  /// The team makes what it recorded its final draft.
  ///
  /// A passage the room called checked stays on screen until somebody presses, and an
  /// approval ends on the Saved screen over it, never on the Choice. The phase never leaves
  /// [BtPhase.conferida] while the request is out, which is what keeps the affordance
  /// alive under a transport failure — [_leaveThinking] has nothing to undo there.
  Future<void> aprovarRascunhoFinal() =>
      _gestureThen(() => _aprovarRascunhoFinal());

  Future<void> _aprovarRascunhoFinal() async {
    final fromTheHome = state.approveOffered;
    if (!fromTheHome &&
        (state.station is! Retro || state.btPhase != BtPhase.conferida)) {
      return;
    }
    if (state.needsPerson) return;
    if (!state.canApprove || state.ensaioSalvo != null) return;
    _silenceTheRoom();
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    state = state.copyWith(
      btAprovando: _generation,
      clearBtRecusa: true,
      clearAviso: true,
      clearArmedTap: true,
    );
    final generation = _waitOnTheGeneration;
    void failed(RoomFailure failure) {
      if (_abandoned(generation)) return;
      if (failure case Refused()) _backToBeforeTerminei();
      _decideTheFailure(failure);
    }

    try {
      final ApprovalAnswer resposta;
      switch (await _room.approveRelease(sessionId)) {
        case Answered(value: final answer):
          resposta = answer;
        case final RoomFailure failure:
          if (!_abandoned(generation)) _saysWhy(CheckRefusal.checkUnavailable);
          return failed(failure);
      }
      if (_abandoned(generation)) return;
      if (!resposta.minted) {
        final failure = await _levarAoBuracoQueARecusaNomeia(
          resposta,
          sessionId,
          generation,
        );
        if (failure != null) failed(failure);
        return;
      }
      state = state.copyWith(btAprovadoAgora: resposta.version);
      unawaited(_readTheApprovedDraft(sessionId, generation));
      try {
        if (!fromTheHome &&
            !await _sayALine(
              LineKind.approved,
              fixedLine: (name: approvedLine, language: _inTheSessionsLanguage),
            )) {
          _registerUnplayableTurn();
        }
      } on RoomFailure catch (failure) {
        if (!_abandoned(generation)) _decideTheFailure(failure);
      }
      if (_abandoned(generation)) return;
      state = state.copyWith(ensaioSalvo: state.btAprovadoAgora);
    } finally {
      if (!_gone && state.btAprovando == generation) {
        state = state.copyWith(
          clearBtAprovando: true,
          clearBtAprovadoAgora: true,
        );
      }
    }
  }

  void _saysWhy(CheckRefusal recusa) =>
      state = state.copyWith(btRecusa: recusa);

  /// Take the team to the first hole the refusal names that this room has a door for.
  ///
  /// Which hole is first is [_PortaDaRecusa]'s own order and never the order the codes
  /// arrived in: a refusal naming the check and a part nobody told back names the check
  /// first, and opening that door hands the team back the very button that was refused. A
  /// hole with no door, a code this tablet does not know, a named hole whose ground never
  /// came, and an answer that is neither a version nor a refusal are the same thing from
  /// here — nothing the team can do from this screen — and they end where a refused
  /// approval has always ended.
  Future<RoomFailure?> _levarAoBuracoQueARecusaNomeia(
    ApprovalAnswer resposta,
    String sessionId,
    int generation,
  ) async {
    _PortaDaRecusa? aberta;
    for (final blocker in resposta.blockers) {
      final porta = _portaDaRecusa(blocker);
      if (porta == null) continue;
      if (aberta == null || porta.index < aberta.index) aberta = porta;
    }
    switch (aberta) {
      case _PortaDaRecusa.trecho:
        _saysWhy(CheckRefusal.notConferida);
        final trecho = resposta.untoldSegmentId;
        if (trecho == null) {
          _backToBeforeTerminei();
          return null;
        }
        // The verdict's read of the names was refused off the network, so the passage
        // landed on conferida holding only the stretches this tablet cut, and the name the
        // refusal gives matches none of them: this read resolves it.
        final failure = await _readTheStretchesBack(sessionId, generation);
        if (failure != null) return failure;
        if (_abandoned(generation) || state.needsPerson) return null;
        _levarAoTrechoNaoTraduzido(trecho);
      case _PortaDaRecusa.parteNaoContada:
        _saysWhy(CheckRefusal.notConferida);
        final gravacoes = resposta.untoldTakeIds;
        if (gravacoes.isEmpty) {
          _backToBeforeTerminei();
          return null;
        }
        await _levarAsPartesApontadasPelaRecusa(
          [gravacoes.first],
          generation,
          semChaoTraduzido: true,
        );
      case _PortaDaRecusa.parteNaoOuvida:
        _saysWhy(CheckRefusal.partUnheard);
        final gravacoes = resposta.unheardTakeIds;
        if (gravacoes.isEmpty) {
          _backToBeforeTerminei();
          return null;
        }
        await _levarAsPartesApontadasPelaRecusa(
          gravacoes,
          generation,
          semChaoTraduzido: false,
        );
      case _PortaDaRecusa.conferir:
        _saysWhy(CheckRefusal.notConferida);
        _backToBeforeTerminei();
      case null:
        _saysWhy(CheckRefusal.checkUnavailable);
        _backToBeforeTerminei();
    }
    return null;
  }

  /// One Session read after a mint, so the badge comes from a read (ADR 0106); a read that
  /// fails leaves the approve button, and the next press asks the room again.
  Future<void> _readTheApprovedDraft(String sessionId, int generation) async {
    final sent = ++_readsSent;
    if (await _room.fetchState(sessionId) case Answered(value: final read)) {
      if (!_abandoned(generation)) _applyTheSessionRead(read, sent);
    }
  }

  /// «Pronto» drops the Saved screen and nothing else: the Station, the checked Step and
  /// the Resume point stay where the approval left them.
  void pronto() => _gesture(() {
    if (state.ensaioSalvo == null) return;
    state = state.copyWith(clearEnsaioSalvo: true);
  });

  /// The room is already silent — the press silenced it — and the last listening of a
  /// checked passage is what took the end of the clip away, which the advance disc waits
  /// on beside told ground and nothing pending.
  void _backToBeforeTerminei() => state = state.copyWith(
    btPhase: BtPhase.playing,
    btClipEnded: true,
    awaitingTheGuide: false,
  );

  /// Straight to the part the verdict names, with the telling-back left standing.
  ///
  /// The room refuses to read a passage carrying ground it does not know about, and it
  /// names the part it is missing — whether nobody heard it ([semChaoTraduzido] false) or
  /// nobody told it back ([semChaoTraduzido] true). The press is not spent on the refusal:
  /// the part goes in the air, the team hears it, and the finish is offered again at its end.
  /// [semChaoTraduzido] carries straight through to [_tocarParteDaRetro], whose own doc
  /// says what it does to the cursor and why.
  Future<void> _levarAsPartesApontadasPelaRecusa(
    List<String> gravacoes,
    int generation, {
    required bool semChaoTraduzido,
  }) async {
    bool apontada(KeptTake take) => gravacoes.contains(take.takeId);
    if (!state.partes.any(apontada)) {
      // A recording this tablet is not holding: there is nothing to lead them to, and
      // measuring the whole rehearsal first would only make them wait for nothing.
      state = state.copyWith(btPhase: BtPhase.playing, awaitingTheGuide: false);
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
      if (antes >= state.partes.lastIndexWhere(apontada)) break;
      if (_tamanhoDaParteMs.containsKey(arquivo)) continue;
      // Measuring waits on the player, and the watchdog that gives up on a wait only
      // watches a room that says it is thinking. Left speaking — which is where saying
      // the refusal leaves it — a measurement that never answered wedged the room with
      // nobody called, which is the one thing every other wait here is protected from.
      state = state.copyWith(awaitingTheGuide: true);
      _watchBusyState();
      final medida = await _playback.howLong(arquivo);
      if (_abandoned(generation)) return;
      if (medida == null) continue;
      if (!state.partes.any((take) => take.path == arquivo)) continue;
      _marcarOFimDaParte(arquivo, medida.inMilliseconds);
    }
    final partes = [
      for (final (onde, take) in state.partes.indexed)
        if (apontada(take)) onde,
    ];
    if (partes.isEmpty) {
      state = state.copyWith(btPhase: BtPhase.playing, awaitingTheGuide: false);
      return;
    }
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btFimDasPartesMs: _fimDaParteMs,
    );
    _ouvirAsPartes(partes, semChaoTraduzido: semChaoTraduzido);
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
      awaitingTheGuide: false,
      clearFindingSegment: true,
    );
    _leadThemToTheTrecho(trecho);
  }

  Trecho? _armarOTrecho(Trecho? trecho, {BtPhase? fase}) {
    if (trecho == null ||
        trecho.parte < 0 ||
        trecho.parte >= state.partes.length) {
      // A name this tablet cannot turn into a slice of a recording it is holding: there
      // is nothing to lead them to.
      state = state.copyWith(btPhase: BtPhase.playing, awaitingTheGuide: false);
      return null;
    }
    _parteTocando = trecho.parte;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _trechoTraduzidoDeNovo = trecho;
    _faseAntesDeTraduzirDeNovo = null;
    state = state.copyWith(
      btPausaAjustavel:
          state.theLastPauseMoves(trecho, naFase: fase) &&
          _ondeAPausaCabe() != null,
      btPausaSoNaUltima: false,
    );
    return trecho;
  }

  /// Take the room's own reading of the stretches, names and all.
  ///
  /// A stretch is born on the server and only the server knows what it is called. The
  /// answer to telling one back names it, but an answer the room kept from before it
  /// named its stretches carries a count and no name. Without this the pointer on a
  /// finding matched nothing this tablet held, and a team that had told six stretches
  /// back was offered the whole recording every time.
  ///
  /// It answers the failure of a read that did not happen, and whether that is survivable
  /// is the caller's to say: the verdict ignores it, because it already holds its answer
  /// and only the pointer is lost; the approval's refusal does not, because the name is
  /// the whole of what it has.
  Future<RoomFailure?> _readTheStretchesBack(
    String sessionId,
    int generation,
  ) async {
    final life = _thisLife;
    final sent = ++_readsSent;
    switch (await _room.fetchState(sessionId)) {
      case Answered(value: final snapshot):
        if (_abandoned(generation)) return null;
        if (sent > _stretchesAt) {
          _stretchesAt = sent;
          final trechos = _trechosFrom(snapshot.backTranslation.segments);
          if (trechos.isNotEmpty) state = state.copyWith(btTrechos: trechos);
          final aguardando = snapshot.backTranslation.awaitingSegmentId;
          state = state.copyWith(
            btFraseQueAguarda: aguardando,
            clearBtFraseQueAguarda: aguardando == null,
          );
        }
        _applyTheSessionRead(snapshot, sent);
        return null;
      case NetworkFailed() && final failure:
        _theNetworkFailedIn(Door.stretches, life);
        return failure;
      case final RoomFailure failure:
        return failure;
    }
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
    final deLado = state.wholeSetAside;
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
            frase: segment.frase,
          );
        }(),
    ].where((trecho) => !deLado.contains(trecho.takeId)).toList();
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
    int generation, {
    List<SegmentView> regravados = const [],
  }) async {
    Set<String> semGravacao(List<SegmentView> lidos) => {
      for (final segment in lidos)
        if (segment.takeId.isNotEmpty &&
            !state.keptTakes.any((take) => take.takeId == segment.takeId))
          segment.takeId,
    };
    final faltando = semGravacao(segments);
    final regravadosFaltando = semGravacao(regravados);
    if (faltando.isEmpty && regravadosFaltando.isEmpty) return;
    // The row of stretches as it stands before the listing waits. The rehearsal goes on
    // playing under it, and a team that cuts a stretch inside that window has it in this
    // list and nowhere else yet.
    final eram = state.btTrechos;
    final life = _thisLife;
    final List<TakeView> guardadas;
    switch (await _room.takesOf(sessionId)) {
      case Answered(value: final listadas):
        guardadas = listadas;
      case NetworkFailed():
        return _theNetworkFailedIn(Door.stretches, life);
      case SessionGone():
        return _theSessionIsGoneIn(sessionId, life);
      case Refused():
        debugPrint(
          'A sessão $sessionId tem trechos numa gravação que este tablet não '
          'tem, e as gravações dela não puderam ser lidas',
        );
        return;
    }
    if (_abandoned(generation)) return;
    final naParte = <String, int>{};
    for (final guardada in guardadas) {
      if (!faltando.contains(guardada.takeId) &&
          !regravadosFaltando.contains(guardada.takeId)) {
        continue;
      }
      final numero = guardada.ordinal;
      if (numero == null) continue;
      final onde = state.partes.indexWhere(
        (parte) => parte.scopeId == KeptScope.parte(numero),
      );
      if (onde < 0) continue;
      naParte[guardada.takeId] = onde;
    }
    if (naParte.isEmpty) return;
    state = state.copyWith(
      btTrechosRegravados: [
        for (final trecho in _trechosFrom(regravados, naParte: naParte))
          if (trecho.parte >= 0) trecho,
      ],
    );
    // Only over a row nothing else has touched. This reading is built out of the answer
    // the resume came in with, so writing it over a row that moved meanwhile would take
    // the stretch the team just told back off the screen.
    if (faltando.isEmpty || !identical(state.btTrechos, eram)) return;
    state = state.copyWith(btTrechos: _trechosFrom(segments, naParte: naParte));
  }

  void _leadThemToTheTrecho(
    Trecho trecho, {
    VoidCallback? depois,
    Duration? ate,
  }) {
    if (_ondeTocar(trecho) == null) return;
    _tocarOTrecho(trecho, depois: depois, ate: ate);
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
  (String, Duration, Duration)? _ondeTocar(Trecho trecho, {Duration? ate}) {
    final path = _pathForTrecho(trecho);
    if (path != null) return (path, trecho.from, ate ?? trecho.to);
    if (trecho.parte >= 0 && trecho.parte < state.partes.length) {
      return (
        state.partes[trecho.parte].path,
        trecho.lugarFrom,
        ate == null ? trecho.lugarTo : ate + trecho.lugarFrom - trecho.from,
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
  void _tocarOTrecho(Trecho trecho, {VoidCallback? depois, Duration? ate}) {
    final onde = _ondeTocar(trecho, ate: ate);
    if (onde == null) return;
    void quiet() => unawaited(_playback.stop());
    _play(
      StretchSound(
        onde.$1,
        named: trecho.segmentId,
        from: onde.$2,
        to: onde.$3,
      ),
      onComplete: () {
        quiet();
        depois?.call();
      },
      onFailed: quiet,
    );
  }

  void traduzirAFraseDeNovo(int indice) =>
      _gesture(() => _traduzirAFraseDeNovo(indice));

  void _traduzirAFraseDeNovo(int indice) {
    if (!state.canRetellAFrase) return;
    if (indice < 0 || indice >= state.btTrechos.length) return;
    final trecho = state.btTrechos[indice];
    if (!trecho.contado ||
        trecho.segmentId == null ||
        !state.aParteDoTrechoEstaAqui(trecho)) {
      return;
    }
    final fimMovido = _trechoTraduzidoDeNovo?.segmentId == trecho.segmentId
        ? _trechoEnd
        : null;
    if (!_traduzirOTrechoDeNovo(trecho)) return;
    if (fimMovido != null) _trechoEnd = fimMovido;
    state = state.copyWith(
      btPausaSoNaUltima: state.anEarlierPauseStays(
        trecho,
        naFase: _faseAntesDeTraduzirDeNovo,
      ),
      clearAviso: true,
    );
    _leadThemToTheTrecho(trecho, ate: fimMovido);
  }

  bool _traduzirOTrechoDeNovo(Trecho trecho) {
    final fase = _trechoTraduzidoDeNovo == null
        ? state.btPhase
        : _faseAntesDeTraduzirDeNovo;
    _silenceTheRoom();
    _descartarATraducaoPendente();
    if (_armarOTrecho(trecho, fase: fase) == null) return false;
    _faseAntesDeTraduzirDeNovo = fase;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      awaitingTheGuide: false,
      btTraducaoPendente: trecho.retroPath,
      btTraducaoEmprestada: trecho.retroPath,
    );
    return true;
  }

  void manterATraducaoDeAntes() => _gesture(() => _manterATraducaoDeAntes());

  void _manterATraducaoDeAntes() {
    final trecho = _trechoTraduzidoDeNovo;
    if (state.btPhase != BtPhase.playing || trecho == null) return;
    final aguardando = state.btFraseQueAguarda;
    if (aguardando != null && trecho.segmentId == aguardando) return;
    _silenceTheRoom();
    _descartarATraducaoPendente();
    _trechoTraduzidoDeNovo = null;
    _walkTheCursorBack(state.btTrechos);
    state = state.copyWith(
      btPhase: _faseAntesDeTraduzirDeNovo ?? BtPhase.playing,
    );
  }

  /// Back to the rehearsal to record one part again, in the place that part already has.
  void gravarAParteDeNovo() => _gesture(() => _gravarAParteDeNovo());

  void _gravarAParteDeNovo() {
    if (state.btPhase != BtPhase.playing) return;
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    // Read before the way back clears the pointer, which is the only place the part is
    // written down at all.
    final parte = trecho.parte;
    if (parte < 0 || parte >= state.partes.length) {
      // A stretch on a recording this tablet is not holding has no part to record again.
      // Carried on, the keep would send a recording up under a part number the rehearsal
      // does not have, and the team would have recorded for nothing.
      _silenceTheRoom();
      return;
    }
    _voltarAoEnsaio();
    if (state.partes[parte].scopeId != KeptScope.whole) {
      state = state.copyWith(parteARegravar: parte);
    }
    _asPartesPerdidasSaem();
    _rememberWhereTheyAre(const Ensaio());
  }

  /// The first scene part sets the whole rehearsal aside: what was told over it leaves the
  /// telling-back here, and stays the room's.
  void _deixarOInteiroDeLado() {
    final deLado = state.wholeSetAside;
    if (deLado.isEmpty) return;
    final trechos = [
      for (final trecho in state.btTrechos)
        if (!deLado.contains(trecho.takeId)) trecho,
    ];
    state = state.copyWith(
      btTrechos: trechos,
      btFindings: _osAchadosQueFicam(state.btFindings, trechos),
    );
  }

  /// With a whole rehearsal set aside, only a finding on a stretch the tablet keeps
  /// stands: the rest were the whole's.
  List<BtFinding> _osAchadosQueFicam(
    List<BtFinding> findings,
    List<Trecho> trechos,
  ) {
    if (state.wholeSetAside.isEmpty) return findings;
    final contados = {for (final trecho in trechos) ?trecho.segmentId};
    return [
      for (final finding in findings)
        if (contados.contains(finding.segmentId)) finding,
    ];
  }

  void _voltarAoEnsaio() {
    _leaveTheStepFor(const Ensaio());
    _clearAll();
    _arriveAt(const TheRehearsalOpened());
    state = state.copyWith(
      awaitingTheGuide: false,
      ensaio: EnsaioStatus.idle,
      btPhase: BtPhase.playing,
      clearFindingSegment: true,
      peerCue: false,
      btSoOuvir: false,
    );
    _readTheScenesForTheRehearsal();
    // A mend left armed by a chunk that never landed would make the first stretch of
    // the next telling-back upload as a correction of one that does not exist.
    _trechoTraduzidoDeNovo = null;
    _rememberWhereTheyAre(const Ensaio());
  }

  Future<void> _startOver() {
    _clearAll();
    _forgetThePassage();
    state = SalaSessionState(machine: _gesturesOnTheirWay);
    _arriveAt(const TheRoomStartedOver());
    return abrirEscolha();
  }

  /// Everything a passage leaves behind that the next one must not inherit.
  ///
  /// Mostly counters and latches with no home in the state object, so nothing about them
  /// is reset by rebuilding it; the cursor, the cut, the stretch being told again and the
  /// pending translation live in the state and are let go here too, the pending file with
  /// them. `leaveThePassage` reset none of them and `_startOver` reset most: the stretch
  /// being told again — armed when the team asks to tell one again and let go only by a
  /// telling that lands — made the very first stretch of the next back translation upload
  /// as a correction of a stretch that does not exist.
  void _forgetThePassage() {
    _relatarAEscuta();
    state = state.copyWith(btSoOuvir: false);
    if (state.sessionId case final session?) {
      unawaited(_recorder.forgetTheKeptRetellings(session).catchError((_) {}));
    }
    unawaited(_coverageWatch?.cancel());
    _coverageWatch = null;
    _coverageSessionId = null;
    for (final perdida in _perdidasNoTrecho.values.expand(
      (perdidas) => perdidas,
    )) {
      unawaited(_retirarDaFilaSeGuardada(perdida));
    }
    _perdidasNoTrecho.clear();
    _stretchKeys.clear();
    _passadasDaSala = null;
    _listenerInProgress = null;
    _personAsked = false;
    _runner.endTheWatch();
    _runner.forgetTheLadder();
    _trechoTraduzidoDeNovo = null;
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _parteJaTocou = false;
    _dispatch(const LeftThePassage());
    _descartarATraducaoPendente();
    _traducoesGuardadas.clear();
    _traducaoNaFila.clear();
    _tamanhoDaParteMs.clear();
    _oQueFaltaOuvir = null;
    _partesDaEscuta = const [];
    _escuta.esquecerTudo();
    _desdeMs = 0;
    _pendingTakePath = null;
    _emCurso = null;
    state = state.copyWith(partsAway: const {});
    _partesDescendo = null;
    _aLinhaDiz = null;
    _semNome.clear();
    _captureFails = {};
    _recordingStarting = false;
  }
}

typedef _AwaitedReply = ({
  Future<void> Function(TurnResult reply) play,
  List<int> gestures,
});

class _HandHost implements HandHost {
  final SalaSessionNotifier _notifier;

  _HandHost(this._notifier);

  @override
  HandView get view {
    final state = _notifier._current;
    return (
      replies: state.replies,
      playingReplyId: state.playingReplyId,
      channel: state.channel,
      noteMode: state.noteMode,
      voice: state.voice,
      stationSessionId: state.stationSessionId,
      atTheTeamsIdleTurn: state.atTheTeamsIdleTurn,
      oldestUnheardReply: state.oldestUnheardReply,
      noteOnItsWay: state.noteOnItsWay,
    );
  }

  @override
  void showReplies(List<HandReply> replies) =>
      _notifier._current = _notifier._current.copyWith(replies: replies);

  @override
  void markPlaying(String id) =>
      _notifier._current = _notifier._current.copyWith(playingReplyId: id);

  @override
  void clearPlaying() =>
      _notifier._current = _notifier._current.copyWith(clearPlayingReply: true);

  @override
  void markReplyHeard(List<HandReply> replies) => _notifier._current = _notifier
      ._current
      .copyWith(replies: replies, clearPlayingReply: true);

  @override
  void enterNoteMode() =>
      _notifier._current = _notifier._current.copyWith(noteMode: true);

  @override
  void leaveNoteMode() =>
      _notifier._current = _notifier._current.copyWith(noteMode: false);

  @override
  void markNoteOnItsWay(int note) => _notifier._current = _notifier._current
      .copyWith(noteMode: false, noteOnItsWay: note);

  @override
  void clearNoteOnItsWay() =>
      _notifier._current = _notifier._current.copyWith(clearNoteOnItsWay: true);

  @override
  bool get gone => _notifier._gone;

  @override
  int? get thisLife => _notifier._thisLife;

  @override
  bool endedSince(int? life) => _notifier._endedSince(life);

  @override
  bool abandoned(int generation) => _notifier._abandoned(generation);

  @override
  int get waitOnTheGeneration => _notifier._waitOnTheGeneration;

  @override
  Duration get listenedFor => _notifier._listenedFor;

  @override
  String stamp() => _notifier._stamp();

  @override
  bool theGuardKeeps(String path, Duration listenedFor) =>
      _notifier._theGuardKeeps(path, listenedFor);

  @override
  void dispatch(MachineEvent event) => _notifier._dispatch(event);

  @override
  void decideAt(RoomFailure failure, {required Door door}) =>
      _notifier._decideAt(failure, door: door);

  @override
  void handOff(Future<void> next) => _notifier._handOff(next);

  @override
  void silenceTheRoom() => _notifier._silenceTheRoom();

  @override
  void startListening(String fileName, {required MicOwner owner}) =>
      _notifier._startListening(fileName, owner: owner);

  @override
  Future<MicOutcome> closeTheMicrophone() => _notifier._closeTheMicrophone();

  @override
  Future<Said> sayTheLine(LineKind kind, {String? url, Source? source}) =>
      _notifier._sayTheLine(kind, url: url, source: source);
}

class _NotifierHost implements StationHost {
  final SalaSessionNotifier _notifier;

  _NotifierHost(this._notifier);

  @override
  bool get watchIsWanted => _notifier._watchIsWanted;

  @override
  String? get session => _notifier._sessionId;

  @override
  FailureContext failureContext({
    required Door door,
    required RefusalRule rule,
  }) => _notifier._failureContext(door: door, rule: rule);

  @override
  SentRead hearTheReadSent() => _notifier._theReadSent();

  @override
  void hearTheSessionRead(SessionSnapshot snapshot, SentRead sent) =>
      _notifier._theSessionReadHeard(snapshot, sent);

  @override
  bool get callIsWanted => _notifier._callIsWanted;

  @override
  bool get aPersonIsNeeded => _notifier._aPersonIsNeeded;

  @override
  void hearTheCallStopped() => _notifier._stopCallingForAPerson();

  @override
  void hearThePassageClosed(String session) =>
      _notifier._theSessionIsClosed(session);

  @override
  void hearTheCallLanded() => _notifier._theCallLanded();

  @override
  void hearAnEarlierSessionsCall(String session, RoomResult result) =>
      _notifier._theCallOfAnEarlierSession(session, result);

  @override
  bool get recordingStarts => _notifier._recordingStarting;

  @override
  bool keepsTheStart(MicOwner owner) => _notifier._keepsTheStart(owner);

  @override
  Kept get sounding => _notifier._whatIsSounding(theOpening: false);

  @override
  void answer(MachineEvent event) =>
      _notifier._apart(() => _notifier._dispatch(event));

  @override
  void answerWhereAsked(MachineEvent event) => _notifier._dispatch(event);

  @override
  void hearThePartEnd() => _notifier._thePartEnded();

  @override
  void hearThePartFail() => _notifier._thePartFailed();

  @override
  void hearTheHold() => _notifier._checkCursorNow();

  @override
  void hearTheRun() => _notifier._theRunHeard();

  @override
  void hearTheMicrophoneTaken(bool taken) =>
      _notifier._theMicrophoneChangedHands(taken);

  @override
  void handOver(LifecycleHandOff handOff) {
    switch (handOff) {
      case OpenTheChoice():
        _notifier._openTheChoice();
      case ReadTheWheel():
        _notifier._handOff(_notifier.abrirEscolha());
      case DiscardTheSession():
        _notifier._discardTheSession();
      case SilenceTheRoom():
        _notifier._silenceTheHaltedRoom();
      case OpenThePanorama(:final id, :final language):
        _notifier._handOff(_notifier._entrarNoPanorama(id, language));
      case ReturnToThePanorama():
        _notifier._returnToThePanorama();
      case EnterThePassageLeft(:final left):
        _notifier._handOff(_notifier._enterThePassageLeft(left));
    }
  }

  @override
  Iterable<int> gesturesAwaiting(Turn turn) =>
      _notifier._awaitedReplies[turn]?.gestures ?? const [];

  @override
  void hearTheTurnLetGo() => _notifier._watchBusyState();

  @override
  void hearTheReplyFound(Turn turn, TurnResult reply) =>
      _notifier._playTheReplyTheLookFound(turn, reply);

  @override
  void hearTheReplyKept(Turn turn, TurnResult reply) =>
      _notifier._keepTheReplyTheLookFound(turn, reply);

  @override
  void hearTheLineLetGo() => _notifier._letTheLineGo();

  @override
  void hearTheWaitResumed() => _notifier._waitOnTheLookAgain();

  @override
  void hearTheSignCleared() => _notifier._theSignCleared();

  @override
  void hearTheOpeningLetGo() => _notifier._letTheOpeningGo();

  @override
  Future<void> hearTheOutboxFlushed() async {
    final generation = _notifier._waitOnTheGeneration;
    final life = _notifier._thisLife;
    await _notifier._adoptTheNames(_notifier._takes, life);
    await _notifier._theRoomKeptWhatWaited(generation, life);
  }

  @override
  Future<void> hearTheOutboxCounted() => _notifier._countUnsent();

  @override
  void hearTheStepLetGo() => _notifier._letTheStepGo();

  @override
  void hearThePendingTranslationLetGo() =>
      _notifier._letThePendingTranslationGo();

  @override
  void hearThePassageRefused() => _notifier._refuseThePassage();

  @override
  void hearTheSceneRehearsals(List<SceneRehearsalRecord> listed) =>
      _notifier._theSceneRehearsalsHeard(listed);

  @override
  void hearTheFraseNotUnderstood() => _notifier._theFraseNotUnderstood();

  @override
  void hearTheFrasePerhapsKept() => _notifier._theFrasePerhapsKept();

  @override
  void hearTheDiskFailed() => _notifier._theDiskFailed();
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
      SalaSessionNotifier.new,
    );

final class _OQueFaltaOuvir {
  final List<int> aFrente;
  final bool paraNaUltima;

  const _OQueFaltaOuvir(this.aFrente, {required this.paraNaUltima});
}

typedef _JoinRowWritten = ({PendingTake row, String path, int pass});

const JoinOutcome _givenUpWaiting = (
  row: JoinRow.retry,
  part: JoinedPart.waiting,
);

const JoinOutcome _joinLeftBehind = (
  row: JoinRow.retry,
  part: JoinedPart.nowhere,
);
