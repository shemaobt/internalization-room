import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../domain/bt_finding.dart';
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

/// How much sound counts as the team having said something. Below it the room answers
/// from the bundle instead of paying for a round trip to hear silence — the one place
/// the app judges a capture rather than forwarding it.
final shortestSpeechProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 900),
);

final playbackCeilingProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 6),
);

/// The book the room is serving. One string, in one place, so another book is a config
/// change rather than a code change — the catalogue route takes it as a parameter.
final bookProvider = Provider<String>((ref) => 'Ruth');

final devLanguageProvider =
    NotifierProvider<DevLanguage, String?>(DevLanguage.new);

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
  String? _haltWatched;
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
  bool _askingForAPerson = false;
  int _personAskStep = 0;
  int _ackSpoken = 0;
  int _inaudibleSpoken = 0;
  DateTime? _listeningSince;
  String? _emCurso;
  bool _traduzindoDeNovo = false;
  Trecho? _trechoTraduzidoDeNovo;
  bool _askingForANewClip = false;
  String _marcaDaMaterna = '';
  /// The clip is paused. `_onPlaybackComplete` deliberately survives a pause — the resume
  /// still has to be able to end the part — so it cannot be what tells a ceiling whether
  /// there is any sound left to measure.
  bool _clipHeld = false;
  int _inboxSilences = 0;
  int _degradedTurns = 0;
  Duration _trechoStart = Duration.zero;

  /// Where each stretch mended by the long way sits, by the take the mend recorded.
  ///
  /// Carried in the resume point rather than only here: the room answers for a mended
  /// stretch with a recording that is no part of the rehearsal, so a tablet opened again
  /// has nothing on the wire to place it by.
  final Map<String, LugarDoTrecho> _lugares = {};
  Duration _trechoEnd = Duration.zero;
  int _parteTocando = 0;

  /// Which part of the rehearsal the team came back to record again, or null when the
  /// recording they are about to keep is a part the passage does not have yet.
  int? _parteARegravar;

  /// The part in the air is the one the room said nobody heard, and hearing it to its end
  /// hands the finish back.
  ///
  /// The finish was already the team's — it is how the refusal was asked for — and the
  /// refusal only takes it away for the length of this one part. Without this, a refusal
  /// naming any part but the last made the team cross and listen through everything after
  /// it to get the press back, which is hearing the story again: the very thing the jump
  /// over the ground already told exists to spare them.
  bool _pousadaNaParteNaoOuvida = false;

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
  /// outlived it: the cord drew every band after a mended part at the length of the
  /// recording that mend replaced, while the rule that crosses into the next part read
  /// the new file. Keyed by the file, a swapped part needs only its own measurement, and
  /// the listening ledger — keyed by the file too — cannot disagree with the ruler about
  /// which recording a length belongs to.
  final Map<String, int> _tamanhoDaParteMs = {};
  final EscutaDasPartes _escuta = EscutaDasPartes();
  int _desdeMs = 0;
  int _ghostParte = 0;
  String? _panoramaSessionId;

  /// The opening turn this instance is asking for, minted once and carried across every
  /// retry of it — a resend under a fresh id is a fresh id the server has never seen, so
  /// it runs the whole pipeline again instead of answering with what it already produced.
  String? _openTurnId;

  String? _bridgeMode;
  bool _awaitingCalibration = false;
  String? _pendingTakePath;
  StreamSubscription<void>? _playbackDone;
  StreamSubscription<void>? _playbackFailed;
  StreamSubscription<void>? _playbackOpened;
  StreamSubscription<void>? _networkWatch;
  StreamSubscription<CoverageEvent>? _coverageWatch;
  String? _coverageSessionId;
  String? _awaitingCoverageTurnId;
  String? _resolvedCoverageTurnId;
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
    _parteARegravar = null;
    state = state.copyWith(clearLastSpoken: true);
    _onPlaybackComplete = null;
    _onPlaybackFailed = null;
    unawaited(_voice.stop());
    unawaited(_playback.stop());
    unawaited(_recorder.discard());
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
    _playbackFailed ??= _playback.failures.listen((_) => _cannotPlayTheirOwnAudio());
    _playbackOpened ??= _playback.openings.listen((_) {
      _watchPlayback();
      _medirAParteNoAr();
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
        : await _voice.playAsset(fixedLineAsset(fixedLine, _lingua));
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
  /// the grid's own players already offer.
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
    final played = await _speak(line.url, line.fixedLine, panoramaUrl: line.panoramaUrl);
    if (epoch != _epoch) return;
    if (!played) return _registerUnplayableTurn(leavesTeamTalk: false);
    _unplayableTurns = 0;
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
    if (!played) return _registerUnplayableTurn(leavesTeamTalk: false);
    _watchBusyState();
    final scene = await _speak(line.url, '', panoramaUrl: line.panoramaUrl);
    if (epoch != _epoch) return;
    if (!scene) return _registerUnplayableTurn(leavesTeamTalk: false);
    _unplayableTurns = 0;
    state = state.copyWith(voice: VoiceState.invite);
  }

  Future<void> _voiceTurn(TurnResult turn, int epoch) async {
    if (epoch != _epoch) return;
    _captureBridgeMode(turn);
    state = state.copyWith(coverage: turn.coverage);
    _awaitCoverageSettle(turn);
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
    _inaudibleSpoken = 0;
    _openTurnId = null;
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
    _awaitCoverageSettle(turn);
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

  void _registerUnplayableTurn({bool leavesTeamTalk = true}) {
    _openTurnId = null;
    _unplayableTurns++;
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

  void _haltForAPerson({bool sessionIsGone = false, bool reachable = true}) {
    _leaveThinking();
    if (!state.needsPerson) {
      unawaited(_voice.playAsset(fixedLineAsset(needsPersonLine, _lingua)));
    }
    state = state.copyWith(
      voice: VoiceState.needsPerson,
      peerCue: false,
      clearSession: sessionIsGone,
    );
    if (reachable) _tellTheRoomAPersonIsNeeded();
    // A halt the desk has already been told about is watched from here; one still being
    // called in starts its watch when the call lands, and a halt nobody could be told
    // about is not watched at all.
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
    if (sessionId == null || !state.needsPerson) return;
    final epoch = _epoch;
    try {
      final snapshot = await _room.fetchState(sessionId);
      if (epoch != _epoch || _haltWatched != sessionId) return;
      if (!snapshot.needsPerson) {
        _leaveTheHalt();
        return;
      }
    } on SessionGone {
      // There is no longer a session to be let out of, so there is nothing left to ask:
      // the room keeps the halt and the long press is the way out of it, as it is for a
      // build with no session at all.
      if (epoch != _epoch || _haltWatched != sessionId) return;
      _haltWatched = null;
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
    final step =
        _personAskStep < backoff.length ? _personAskStep : backoff.length - 1;
    _personAskStep++;
    _after('person', backoff[step], () => unawaited(retry()));
  }

  void _handleRoomFailure(Object error) {
    _leaveThinking();
    switch (error) {
      case RoomRefused():
        _haltForAPerson();
      case SessionGone():
        _haltForAPerson(sessionIsGone: true);
      case PassageShut():
        _haltForAPerson();
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
  }

  void _registerRoomFailure() {
    _roomFailures++;
    _conviteOpened = false;
    if (_roomFailures >= _roomFailuresBeforeNeedsPerson) {
      _haltForAPerson();
      return;
    }
    state = state.copyWith(voice: VoiceState.invite, peerCue: false);
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
  /// A correction under it is over with it, so that stretch goes back to waiting. This is
  /// the seam rather than `_handleRoomFailure`, because the watchdog that gives up on a
  /// busy state is not a room failure — it is this tablet deciding the wait is over — and
  /// it is the one give-up that fires while a correction's own call is in the air, with no
  /// refusal and no offline circle to show for it. Both stations do all their waiting in
  /// this phase, so this is where the promise the band made is taken back.
  void _leaveThinking() {
    if (state.stage == SalaStage.retro && state.btPhase == BtPhase.thinking) {
      state = state.copyWith(btPhase: BtPhase.playing, btConsertando: false);
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
      unawaited(_voice.playAsset(offlineNoticeAsset(_lingua)));
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

  void _leaveTheHalt() {
    _haltWatched = null;
    _timers.remove('halt')?.cancel();
    _timers.remove('retry')?.cancel();
    _timers.remove('person')?.cancel();
    _personAsked = false;
    _personAskStep = 0;
    _unplayableTurns = 0;
    _roomFailures = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    unawaited(_networkWatch?.cancel());
    _networkWatch = null;
    state = state.copyWith(voice: VoiceState.invite);
    if (state.sessionId == null && state.stage == SalaStage.conversa) {
      unawaited(goConversa(pericope: _emCurso));
    }
  }

  /// Arms the wait for the coverage channel to say what this turn's classification
  /// decided. A turn the server never meant to grade — no id, or nothing pending — has
  /// nothing to wait for, so it is not the panorama's own turns that skip this: it is any
  /// turn the server already settled by the time it answered. Called twice per turn, once
  /// before it speaks and once after — a turn the channel already settled while it spoke
  /// stays settled, rather than being rearmed for the same wait a second time.
  void _awaitCoverageSettle(TurnResult turn) {
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
    _after('coverage', ref.read(coverageFallbackDelayProvider), () {
      if (_awaitingCoverageTurnId != turnId) return;
      _resolveCoverageWait(sessionId, turnId, pullState: true);
    });
  }

  void _watchCoverageChannel(String sessionId) {
    if (_coverageSessionId == sessionId) return;
    unawaited(_coverageWatch?.cancel());
    _coverageSessionId = sessionId;
    _coverageWatch = _room.watchCoverage(sessionId).listen(_onCoverageFrame);
  }

  void _onCoverageFrame(CoverageEvent frame) {
    if (frame.turnId != _awaitingCoverageTurnId) return;
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    _resolveCoverageWait(
      sessionId,
      frame.turnId,
      pullState: frame.status == CoverageStatus.settled,
    );
  }

  void _resolveCoverageWait(String sessionId, String turnId, {required bool pullState}) {
    _awaitingCoverageTurnId = null;
    _resolvedCoverageTurnId = turnId;
    _timers.remove('coverage')?.cancel();
    if (pullState) unawaited(_pullState(sessionId).catchError((_) {}));
    unawaited(_pullInbox());
  }

  Future<void> _pullState(String sessionId) async {
    final epoch = _epoch;
    try {
      final snapshot = await _room.fetchState(sessionId);
      if (epoch != _epoch || state.sessionId != sessionId) return;
      final told = snapshot.coverage;
      final before = state.coverage.engaged;
      // A turn that carried no coverage, or fewer beads than the necklace already shows,
      // leaves the necklace where it is. Reading a missing field as zero emptied the cord
      // mid-passage — the only record of progress this team can perceive — and a read
      // that raced ahead of a slower one used to be able to put it back.
      if (told != null && told.engaged >= before) {
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
      // A warning follows the last state read, and only the last one: a turn landing
      // or the facilitator attending the session on the Desk both show up here as a
      // read that no longer says it, and that is what turns the circle back.
      state = state.copyWith(warning: snapshot.halt == HaltKind.warning);
      if (snapshot.needsPerson) {
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
      if (given != null && given != panoramaPericope) {
        // The room answering a passage is its word that the panorama was heard. Left
        // unwritten, a tablet without the mark asked for the panorama on every launch and
        // adopted a new session each time, its coverage starting over from zero.
        unawaited(_feitas.markBookOpened(_book).catchError((_) {}));
        unawaited(goConversa(pericope: given, opened: created));
        return;
      }
      final panorama = _panoramaSessionId ?? created!.sessionId;
      _panoramaSessionId = panorama;
      final turn =
          await _room.openSession(panorama, turnId: _openTurnId ??= _stamp());
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
      return;
    }
    _unplayableTurns = 0;
    _roomFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _openTurnId = null;
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
    if (path == null || !_hasAudio(path)) {
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
      todas = await _room.passagesOf(_book, language: _lingua);
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
    state = state.copyWith(
      naRoda: todas,
      comecadas: comecadas,
      feitas: feitas,
      aOferecer: 0,
      voice: VoiceState.invite,
    );
    if (todas.every((passagem) => passagem.isPanorama)) {
      // Nothing left for the room to offer, which is exactly what needsPerson means —
      // and it is the only state here with a glyph, a spoken line and a way out. A green
      // disc that refused every gesture in silence looked like a room that had died.
      //
      // The panorama's own spoke is not a passage.
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
    final spoke = await _speak(passagem.audioUrl, '');
    if (moved()) return;
    // A wheel that has gone silent looks to the team exactly like a wheel that has
    // stopped, and there is no written word here to tell them apart.
    if (!spoke) return _registerUnplayableTurn();
    _unplayableTurns = 0;
    state = state.copyWith(voice: VoiceState.invite);
  }

  void entrarNaOferecida() {
    final passagem = state.oferecida;
    if (passagem == null || state.voice != VoiceState.invite) return;
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
      if (given != null && given != panoramaPericope) {
        unawaited(goConversa(pericope: given, opened: created));
        return;
      }
      final panorama = _panoramaSessionId ?? created!.sessionId;
      _panoramaSessionId = panorama;
      final turn =
          await _room.openSession(panorama, turnId: _openTurnId ??= _stamp());
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
      _handleRoomFailure(error);
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
    // A place belongs to the passage it was mended in. Carried into the next one they
    // enter, the places of the last would be written into its row of the ledger.
    _lugares.clear();
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
    final waiting = opened == null &&
            !fresh &&
            pericope != null &&
            state.comecadas.contains(pericope)
        ? await _emAberto.of(_book, pericope)
        : null;
    if (epoch != _epoch) return;
    try {
      final resumed = waiting != null;
      final created = opened ??
          (waiting == null
              ? await _room.createSession(
                  pericope: pericope,
                  afterSession: _panoramaSessionId,
                  bridgeMode: _bridgeMode,
                  language: _lingua,
                )
              : null);
      final sessionId = waiting?.sessionId ?? created!.sessionId;
      if (epoch != _epoch) return;
      state = state.copyWith(sessionId: sessionId, coverage: created?.coverage);
      if (pericope != null && !resumed) {
        unawaited(_mindingThePlace(
          () => _emAberto.remember(
            _book,
            pericope,
            ResumePoint(sessionId: sessionId, stage: SalaStage.conversa),
          ),
        ));
      }
      unawaited(_pullInbox());
      _watchBusyState();
      if (resumed) {
        final pastTheConversa =
            await _backToWhereTheyStopped(waiting, epoch, pericope!);
        if (epoch != _epoch) return;
        if (pastTheConversa) {
          final snapshot = await _room.fetchState(sessionId);
          if (epoch != _epoch) return;
          state = state.copyWith(
            coverage: snapshot.coverage,
            warning: snapshot.halt == HaltKind.warning,
          );
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
          if (snapshot.needsPerson) _haltForAPerson();
          return;
        }
        if (waiting.stage == SalaStage.retro) {
          final told = (await _room.fetchState(sessionId)).backTranslation;
          if (epoch != _epoch) return;
          // Only when there is a telling-back to land on. A checked answer carrying no
          // stretch contradicts itself — the check is about what was told — and
          // [_pickTheTellingBackUp] rightly declines it, which left the room standing in
          // the conversa until the watchdog called a person two minutes later. It falls
          // through to the turn instead, which is the door every other empty answer takes:
          // closing would call a passage the team never approved its final draft.
          if (told.checked && !told.nothingTold) {
            _pickTheTellingBackUp(told);
            return;
          }
          if (!told.nothingTold) {
            final restarted = await _room.restartBackTranslation(sessionId);
            if (epoch != _epoch) return;
            if (restarted.needsPerson) state = state.copyWith(warning: true);
          }
        }
      }
      // Re-opening carries the coverage back with it, so the necklace fills itself.
      await _voiceTurn(
        await _room.openSession(sessionId, turnId: _openTurnId ??= _stamp()),
        epoch,
      );
    } on SessionGone {
      if (epoch != _epoch) return;
      if (pericope != null) {
        unawaited(_mindingThePlace(() => _emAberto.forget(_book, pericope)));
      }
      if (fresh) {
        // Already the clean attempt: the server is refusing the passage itself, not the
        // session we remembered. Retrying again is the loop this guard exists to stop.
        _haltForAPerson(sessionIsGone: true);
        return;
      }
      // The tablet remembered a session the server has forgotten. Start clean, once.
      unawaited(goConversa(pericope: pericope, fresh: true));
    } on PassageShut {
      if (epoch != _epoch) return;
      unawaited(abrirEscolha());
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
    unawaited(_mindingThePlace(
      () => _emAberto.remember(
        _book,
        pericope,
        ResumePoint(
          sessionId: sessionId,
          stage: stage,
          takes: state.keptTakes,
          pass: state.ensaioPass,
          lugares: List.of(_lugares.values),
        ),
      ),
    ));
  }

  /// Put the team back on the stage they left, when the audio for it is still here.
  Future<bool> _backToWhereTheyStopped(
    ResumePoint waiting,
    int epoch,
    String pericope,
  ) async {
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
      //
      // The row is rewritten at the conversa, with no rehearsal in it. Left as it was,
      // the same failed resume runs on every single opening from here on, and an
      // unbounded repeat is the harm — one failed resume is survivable.
      //
      // Rewritten rather than forgotten, because the session id lives nowhere else:
      // `ir_sessions` carries no device, so dropping the row would abandon that session
      // on the server the moment the team closed the app during the conversa, and take
      // the passage off the wheel along with it. Nothing writes this row again until the
      // team reaches the ensaio, which is a long way from where they now are. With no
      // takes in it the next opening finds nothing to restore and goes straight through,
      // so the repeat is gone and the id survives. Where the team lands is unchanged.
      if (!_gone) {
        unawaited(_mindingThePlace(
          () => _emAberto.remember(
            _book,
            pericope,
            ResumePoint(
              sessionId: waiting.sessionId,
              stage: SalaStage.conversa,
            ),
          ),
        ));
      }
      return false;
    }
    _lugares
      ..clear()
      ..addEntries([
        for (final lugar in waiting.lugares)
          MapEntry(lugar.segmentId ?? lugar.takeId, lugar),
      ]);
    state = state.copyWith(
      stage: SalaStage.ensaio,
      ensaio: EnsaioStatus.idle,
      voice: VoiceState.invite,
      keptTakes: here,
      // Counted among the rehearsal's own parts — `here` can also carry a correction's
      // own take, kept beside the parts but not one of them.
      takes: here.where((take) => KeptScope.isParte(take.scopeId)).length,
      ensaioPass: waiting.pass,
    );
    unawaited(_countUnsent());
    return true;
  }

  /// Every reopening landed on the rehearsal, so a team that had stopped part-way through
  /// telling it back recorded the whole passage a second time and the session ended
  /// holding two of everything. A room with no stretch has no telling-back to pick up.
  void _pickTheTellingBackUp(BackTranslationProgress told) {
    if (told.nothingTold) return;
    state = state.copyWith(
      stage: SalaStage.retro,
      voice: told.checked ? VoiceState.done : VoiceState.invite,
      btPhase: told.checked ? BtPhase.conferida : BtPhase.playing,
      btTrechos: _trechosFrom(told.segments),
      btChunkPasses: [
        for (final segment in told.segments) segment.passNumber,
      ],
    );
    final sessionId = state.sessionId;
    if (sessionId != null) {
      unawaited(_alcancarAsCompostas(sessionId, told.segments, _epoch));
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
    state = state.copyWith(
      btTrechos: _trechosFrom(told.segments),
      btChunkPasses: [
        for (final segment in told.segments) segment.passNumber,
      ],
    );
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

  bool _hasAudio(String path) =>
      File(path).existsSync() && File(path).lengthSync() > 0;

  Future<void> _finishListening() async {
    final epoch = _epoch;
    final path = await _recorder.stop();
    if (epoch != _epoch) return;
    final sessionId = state.sessionId;
    if (path == null || !_hasAudio(path)) {
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
    unawaited(_voice.playAsset(fixedLineAsset(line, _lingua)));
  }

  Future<void> _askThemToRepeat(String path) async {
    unawaited(_recorder.delete(path));
    if (_inaudibleSpoken > 0) {
      _haltForAPerson();
      return;
    }
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.speaking, peerCue: false);
    _watchBusyState();
    final line = inaudibleLines.first;
    _inaudibleSpoken++;
    await _voice.playAsset(fixedLineAsset(line, _lingua));
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
    unawaited(_markHeard(reply.id));
    if (played) return;
    // No strike count here, unlike every other line. A reply the room could not play is
    // one only a person can now relay, so it calls for one at once; giving this path the
    // three strikes a turn gets would lose three answers before anyone was called, and a
    // turn survives its strikes only because the room can say it again.
    //
    // The mark above is no longer unconditional, so a reply that did not play and whose
    // mark the desk turns down does come back to the list. That is the honest state and
    // it was chosen over a retry: the desk never learned, so the reply is still owed. It
    // is not the trap the doc above describes, because the room is halted from here and
    // the hand answers no one until a person resolves it.
    _haltForAPerson();
  }

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
  Future<void> _markHeard(String replyId) async {
    final epoch = _epoch;
    state = state.copyWith(replies: _replies(replyId, heard: true), clearPlayingReply: true);
    if (await _inbox.markHeard(replyId)) return;
    if (_gone || epoch != _epoch) return;
    state = state.copyWith(replies: _replies(replyId, heard: false));
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
    if (path == null || !_hasAudio(path) || sessionId == null) {
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
    await _voice.playAsset(fixedLineAsset(rotated(handoffLines, asked), _lingua));
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
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
    _startOver();
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
    // The retro's own stretches, once it has any, are the passage: a correction lives in
    // one of them and nowhere among the raw parts, so hearing the passage means hearing
    // them, in the order the necklace already holds them.
    if (state.btTrechos.isNotEmpty) {
      _tocarTrechoFantasma();
    } else {
      _tocarParteFantasma();
    }
  }

  void _tocarTrechoFantasma() {
    void backToTheCircle() {
      state = state.copyWith(ensaio: EnsaioStatus.idle);
    }

    void aProximo() {
      _ghostParte++;
      if (_ghostParte >= state.btTrechos.length ||
          state.ensaio != EnsaioStatus.ghostPlaying) {
        backToTheCircle();
        return;
      }
      _tocarTrechoFantasma();
    }

    final trecho = state.btTrechos[_ghostParte];
    final onde = _ondeTocar(trecho);
    if (onde == null) {
      aProximo();
      return;
    }
    _clipHeld = false;
    _onPlaybackComplete = aProximo;
    _onPlaybackFailed = backToTheCircle;
    _listenForTheEnd();
    unawaited(_playback.playRange(onde.$1, onde.$2, onde.$3));
    _watchPlayback(clipStillOpening: true);
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
    if (state.needsPerson) return;
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
    if (path == null || !_hasAudio(path)) {
      // Nothing came back. Offering keep, redo and listen over a take that does not exist
      // let a team confirm a rehearsal into nothing — the buttons vanished exactly as on a
      // good keep, no bead appeared, and the way to the retro never opened.
      state = state.copyWith(ensaio: EnsaioStatus.idle);
      _haltForAPerson();
      return;
    }
    _pendingTakePath = path;
    state = state.copyWith(
      ensaio: EnsaioStatus.recorded,
      playPing: false,
      takePaused: false,
    );
  }

  /// Play the take, pausing and resuming it on the taps after the first.
  ///
  /// Modelled on [ouvirVozMaterna]: the same [_holdClip]/[_letTheClipRun] pair, and its own
  /// pair of flags for the same reason — a tap has to tell a resume from a restart, and
  /// nothing else here carries that.
  void takePlay() {
    final path = _pendingTakePath;
    if (path == null) return;
    if (state.playPing) {
      _holdClip();
      state = state.copyWith(playPing: false, takePaused: true);
      return;
    }
    if (state.takePaused) {
      state = state.copyWith(playPing: true, takePaused: false);
      _letTheClipRun();
      return;
    }
    state = state.copyWith(playPing: true, takePaused: false);
    void stopThePulse() {
      state = state.copyWith(playPing: false, takePaused: false);
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
    final regravada = _parteARegravar;
    _parteARegravar = null;
    if (regravada != null && regravada < state.partes.length) {
      _aParteVoltaAoSeuLugar(regravada, path);
      return;
    }
    // Counted among the rehearsal's own parts, never among the corrections a trecho may
    // already have picked up in this same ensaio — those live in keptTakes too, but are
    // not parts of the rehearsal in their own right.
    final parte = state.partes.length + 1;
    final escopo = KeptScope.parte(parte);
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [...state.keptTakes, KeptTake(scopeId: escopo, path: path)],
      takes: parte,
    );
    unawaited(_guard(
      path,
      kind: 'ensaio',
      scope: escopo,
      passNumber: state.ensaioPass,
      chunkIndex: parte,
    ));
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
  /// the cord would draw them over ground nobody has explained yet and the next
  /// telling-back would step over a part the team has not heard. They leave as untold
  /// ground and not as drained bands: a drained band means waiting to be mended, and
  /// this ground is waiting to be told.
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
    final trechos = <Trecho>[];
    final passes = <int>[];
    for (var onde = 0; onde < state.btTrechos.length; onde++) {
      if (state.btTrechos[onde].parte == parte) continue;
      trechos.add(state.btTrechos[onde]);
      if (onde < state.btChunkPasses.length) passes.add(state.btChunkPasses[onde]);
    }
    state = state.copyWith(
      ensaio: EnsaioStatus.idle,
      keptTakes: [
        for (final take in state.keptTakes)
          if (take.scopeId == escopo)
            KeptTake(scopeId: escopo, path: path)
          else
            take,
      ],
      btTrechos: trechos,
      btChunkPasses: passes,
    );
    unawaited(_medirAParteRegravada(path, _epoch));
    unawaited(_guard(
      path,
      kind: 'ensaio',
      scope: escopo,
      passNumber: state.ensaioPass,
      chunkIndex: numero,
    ));
    _rememberWhereTheyAre(SalaStage.ensaio);
  }

  /// The cord is drawn over the parts as they now are, and this part is a file of its own
  /// length. Measured here rather than left to the next playthrough, for the reason the
  /// rebuilt passage is measured where it is swapped in.
  Future<void> _medirAParteRegravada(String arquivo, int epoch) async {
    final quanto = await _playback.howLong(arquivo);
    if (quanto == null || epoch != _epoch || _gone) return;
    _tamanhoDaParteMs[arquivo] = quanto.inMilliseconds;
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

  /// Answers what the room called this recording, or null while it has not answered.
  Future<String?> _guard(
    String path, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    if (_gone) return null;
    final queue = _takes;
    final sessionId = state.sessionId;
    final audio = File(path);
    if (!await audio.exists()) return null;
    if (sessionId == null) {
      // The room lost the session — a 404 clears it — and a take has nowhere to go
      // without one. The bead had already been filled by `takeKeep`, so this returned in
      // silence and the recording read as delivered.
      _sayARecordingIsStranded();
      return null;
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
      return null;
    }
    await _countUnsent();
    await queue.flush();
    await _countUnsent();
    if (kind != 'ensaio') return null;
    return _adoptTheName(queue, linha.id, path);
  }

  /// Take back the name the room gave a rehearsal recording.
  ///
  /// A told-back stretch is a slice of one recording and says which, and this is the only
  /// moment that name is ever said. It is written beside the file rather than fetched
  /// later because the two are halves of one thing: the retro is already local to the
  /// tablet that recorded it — a rehearsal whose files are not here is refused a resume —
  /// so there is no second tablet to fetch it for.
  ///
  /// The name goes to the file it was given for, never to every take of the scope: a part
  /// recorded again shares its scope with the recording it replaced, and the outbox row
  /// is what tells the two apart.
  Future<String?> _adoptTheName(
    TakeUploadQueue queue,
    String linha,
    String arquivo,
  ) async {
    final id = await queue.takeIdOf(linha);
    if (id == null || _gone) return null;
    state = state.copyWith(keptTakes: [
      for (final take in state.keptTakes)
        if (take.path == arquivo) take.withTakeId(id) else take,
    ]);
    return id;
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
      // The microphone a correction was going to speak into never opened, so the mend
      // has not started after all and that stretch is waiting again.
      btConsertando: false,
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
    if (_gone || epoch != _epoch || counting != _newestCount) return;
    state = state.copyWith(
      unsentTakes: takes,
      unsentChunks: chunks,
      unsentTakeScopes: scopes,
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
      btChunkFailures: const [],
      btClipEnded: false,
      btFindings: const [],
      btPass: 1,
      peerCue: false,
    );
    unawaited(_playFromTheUntoldGround(_epoch));
  }

  /// How far short of a part's end the told ground may stop and still count as its end.
  ///
  /// The last cut of a part is made where the clip stopped, and a position read as a
  /// clip finishes can sit a little before the length measured without playing it. This
  /// end's choice: the number is the slack the room's gate was read to allow itself when
  /// it checks what was heard, not a contract the room promises.
  static const _fimDaParte = Duration(milliseconds: 750);

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
  /// left to tell, so the clip still reaches its end and `terminei` is still offered.
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
    // Everything up to the first measurement runs before this function first yields, so
    // a retro with nothing told back yet starts its clip in the same call that asked for
    // it, as it always did. The measuring is the only part that waits.
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _tamanhoDaParteMs.clear();
    _pousadaNaParteNaoOuvida = false;
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
      // one opened `terminei` over an empty back translation.
      _haltForAPerson();
      return;
    }
    var parte = 0;
    if (_chaoExplicadoDe(0) > Duration.zero) {
      // Measuring waits on the player, and the screen it waits under is the retro with
      // its buttons up: a cut landing inside the wait opened the microphone over a clip
      // about to start, with the cursor at nought. Busy is the honest state for it.
      state = state.copyWith(btPhase: BtPhase.thinking, voice: VoiceState.thinking);
      _watchBusyState();
      while (parte < partes.length - 1) {
        final contadaAte = _chaoExplicadoDe(parte);
        if (contadaAte == Duration.zero) break;
        final quanto = await _playback.howLong(partes[parte].path);
        if (epoch != _epoch) return;
        if (quanto == null || contadaAte + _fimDaParte < quanto) break;
        _marcarOFimDaParte(parte, quanto.inMilliseconds);
        _escuta.inteira(partes[parte].path, quanto.inMilliseconds);
        parte++;
      }
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btFimDasPartesMs: _fimDaParteMs,
      );
    }
    _tocarParteDaRetro(parte);
  }

  /// Where each part ends along the cord, the parts glued end to end in the order they
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

  /// Where [parte] begins along the cord: what the parts before it add up to, as far as
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

  /// Where a position inside the part in the air sits on the cord, which is drawn over the
  /// parts glued end to end. The necklace's job, and the only place the offset is added.
  int _pontoNoColar(int local) => _inicioDaParteMs(_parteTocando) + local;

  /// Write down how long [parte] turned out to be, once it has measured itself.
  void _marcarOFimDaParte(int parte, int medido) {
    final partes = state.partes;
    if (parte < 0 || parte >= partes.length || medido <= 0) return;
    _tamanhoDaParteMs[partes[parte].path] = medido;
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

  /// How far into the whole rehearsal the sound in the air has got, asked for right now.
  ///
  /// Asked many times a second by the cord while a part plays. It is a question, not a
  /// piece of state, on purpose: an answer written into [SalaSessionState] would rebuild
  /// everything that watches the session at that rate.
  ///
  /// A part is in the air from the moment the room asks for it, and open only once it has
  /// loaded — and until it loads the player still answers for the part before it. That
  /// stale position, added to the new part's offset, is a place past the end of the part
  /// being opened; measured against the part's length the moment it lands, it put the
  /// bead on the far end of the cord for as long as a tick. A part that has not said its
  /// length yet has not sounded, and the beginning the room wrote down is the whole of
  /// what is known about it.
  int get ouvidoAgoraMs {
    final noAr = state.btParteNoArMs;
    if (noAr == 0) return state.btOuvidoMs;
    final inicio = _inicioDaParteMs(_parteTocando);
    return (inicio + _playback.position.inMilliseconds)
        .clamp(inicio, inicio + noAr);
  }

  void _seguirOClipe() {
    _desdeMs = _playback.position.inMilliseconds;
    final arquivo = _parteNoAr?.path;
    if (arquivo != null) _escuta.abrir(arquivo, _playback.position.inMilliseconds);
    state = state.copyWith(btClipRodando: true);
    _letTheClipRun();
  }

  /// Stop the rehearsal and write down how far it got.
  ///
  /// [ate] is the true end of a part, which the part's own duration knows better than the
  /// player's position at the moment it finished. Both it and the player's answer are
  /// positions inside the file in the air: the ledger is never handed a place on the cord.
  void _pararOClipe({int? ate}) {
    _holdClip();
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
  void _tocarParteDaRetro(int parte, {bool doComeco = false}) {
    _parteTocando = parte;
    _trechoStart = _ondeParouNesteArquivo(parte);
    _desdeMs = 0;
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
    );
    _play(
      state.partes[parte].path,
      from: doComeco ? Duration.zero : _trechoStart,
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
    final medido = _playback.playingLength?.inMilliseconds ??
        _playback.position.inMilliseconds;
    final arquivo = _parteNoAr?.path;
    // And never a nought, on either of them. A part is never nought milliseconds long, so
    // a nought here is the player with nothing to say about the clip that just ended. The
    // ledger's copy is the `clip_duration_ms` the report carries, which is what the room
    // reads to decide this very refusal: a part the team heard whole, reported as nought
    // milliseconds long, is the same *terminei* refused again.
    if (arquivo != null && medido > 0) _escuta.medida(arquivo, medido);
    _marcarOFimDaParte(_parteTocando, medido);
    _pararOClipe(ate: medido);
    // Whether the rehearsal has played through, which is what the finish waits on, and
    // whether the cord can draw every part, which is the ruler's business: one question
    // each. They were one line while the ruler could only fill in order, so the last part
    // ending and the ruler being complete were the same instant. A landing jumps over a
    // part, and a part nothing could measure then held the boundary open past the end of
    // the row: the room offered a crossing into a part that is not there.
    final ultima = _parteTocando >= state.partes.length - 1;
    final pousada = _pousadaNaParteNaoOuvida;
    _pousadaNaParteNaoOuvida = false;
    state = state.copyWith(
      btClipEnded: ultima || pousada,
      btParteFronteira: !ultima,
      btFimDasPartesMs: _fimDaParteMs,
      btParteNoArMs: 0,
    );
  }

  /// Listen to the rehearsal, hold it, or cross into the next part.
  ///
  /// One gesture with one meaning. It used to share the circle with cutting a stretch and
  /// opening the microphone, which is why the room could only guess how much had been
  /// heard.
  void ouvirGravacao() {
    if (state.stage != SalaStage.retro) return;
    final conferida = state.btPhase == BtPhase.conferida;
    if (state.btPhase != BtPhase.playing && !conferida) return;
    if (state.needsPerson || state.offline) return;
    if (state.btTrechoTocando) return;
    if (state.btClipRodando) {
      _pararOClipe();
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
    if (!_traduzindoDeNovo) {
      // The player's own position, not a place in the concatenated passage: a stretch is a
      // slice of the file that is playing, and its two times are counted from that file's
      // beginning.
      //
      // A belt. No way the room starts playback puts the playhead behind the cursor any
      // more — a part picked back up opens at its cursor, crossing into a part opens at
      // that part's, and holding the clip and letting it run again never rewinds — but
      // the position is the player's answer, not the room's, and a player that comes back
      // from behind it would send a stretch that ends before it begins and then walk the
      // cursor backwards over every stretch after it.
      if (_playback.position < _trechoStart) return;
      _trechoEnd = _playback.position;
    }
    _pararOClipe();
    _startChunkCapture();
  }

  /// Cut the stretch that is playing in two, where the team is hearing it.
  ///
  /// It only ever answers for the stretch in the air, which is the only stretch the team
  /// can hear again: the room leads them to the one a finding named, and nothing else
  /// replays a stretch they already told. So there is nothing to choose first — what is
  /// playing is what divides — and the point is where the audio is, which is the same
  /// relation the other pair of scissors already has.
  ///
  /// The position is read from the player, which is playing inside one file, so it is
  /// already counted from that recording's beginning. Adding the parts before it would be
  /// the global timeline under a new name.
  ///
  /// The finding ends here rather than being handed on. The two halves are born with no
  /// explanation, and the first round does not run while a final stretch is missing one,
  /// so no verdict stands until the team has told them both — and the finding that comes
  /// back after that names the half it belongs to, decided by reading rather than by a
  /// guess of ours. Cleared, not left unpointed: the branch for a finding with no stretch
  /// exists for an analyst who could not attribute one, which is a different thing from a
  /// finding that is over.
  Future<void> dividirTrecho() async {
    if (state.stage != SalaStage.retro) return;
    if (!state.btTrechoTocando) return;
    if (state.needsPerson || state.offline) return;
    final sessionId = state.sessionId;
    final trecho = state.btFindingTrecho;
    final named = trecho?.segmentId;
    if (sessionId == null || trecho == null || named == null) return;

    final at = _playback.position;
    final epoch = _epoch;
    try {
      final told = await _room.divideSegment(sessionId, named, at: at);
      if (epoch != _epoch) return;
      final trechos = _trechosFrom(told);
      if (trechos.isEmpty) return;
      _holdClip();
      state = state.copyWith(
        btTrechos: trechos,
        btChunkPasses: [for (final segment in told) segment.passNumber],
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btFindings: const [],
        btTrechoTocando: false,
        clearFindingSegment: true,
      );
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    }
  }

  /// Tell one stretch again: the same slice of the same recording, a new explanation.
  ///
  /// This is the correction that leaves the mother tongue where it is — the one the room
  /// needs after a division, because the two halves are born with nothing told about them
  /// and the first round does not run while a final stretch is missing its explanation.
  /// Telling a stretch back the ordinary way makes a *new* one at the next position, so
  /// it could never fill a half; this fills it.
  ///
  /// A stretch with no name is not offered: the route addresses one, and the room has no
  /// way to explain a refusal to a team that cannot read.
  Future<void> traduzirDeNovo(Trecho trecho) async {
    if (state.stage != SalaStage.retro) return;
    // Two doors reach the same verb: the cord, where a stretch is tapped while the
    // rehearsal plays, and the question the room puts when the analyst points at one.
    if (state.btPhase != BtPhase.playing && state.btPhase != BtPhase.findings) {
      return;
    }
    // The warning asks for a person; it is not a ceiling. Both microphones keep
    // opening while it is up — only offline, which cannot record anything to send,
    // closes this one.
    if (state.offline) return;
    if (state.btTrechoTocando) return;
    if (trecho.segmentId == null) return;
    _pararOClipe();
    _trechoTraduzidoDeNovo = trecho;
    // The short way's whole gesture is this one: choosing it opens the microphone on the
    // stretch, and that is where its mend starts. Conditioned rather than asserted,
    // because the other door here is a half born of a division, which no finding points
    // at — and a flag that claimed a mend of nothing would be a lie about itself.
    state = state.copyWith(
      btConsertando: state.btFindingSegmentId == trecho.segmentId,
    );
    _startChunkCapture();
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
    } on Exception catch (error) {
      unawaited(_guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ));
      if (epoch != _epoch) return;
      state = state.copyWith(
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      _handleRoomFailure(error);
      return;
    }

    if (!told.captured) {
      // The room made nothing out of it, which is also what a transcriber outage looks
      // like from here. The stretch is left exactly as it was — an explanation is not
      // swapped for an empty one over somebody else's failure — and their audio is kept.
      unawaited(_guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ));
      // A refusal leaves the stretches as they were, so the ground told back is the same
      // ground the taken correction would have left: read it off what the tablet already
      // holds rather than off an answer that carries nothing.
      _walkTheCursorBack(state.btTrechos);
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
        btConsertando: false,
      );
      if (told.needsPerson) _haltForAPerson();
      return;
    }

    // The telling just recorded is this stretch's own. Only a first telling used to keep
    // its file, so from the first correction on the blue voice played back the very
    // explanation the analyst had refused — and after the mother tongue was told again,
    // which leaves no telling to inherit, it played nothing at all, for good.
    final trechos = _trechosFrom(
      told.segments,
      lugar: lugar,
      noLugarDe: alvo,
      contadoEm: path,
    );
    // A version is minted on every route through this replace, composed or not, so the
    // stretch just retold names a segment [alvo] never carried. The place kept for it —
    // written when the mother tongue was corrected, if it was — has to move to the new
    // name too, or a resume between here and the next mend finds nothing under it. Read
    // by [alvo]'s own name first — the one the mend that set it wrote under — and by its
    // take for the older mend that never named a segment.
    if (lugar >= 0 && lugar < trechos.length) {
      final novo = trechos[lugar];
      final antigo = (alvo.segmentId != null ? _lugares[alvo.segmentId] : null) ??
          _lugares[alvo.takeId];
      if (novo.segmentId != null && antigo != null) {
        _lugares[novo.segmentId!] = LugarDoTrecho(
          takeId: novo.takeId,
          segmentId: novo.segmentId,
          parte: novo.parte,
          from: novo.lugarFrom,
          to: novo.lugarTo,
          fallbackPath: antigo.fallbackPath,
          fallbackFrom: antigo.fallbackFrom,
          fallbackTo: antigo.fallbackTo,
        );
      }
    }
    _walkTheCursorBack(trechos);
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btTrechos: trechos.isEmpty ? state.btTrechos : trechos,
      btChunkPasses: [for (final segment in told.segments) segment.passNumber],
    );
    _rememberWhereTheyAre(SalaStage.retro);
    if (epoch != _epoch) return;
    // The correction is finished, so the room goes and finds out what it was worth. The
    // team used to be handed back to the screen for hearing the recording, with nothing
    // said: the only way to learn whether the fix had taken was to press "terminei"
    // again, and nobody tells them that. From where they stand they had corrected the
    // stretch and nothing had happened.
    //
    // Only a correction arrives here — an ordinary telling during the back-translation
    // returns before this, and it should, because there is still passage left to hear and
    // tell. And on the mother tongue route this is the second of the two steps: the
    // re-recording does not pass through here, the retelling that follows it does, so the
    // result is asked for once and at the end.
    //
    // Nothing had to be unlocked for this: the mark that the recording ended survives a
    // correction, so the ask is allowed the moment it is made.
    await finishBackTranslation();
    // Not the epoch. The epoch moves whenever `_cancelTimers` runs, and going offline is
    // the commonest way that happens — so a hiccup on the verdict request above bumped it
    // and swallowed the news, and the team was invited back to tell stretches into a room
    // that had stopped taking them. Losing the network is exactly the moment the room
    // being spent still matters, so it cannot be the moment the news is dropped.
    //
    // Only the notifier being gone is read, because that is the only thing left that must
    // stop this. A team who walked out of the passage is already covered twice over: the
    // gesture empties the session, and the call for a person is only ever made when there
    // is a session to make it about.
    if (_gone) return;
    // A passage that came back clean wins over a room that has run dry. If the work is
    // right there is nothing left to correct, so the spent budget has stopped mattering,
    // and calling somebody to a passage that is over is noise in the queue the facilitator
    // has to trust. The team is left on the approval and nobody is sent for.
    if (state.btPhase == BtPhase.conferida) return;
    // The budget for retellings runs out on this route too, and the room says so in the
    // same breath as the answer. It used to be read only off telling a stretch, so a team
    // that hit the ceiling by correcting one saw nothing at all: the room had stopped
    // taking their work and they went on making more of it.
    //
    // Said after the answer is in, never instead of it. Losing what became of the
    // recording they just made, at the very moment the room stops, would be worse than
    // the silence this fixes — so the verdict above is asked for and spoken first, and
    // only then does the room stop. It has to be this way round and not the other: the
    // verdict walks the session's voice from thinking to speaking to done, and a halt
    // raised before it would be written over by that walk, leaving the team invited back
    // to work in a room that had stopped taking any.
    if (told.needsPerson) _haltForAPerson();
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
        unawaited(_repeatTheFinding());
      case BtPhase.gravandoMaterna:
        unawaited(_gravarAVozMaterna());
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
    final traduzidoDeNovo = _trechoTraduzidoDeNovo;
    _trechoTraduzidoDeNovo = null;

    if (path != null && !_hasAudio(path)) {
      _traduzindoDeNovo = false;
      _trechoStart = _ondeParouNesteArquivo(_parteTocando);
      state = state.copyWith(btPhase: BtPhase.playing, btConsertando: false);
      _haltForAPerson();
      return;
    }

    if (path == null || sessionId == null) {
      state = state.copyWith(
        btPhase: BtPhase.playing,
        voice: VoiceState.invite,
        btConsertando: false,
      );
      return;
    }

    if (traduzidoDeNovo != null) {
      // Cleared on this branch too, because it returns before the ordinary path clears
      // it. Left switched on, the next cut would ignore the player, reuse the bounds the
      // retelling had left behind, and upload as a correction of a stretch that is not
      // the one being told. It is cleared here rather than at the top: the ordinary path
      // reads it when it uploads, and clearing it above that turns every retelling into
      // an ordinary telling.
      _traduzindoDeNovo = false;
      await _tellThatStretchAgain(traduzidoDeNovo, path, sessionId, epoch);
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
      unawaited(_guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ));
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
        retelling: _traduzindoDeNovo,
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
        ));
        state = state.copyWith(
          btPhase: BtPhase.playing,
          voice: VoiceState.invite,
          btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
          // The room can ask for a person over a chunk it never captured — the two
          // are independent — and that ask is a warning like any other.
          warning: captured.needsPerson ? true : null,
        );
          return;
      }
    } on Exception catch (error) {
      unawaited(_guard(
        path,
        kind: 'retro',
        scope: KeptScope.whole,
        passNumber: state.btPass,
      ));
      if (epoch != _epoch) return;
      state = state.copyWith(
        btChunkFailures: [...state.btChunkFailures, _nextChunkPlace()],
      );
      _handleRoomFailure(error);
      return;
    }

    _traduzindoDeNovo = false;
    // The room asking for a person over a retold stretch is a warning: somebody is called
    // to come and watch, and the team is refused nothing. Stopping the retro on it ended
    // the telling-back over a note nobody had read yet.
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
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btChunkPasses: [...state.btChunkPasses, captured.passNumber],
      btTrechos: [...state.btTrechos, trecho],
      // Only ever set here, never cleared: the next state read is the one that says
      // the warning is over, the same way it would for one raised on a state read.
      warning: captured.needsPerson ? true : null,
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

      final naoOuvidas = verdict.unheardTakeIds;
      if (naoOuvidas.isNotEmpty) {
        await _levarAParteNaoOuvida(naoOuvidas.first, epoch);
        return;
      }

      if (verdict.checked) {
        // The finding is over, and so is the stretch it named. This branch returns above
        // the place the pointer is resolved, so a name outlived the objection that gave it
        // — and the cord went on drawing that stretch drained under a passage the room had
        // just called checked. It only showed after a correction the room made nothing of:
        // one that lands retires the name it replaces, so the pointer goes stale on its
        // own and matches nothing.
        state = state.copyWith(
          btPhase: BtPhase.conferida,
          voice: VoiceState.done,
          clearFindingSegment: true,
          // Its other half. The flag is switched on when the team takes a correction on
          // and nothing on the way out of one that lands switches it off, so it outlived
          // the session it belonged to. The two are one fact — whether a stretch is
          // waiting to be mended — and leaving one of them standing is half a cleanup for
          // whoever comes next.
          btConsertando: false,
        );
        return;
      }
      // The room names the stretch the finding lands on, and the name is the room's to
      // give: nothing in the chunk it answered ever said it. The stretches are read back
      // before the pointer is resolved, so it is resolved against names that exist.
      await _readTheStretchesBack(sessionId, epoch);
      if (epoch != _epoch) return;

      final naoTraduzido = verdict.untoldSegmentId;
      if (naoTraduzido != null) {
        _levarAoTrechoNaoTraduzido(naoTraduzido);
        return;
      }
      state = state.copyWith(
        btPhase: BtPhase.findings,
        voice: VoiceState.invite,
        btFindings: verdict.findingKind == null ? const [] : [verdict.findingKind!],
        btFindingSegmentId: verdict.findingSegmentId,
        clearFindingSegment: verdict.findingSegmentId == null,
        // A verdict is the room asking again, so nothing is being mended yet — including
        // when it points at the stretch the team just mended. Filling the band is not
        // permanent, and a mend that did not satisfy the analyst has to show as waiting a
        // second time.
        btConsertando: false,
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
        await _room.approveRelease(sessionId);
        if (epoch != _epoch) return;
        _aprovada = true;
      }
      final disse = await _voice.playAsset(fixedLineAsset(approvedLine, _lingua));
      if (epoch != _epoch) return;
      // As all five of its siblings do. Closing over a line the team never heard ends the
      // passage on a gesture nobody was answered for, and the press is the whole of what
      // the approval is.
      if (!disse) return _registerUnplayableTurn();
      _unplayableTurns = 0;
      _closeTheNecklace();
    } on ReleaseRefused {
      if (epoch != _epoch) return;
      _haltForAPerson();
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      _handleRoomFailure(error);
    } finally {
      _aprovando = false;
    }
  }

  /// Straight to the part the room says nobody heard, with the telling-back left standing.
  ///
  /// The room refuses to read a passage whose rehearsal was not heard through, and it
  /// names the parts it is missing. The press is not spent on the refusal: the part goes
  /// in the air, the team hears it, and *terminei* lights again at its end.
  ///
  /// At the part's own nought, which is the one place this differs from picking a part
  /// back up. A part already told back whole has its cursor at its end, and started there
  /// it would play silence while the listening ledger — which opens at nought either way —
  /// reported the part heard whole: the same *terminei* would be refused again, with
  /// nothing the team could do about it.
  Future<void> _levarAParteNaoOuvida(String gravacao, int epoch) async {
    if (!state.partes.any((take) => take.takeId == gravacao)) {
      // A recording this tablet is not holding. There is nothing to lead them to and no
      // way to say so without words. Asked before anything is measured: a name that leads
      // nowhere is a person, and measuring the whole rehearsal first only makes them wait
      // for it.
      _haltForAPerson();
      return;
    }
    // Landing forward over a part nobody has measured sits the cord's head short of the
    // sound by the whole of that part. A file the player still answers nothing about is
    // the one gap left once a mend measures what it swaps in, and it is measured here.
    //
    // The row is read again after every wait, and a path that has left it is left alone:
    // a rebuilt passage landing in the middle of this would otherwise have a length
    // written under the file it just replaced.
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
      _tamanhoDaParteMs[arquivo] = medida.inMilliseconds;
    }
    final parte = state.partes.indexWhere((take) => take.takeId == gravacao);
    if (parte < 0) {
      _haltForAPerson();
      return;
    }
    _pousadaNaParteNaoOuvida = true;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btFimDasPartesMs: _fimDaParteMs,
      // This branch returns above the two that clear it, so a team sent to an unheard
      // part mid-mend kept the flag on and the drained band — the only mark of a stretch
      // still waiting — was suppressed under them.
      btConsertando: false,
    );
    _tocarParteDaRetro(parte, doComeco: true);
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
    final trecho = state.trechoChamado(named);
    if (trecho == null ||
        trecho.parte < 0 ||
        trecho.parte >= state.partes.length) {
      // A name this tablet cannot turn into a slice of a recording it is holding. There
      // is nothing to lead them to and no way to say so without words, and every quiet
      // way out of here ends on the exit that empties the rehearsal.
      _haltForAPerson();
      return;
    }
    _parteTocando = trecho.parte;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _traduzindoDeNovo = true;
    _trechoTraduzidoDeNovo = trecho;
    state = state.copyWith(
      btPhase: BtPhase.playing,
      voice: VoiceState.invite,
      btFindings: const [],
      clearFindingSegment: true,
    );
    _leadThemToTheTrecho(trecho);
  }

  /// Take the room's own reading of the stretches, names and all.
  ///
  /// A stretch is born on the server and only the server knows what it is called; the
  /// answer to telling one back carries a count and no name. Without this the pointer on
  /// a finding matched nothing this tablet held, and a team that had told six stretches
  /// back was offered the whole recording every time.
  Future<void> _readTheStretchesBack(String sessionId, int epoch) async {
    final SessionSnapshot snapshot;
    try {
      snapshot = await _room.fetchState(sessionId);
    } on Exception {
      // The verdict is already in hand and already spoken. Failing to re-read the names
      // costs the pointer, not the verdict, so the findings screen still opens — on the
      // whole recording, which is where an unnamed stretch has always landed.
      return;
    }
    if (epoch != _epoch) return;
    final trechos = _trechosFrom(snapshot.backTranslation.segments);
    if (trechos.isEmpty) return;
    state = state.copyWith(btTrechos: trechos);
  }

  /// The room's stretches as this tablet's own, each tied back to the recording it slices.
  ///
  /// [noLugarDe] is the stretch a replacement took the place of and [lugar] where it sat,
  /// on the routes that know. Identity is what ties the room's reading back to what this
  /// tablet holds, and a mend can break it: the mother tongue told again becomes a take
  /// of its own, which is no part of the rehearsal, so nothing about the successor
  /// matches. Its place on the cord has to survive that — it is the same stretch, and the
  /// necklace is where a team who cannot read sees where their correction went.
  ///
  /// [contadoEm] is the file a telling was just recorded into. It belongs to the stretch
  /// that replaced the one it was told over, and to no other.
  List<Trecho> _trechosFrom(
    List<SegmentView> told, {
    int lugar = -1,
    Trecho? noLugarDe,
    String? contadoEm,
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
          // slice alone stopped answering the day the room began rebuilding the
          // recording under a correction: every stretch of that part moves to another
          // file at another time at once, and a stretch nobody touched came back
          // matching nothing and lost the telling this tablet holds for it.
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
          final antes =
              aqui.isNotEmpty ? aqui.first : (onde == lugar ? noLugarDe : null);
          // Where it sits, which is the slice of a part it covers, and has nothing to do
          // with the file it plays. A stretch out of a rehearsal part sits where it
          // plays; a mended one keeps the place of the stretch it replaced — carried
          // from that stretch inside the round that mends it, and read back out of the
          // resume point on a tablet that has no such round behind it.
          //
          // By segment first: a mend gives its stretch a new take every time it is
          // asked for again, so the name that survives from one round to the next is
          // the stretch's own, not what it happened to be called last. The take is
          // still tried, for the older kind of mend that never learned to name a
          // segment at all.
          final naParte = partes.indexWhere((p) => p.takeId == segment.takeId);
          final guardado =
              _lugares[segment.segmentId] ?? _lugares[segment.takeId];
          final parte = naParte >= 0
              ? naParte
              : (antes?.parte ?? guardado?.parte ?? naParte);
          return Trecho(
            segmentId: segment.segmentId,
            takeId: segment.takeId,
            retroPath: !segment.told
                ? null
                : onde == lugar && contadoEm != null
                    ? contadoEm
                    : (aqui.isNotEmpty ? aqui.first.retroPath : null),
            parte: parte,
            from: from,
            to: to,
            lugarFrom: naParte >= 0
                ? from
                : (antes?.lugarFrom ?? guardado?.from ?? from),
            lugarTo:
                naParte >= 0 ? to : (antes?.lugarTo ?? guardado?.to ?? to),
            contado: segment.told,
          );
        }(),
    ];
  }

  /// The passage the room rebuilt, put in the place of the part it was rebuilt from.
  ///
  /// The same scope, because a stretch addresses its part by where it sits in the row and
  /// a part that changed places would take every stretch of the rehearsal with it. What
  /// changes is the file and the name: from here the part *is* the rebuilt passage, and
  /// every play, every cut and every resume reads it without knowing there was ever a
  /// rebuilding.
  ///
  /// The part's own recording is left on the tablet. It is what the correction was made
  /// out of, nothing points at it any more, and deleting audio a team recorded is not a
  /// thing this room does quietly.
  ///
  /// Answers whether the swap happened. It does not when the audio cannot be fetched or
  /// cannot be written, and that is not a failed correction: the correction is already
  /// the team's, on the server and on its own recording, and the room goes on playing the
  /// passage stretch by stretch the way it did before there were rebuilt ones. Nobody in
  /// this room can read, so the log is the only place it can be said at all.
  Future<bool> _aParteViraAComposta(
    String sessionId,
    String composta,
    int epoch, {
    required String noLugarDe,
  }) async {
    if (!state.keptTakes.any((take) => take.takeId == noLugarDe)) return false;
    final String arquivo;
    try {
      arquivo = await _recorder.keepBytes(
        await _room.fetchClip(RoomRepository.takeAudioUrl(sessionId, composta)),
        'composta-$composta',
      );
    } on Exception catch (error) {
      debugPrint(
        'A passagem composta $composta da sessão $sessionId não pôde ser '
        'trazida; a parte continua sendo a gravação do ensaio: $error',
      );
      return false;
    }
    // The rebuilt passage is a file of its own length, and the cord is drawn over the
    // parts as they now are. Measured here rather than left to the next playthrough
    // because a resume launches this and the untold ground unawaited, in either order:
    // whichever lands last, the part must not go on being drawn at the length of the file
    // this one replaces.
    final quanto = await _playback.howLong(arquivo);
    if (epoch != _epoch) return false;
    // Found again on the far side of the wait, by the name and not by where it sat. Three
    // waits is long enough for the rehearsal to have been thrown away and started over
    // under this, and a position read before them addresses a row that may no longer be
    // there — or may now be somebody else's part.
    final parte = state.keptTakes.where((take) => take.takeId == noLugarDe);
    if (parte.isEmpty) return false;
    final escopo = parte.first.scopeId;
    state = state.copyWith(keptTakes: [
      for (final take in state.keptTakes)
        if (take.scopeId == escopo)
          KeptTake(scopeId: escopo, path: arquivo, takeId: composta)
        else
          take,
    ]);
    if (quanto != null) _tamanhoDaParteMs[arquivo] = quanto.inMilliseconds;
    state = state.copyWith(btFimDasPartesMs: _fimDaParteMs);
    return true;
  }

  /// Fetch the rebuilt passages this tablet does not have, on a session picked back up.
  ///
  /// Stretches naming a recording that is not here is what a rebuilding this tablet never
  /// saw the answer to looks like afterwards. Which part such a recording answers for is
  /// the one thing the stretches cannot say, so the room's own list of them is read for
  /// it: a rebuilt passage is kept under the number of the part it was rebuilt from, which
  /// is the number this tablet gave that part when it sent it up.
  Future<void> _alcancarAsCompostas(
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
    // The row of stretches as it stands before any of this waits. Fetching a passage is
    // two round trips, the rehearsal goes on playing under them, and a team that cuts a
    // stretch inside that window has it in this list and nowhere else yet.
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
    for (final guardada in guardadas) {
      if (!faltando.contains(guardada.takeId)) continue;
      if (guardada.scope != KeptScope.composed) continue;
      final numero = guardada.ordinal;
      if (numero == null) continue;
      final parte = state.keptTakes
          .where((take) => take.scopeId == KeptScope.parte(numero));
      final era = parte.isEmpty ? null : parte.first.takeId;
      if (era == null) continue;
      await _aParteViraAComposta(sessionId, guardada.takeId, epoch,
          noLugarDe: era);
      if (epoch != _epoch) return;
    }
    // Rebuilt whether or not any of those downloads landed: a stretch this tablet has no
    // file for yet is still one the room told back, and it keeps the place [_lugares]
    // remembers for it rather than falling out of the necklace until the next download
    // that succeeds.
    //
    // Only over a row nothing else has touched. This reading is built out of the answer
    // the resume came in with, so writing it over a row that moved meanwhile would take
    // the stretch the team just told back off the screen — it is on the server, and this
    // list is the only place the room draws it from.
    if (!identical(state.btTrechos, eram)) return;
    // Read again over the parts as they now are: what was a stretch of no part of this
    // rehearsal is a stretch of one, and its place is the ground it covers there.
    state = state.copyWith(btTrechos: _trechosFrom(segments));
    _rememberWhereTheyAre(state.stage);
  }

  void _leadThemToTheTrecho(Trecho trecho) {
    if (_ondeTocar(trecho) == null) return;
    state = state.copyWith(btTrechoTocando: true);
    _tocarOTrecho(trecho);
  }

  /// Which take answers for a stretch's audio: the one its own id names, never the one
  /// sitting at its place in the rehearsal. A correction moves the file without moving
  /// the place — [Trecho.parte] stays the cord's address, and has nothing to do with
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
  /// case, true of every stretch nobody has corrected, and of a corrected one whose own
  /// take or composed passage has already reached this tablet. Otherwise the place
  /// [_lugares] kept for its segment, for a mend or a composed passage that has not
  /// reached `keptTakes` yet: the mother tongue recorded for the stretch that was
  /// corrected, the part's own audio still under it for a neighbour that only moved on
  /// paper.
  ///
  /// Last, the part [trecho] sits in, at the place ([Trecho.lugarFrom]..[Trecho.lugarTo])
  /// rather than the file's own slice — the part's audio has not moved for a stretch this
  /// tablet has never been told a fallback for, so its own place in the rehearsal is the
  /// best guess left. Null only for a stretch belonging to no part at all: that would be
  /// some other stretch's recording, not this one's, and playing it is worse than the
  /// silence a skip is.
  (String, Duration, Duration)? _ondeTocar(Trecho trecho) {
    final path = _pathForTrecho(trecho);
    if (path != null) return (path, trecho.from, trecho.to);
    final lugar = (trecho.segmentId != null ? _lugares[trecho.segmentId] : null) ??
        _lugares[trecho.takeId];
    final fallbackPath = lugar?.fallbackPath;
    if (fallbackPath != null) {
      return (
        fallbackPath,
        lugar!.fallbackFrom ?? Duration.zero,
        lugar.fallbackTo ?? Duration.zero,
      );
    }
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
  void _tocarOTrecho(Trecho trecho) {
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

    _onPlaybackComplete = quiet;
    _onPlaybackFailed = quiet;
    _clipHeld = false;
    _listenForTheEnd();
    unawaited(_playback.playRange(onde.$1, onde.$2, onde.$3));
    _watchPlayback(clipStillOpening: true);
  }

  /// Hear the team's own voice on the stretch the analyst pointed at.
  ///
  /// Free, and it decides nothing: the room used to read the kind of finding and pick the
  /// correction itself, so the team never compared the two voices before the choice was
  /// already made for them.
  void ouvirVozMaterna() {
    if (state.btPhase != BtPhase.findings) return;
    if (state.btTrechoTocando) {
      _holdClip();
      state = state.copyWith(btTrechoTocando: false, btTrechoPausada: true);
      return;
    }
    if (state.btRetroTocando) return;
    if (state.btTrechoPausada) {
      state = state.copyWith(btTrechoTocando: true, btTrechoPausada: false);
      _letTheClipRun();
      return;
    }
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    _leadThemToTheTrecho(trecho);
  }

  /// Hear the telling in Portuguese — the voice that travels to the analyst.
  void ouvirTraducaoEmPortugues() {
    if (state.btPhase != BtPhase.findings) return;
    if (state.btRetroTocando) {
      _holdClip();
      state = state.copyWith(btRetroTocando: false, btRetroPausada: true);
      return;
    }
    if (state.btTrechoTocando) return;
    final path = state.btFindingTrecho?.retroPath;
    if (path == null) return;
    if (state.btRetroPausada) {
      state = state.copyWith(btRetroTocando: true, btRetroPausada: false);
      _letTheClipRun();
      return;
    }
    void quiet() {
      unawaited(_playback.stop());
      state = state.copyWith(btRetroTocando: false, btRetroPausada: false);
    }

    state = state.copyWith(btRetroTocando: true);
    _play(path, onComplete: quiet, onFailed: quiet);
  }

  /// The error was born in the recording: the mother tongue is re-recorded first, and the
  /// telling of this stretch is redone over it afterwards. Always in that order — the
  /// server refuses a new recording that arrives carrying an explanation.
  void regravarAVozMaterna() {
    if (state.btPhase != BtPhase.findings) return;
    if (state.btFindingTrecho == null) return;
    _holdClip();
    // The mend starts at the choosing, before any microphone opens and before anything is
    // sent: the band stands for "this is the one waiting", and it stopped waiting here.
    state = state.copyWith(
      btPhase: BtPhase.gravandoMaterna,
      voice: VoiceState.invite,
      btTrechoTocando: false,
      btRetroTocando: false,
      btConsertando: true,
    );
  }

  /// The team's own voice stands and only the telling slipped: the explanation is redone
  /// over a recording that does not move.
  void traduzirDeNovoEmPortugues() {
    final trecho = state.btFindingTrecho;
    if (state.btPhase != BtPhase.findings || trecho == null) return;
    state = state.copyWith(btTrechoTocando: false, btRetroTocando: false);
    unawaited(traduzirDeNovo(trecho));
  }

  /// The far station: the mother tongue of one stretch, recorded again.
  ///
  /// Tap to start, tap to stop — the room's own gesture, not the design's press-and-hold.
  Future<void> _gravarAVozMaterna() async {
    // Which tap this is comes from whether the room is listening, not from a flag of its
    // own. A flag survives a capture that never started — a refused microphone, a recorder
    // that would not open — and the next tap then stopped a recording that did not exist,
    // dropping the team back on the question with the step still to do. The phase is the
    // same on both sides of this gesture, so the voice is what tells them apart, and it is
    // already what the circle reads to decide what it says.
    if (state.voice == VoiceState.listening) {
      await _guardarAVozMaterna();
      return;
    }
    // The stamp travels with the recording into its scope: the same stretch can be
    // re-recorded twice — a replacement that fails leaves the team tapping again — and a
    // scope that repeats would hand back the first take's name for the second file.
    _marcaDaMaterna = _stamp();
    // The room may still be asking them to say it again; a microphone opened over that
    // would keep the tablet's own line inside the new voice.
    unawaited(_voice.stop());
    // Taken on again, because a microphone that refused took it back: the team lands on
    // the same question and taps to record a second time, and the band has to follow them
    // rather than stay empty over a recording that is now running.
    state = state.copyWith(voice: VoiceState.listening, btConsertando: true);
    await _recordOrBlock('materna_$_marcaDaMaterna');
  }

  /// What the new recording costs, paid in the order the room insists on.
  ///
  /// The file becomes a rehearsal take of this session, because a stretch is a slice of
  /// one and the room checks that. Its slice runs from nought to its own length — which is
  /// why this could not be built until the room could measure an audio without playing it.
  /// It goes up with no explanation attached: the one that belonged to the audio it
  /// replaces does not carry over, and sending both is the combination the room refuses.
  ///
  /// And the second station follows immediately. Correcting only the mother tongue is not
  /// a state this product has: a stretch left with a new recording and no telling is a
  /// stretch the first round's gate will hold the whole passage for.
  Future<void> _guardarAVozMaterna() async {
    final epoch = _epoch;
    state = state.copyWith(btPhase: BtPhase.thinking, voice: VoiceState.thinking);
    _watchBusyState();
    final path = await _recorder.stop();
    final sessionId = state.sessionId;
    final alvo = state.btFindingTrecho;
    if (epoch != _epoch) return;
    if (path != null && !_hasAudio(path)) {
      _voltarAPergunta();
      _haltForAPerson();
      return;
    }

    if (path == null || sessionId == null || alvo?.segmentId == null) {
      _voltarAPergunta();
      return;
    }

    final escopo = KeptScope.trecho(alvo!.segmentId!, _marcaDaMaterna);
    final onde = state.btTrechos.indexWhere(
      (trecho) => trecho.segmentId == alvo.segmentId,
    );
    final gravacao = await _guard(path, kind: 'ensaio', scope: escopo);
    if (epoch != _epoch) return;
    final quanto = await _playback.howLong(path);
    if (epoch != _epoch) return;
    if (gravacao == null || quanto == null || quanto <= Duration.zero) {
      // Either the room has not taken the recording yet or it cannot be measured. Their
      // voice is kept and the ladder runs; three of these and the room stops for a person.
      await _oConsertoNaoPegou(const RoomBroke('a voz nova não pôde ser guardada'));
      return;
    }

    final TellingAgain trocado;
    try {
      trocado = await _room.replaceSegment(
        sessionId,
        alvo.segmentId!,
        null,
        takeId: gravacao,
        from: Duration.zero,
        to: quanto,
      );
      if (epoch != _epoch) return;
    } on Exception catch (error) {
      if (epoch != _epoch) return;
      await _oConsertoNaoPegou(error);
      return;
    }

    // A version is a new row and carries a new name, so the pointer the finding came with
    // now names a stretch the room has retired. What stays put is the position: a
    // replacement takes the place of the one it replaces, and that is how the successor is
    // found and the pointer moved onto it. Following the old name would land the team back
    // on the question with the recording already replaced.
    // The place carries more than the pointer. The new recording is a take of this
    // stretch and no part of the rehearsal, so the cord cannot situate the successor by
    // its name and used to drop it: a team came out of the far station with the band they
    // were mending gone off the necklace altogether.
    // Kept by the take the mend recorded, which is the only name the successor and this
    // tablet will still agree on after the app is closed: the stretch's own is minted
    // fresh by every mend, and the place is what the team sees on the necklace.
    _lugares[gravacao] = LugarDoTrecho(
      takeId: gravacao,
      parte: alvo.parte,
      from: alvo.lugarFrom,
      to: alvo.lugarTo,
      fallbackPath: path,
      fallbackFrom: Duration.zero,
      fallbackTo: quanto,
    );
    // Every stretch of the part this mend is about to rebuild, kept by its own segment
    // rather than the take: the take a composed passage answers to is a name the server
    // can give and take away across as many failed downloads as it likes, but the
    // segment is the one identity that survives all of them. Written before the fetch
    // below is even tried, because a place remembered only on success is no place at all
    // on the download that fails.
    //
    // The stretch being mended falls back to the mother tongue it was just recorded
    // into, played whole — the take of its own the room would have played had nothing
    // been composed. Its neighbours fall back to the part's own file, at the place they
    // already played: the audio has not moved for them, only its name is about to, and
    // that file is never overwritten under a failed download the way the part's `KeptTake`
    // is left pointing nowhere once the swap succeeds.
    for (final vizinho in state.btTrechos) {
      if (vizinho.parte != alvo.parte || vizinho.segmentId == null) continue;
      if (vizinho.parte < 0 || vizinho.parte >= state.partes.length) continue;
      final ehAlvo = vizinho.segmentId == alvo.segmentId;
      _lugares[vizinho.segmentId!] = LugarDoTrecho(
        takeId: ehAlvo ? gravacao : vizinho.takeId,
        segmentId: vizinho.segmentId,
        parte: vizinho.parte,
        from: vizinho.lugarFrom,
        to: vizinho.lugarTo,
        fallbackPath: ehAlvo ? path : state.partes[vizinho.parte].path,
        fallbackFrom: ehAlvo ? Duration.zero : vizinho.from,
        fallbackTo: ehAlvo ? quanto : vizinho.to,
      );
    }
    // Before the stretches are rebuilt, not after: a stretch sitting in a part of the
    // rehearsal is read off that part, and a swap that came later would have every stretch
    // of this one already reading as a slice of no part at all.
    final composta = trocado.composedTakeId;
    if (composta != null) {
      await _aParteViraAComposta(sessionId, composta, epoch,
          noLugarDe: alvo.takeId);
      if (epoch != _epoch) return;
    }
    final trechos = _trechosFrom(
      trocado.segments,
      lugar: onde,
      noLugarDe: alvo,
    );
    final agora = onde >= 0 && onde < trechos.length ? trechos[onde] : null;
    if (agora?.segmentId == null) {
      _voltarAPergunta();
      return;
    }
    // The mended stretch itself is renamed by this very replace — the second station
    // renames it again, and its own migration is not reached when the room halts before
    // the second station ever runs. Done here too, so the entry above survives under a
    // name a resume can actually find, whichever station this correction stops at.
    if (agora!.segmentId != alvo.segmentId) {
      final antigo = _lugares[alvo.segmentId] ?? _lugares[alvo.takeId];
      if (antigo != null) {
        _lugares[agora.segmentId!] = LugarDoTrecho(
          takeId: agora.takeId,
          segmentId: agora.segmentId,
          parte: agora.parte,
          from: agora.lugarFrom,
          to: agora.lugarTo,
          fallbackPath: antigo.fallbackPath,
          fallbackFrom: antigo.fallbackFrom,
          fallbackTo: antigo.fallbackTo,
        );
      }
    }
    state = state.copyWith(
      btPhase: BtPhase.findings,
      btTrechos: trechos,
      btFindingSegmentId: agora.segmentId,
      // The corrected voice is its own take, kept beside the rehearsal's — never added
      // before this, which is why the trecho it corrects had no file of its own to be
      // found by and fell back to the part it used to share a place with.
      keptTakes: [
        ...state.keptTakes,
        KeptTake(scopeId: escopo, path: path, takeId: gravacao),
      ],
    );
    _rememberWhereTheyAre(SalaStage.retro);
    // Correcting the mother tongue is two steps over the same route, and the room can give
    // out on either. Read only on the second, the news would arrive after this step had
    // already opened the microphone for a telling the room would not take.
    if (trocado.needsPerson) {
      _haltForAPerson();
      return;
    }
    await traduzirDeNovo(agora);
  }

  /// Back to the question, from a step that cannot finish its work yet.
  ///
  /// Choosing which voice must speak again lands on a recording step whose call to the
  /// room does not exist yet. Until it does, a team that chose could neither record nor
  /// go back: the only way out was abandoning the whole passage.
  void _voltarAPergunta() {
    state = state.copyWith(
      btPhase: BtPhase.findings,
      voice: VoiceState.invite,
      btConsertando: false,
    );
  }

  /// A new mother-tongue recording the room did not take: back to the question, said.
  ///
  /// The band drains, because the promise it made was withdrawn — and the team is told so
  /// with the line an inaudible turn gets, standing on the question they left, where the
  /// way to try again is on screen. The failure still runs its ladder underneath, and the
  /// ladder now lands on the question too: a refusal, a lost session or a third failure
  /// in this passage stop for a person, a lost network goes offline, and the room has
  /// spoken for each of those already, so nothing is said on top.
  Future<void> _oConsertoNaoPegou(Object error) async {
    _voltarAPergunta();
    _handleRoomFailure(error);
    if (state.needsPerson || state.offline) return;
    final epoch = _epoch;
    state = state.copyWith(voice: VoiceState.speaking, peerCue: false);
    _watchBusyState();
    final line = rotated(inaudibleLines, _inaudibleSpoken++);
    await _voice.playAsset(fixedLineAsset(line, _lingua));
    if (epoch != _epoch) return;
    state = state.copyWith(voice: VoiceState.invite);
  }

  void retellChunk() {
    if (state.btPhase != BtPhase.findings) return;
    final trecho = state.btFindingTrecho;
    if (trecho == null) return;
    _parteTocando = trecho.parte;
    _trechoStart = trecho.from;
    _trechoEnd = trecho.to;
    _traduzindoDeNovo = true;
    state = state.copyWith(btPhase: BtPhase.playing, voice: VoiceState.invite);
    _leadThemToTheTrecho(trecho);
  }

  /// Back to the rehearsal with everything kept, to record what the story still lacks.
  ///
  /// A finding of something missing that the analyst could not place in any stretch is a
  /// passage whose stretches are right and whose end was never recorded. The way back
  /// used to be [reRecordClip], which asks the room to retire the clip and empties the
  /// rehearsal on this side: a team that had told three stretches back and got every one
  /// right went back to nothing, in the app and in the session. Nothing is asked of the
  /// room here, because the stretches are still the session's, and the takes stay, so
  /// the team records more and the next telling-back starts where the told ground ends.
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
      _haltForAPerson();
      return;
    }
    _voltarAoEnsaio();
    _parteARegravar = parte;
  }

  void _voltarAoEnsaio() {
    _clearAll();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      btPhase: BtPhase.playing,
      btFindings: const [],
      clearFindingSegment: true,
      peerCue: false,
    );
    // A retelling left switched on by a chunk that never landed would make the first
    // stretch of the next telling-back upload as a correction of one that does not exist.
    _traduzindoDeNovo = false;
    _trechoTraduzidoDeNovo = null;
    _rememberWhereTheyAre(SalaStage.ensaio);
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
    _tamanhoDaParteMs.clear();
    _pousadaNaParteNaoOuvida = false;
    _escuta.esquecerTudo();
    state = state.copyWith(
      stage: SalaStage.ensaio,
      voice: VoiceState.invite,
      ensaio: EnsaioStatus.idle,
      takes: 0,
      keptTakes: const [],
      ensaioPass: state.ensaioPass + 1,
      btPhase: BtPhase.playing,
      // The room retired these with the clip. Left standing, the next telling-back would
      // read them as ground already told and step over recordings nobody has heard.
      btTrechos: const [],
      btChunkPasses: const [],
      btChunkFailures: const [],
      btClipEnded: false,
      btParteFronteira: false,
      btFindings: const [],
      btPass: 1,
    );
    _traduzindoDeNovo = false;
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
    final BackTranslationRestart restarted;
    try {
      restarted = await _room.restartBackTranslation(sessionId);
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
    state = state.copyWith(
      btPhase: BtPhase.findings,
      warning: restarted.needsPerson ? true : null,
    );
    return true;
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
  /// for a person on its first failure, and `_traduzindoDeNovo` — set when the team
  /// asks to tell a stretch again and cleared only by a chunk that lands — made the very
  /// first stretch of the next back translation upload as a correction of a stretch that
  /// does not exist.
  void _forgetThePassage() {
    _unplayableTurns = 0;
    _roomFailures = 0;
    _slowAnswers = 0;
    _retryStep = 0;
    _noticeSpoken = false;
    _strandedSpoken = false;
    _personAsked = false;
    _personAskStep = 0;
    _haltWatched = null;
    _traduzindoDeNovo = false;
    _trechoTraduzidoDeNovo = null;
    _inboxSilences = 0;
    _degradedTurns = 0;
    _trechoStart = Duration.zero;
    _trechoEnd = Duration.zero;
    _parteTocando = 0;
    _parteARegravar = null;
    _tamanhoDaParteMs.clear();
    _pousadaNaParteNaoOuvida = false;
    _aprovando = false;
    _aprovada = false;
    _escuta.esquecerTudo();
    _desdeMs = 0;
    _ghostParte = 0;
    _pendingTakePath = null;
    _emCurso = null;
  }
}

final salaSessionProvider =
    NotifierProvider<SalaSessionNotifier, SalaSessionState>(
  SalaSessionNotifier.new,
);
