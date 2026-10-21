// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:internalization_room/features/sala/data/connectivity_service.dart';
import 'package:internalization_room/features/sala/data/current_session_ledger.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/data/credential_vault.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/playback_repository.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/screen_awake.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/data/look_ledger.dart';
import 'package:internalization_room/features/sala/data/room_language_ledger.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/pausa.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

/// Throwing here instead of returning keeps the failure at the wait: a deadline that
/// passes in silence surfaces as an unrelated error several lines later.
Future<void> waitFor(
  String what,
  FutureOr<bool> Function() ready, {
  Duration limit = const Duration(seconds: 10),
  Future<void> Function()? step,
}) async {
  const stepLength = Duration(milliseconds: 100);
  final deadline = DateTime.now().add(limit);
  var stepped = Duration.zero;
  while (!await ready()) {
    if (step == null ? DateTime.now().isAfter(deadline) : stepped >= limit) {
      final waited = limit.inMilliseconds % 1000 == 0
          ? '${limit.inSeconds}s'
          : '${limit.inMilliseconds}ms';
      throw TimeoutException('esperei $waited e $what não aconteceu', limit);
    }
    if (step == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    } else {
      await step();
      stepped += stepLength;
    }
  }
}

/// Ends the room before the binding looks for a timer still in the air.
///
/// A room stopped for a person keeps asking the server whether the halt is still
/// standing, on a cadence that ends only with the halt or with the room. A widget test
/// that leaves the team on a halt therefore always has one timer pending, and the
/// `addTearDown` that disposes the container runs after the check that would see it.
///
/// A warning is watched the same way, so a correction answered with `replaceNeedsPerson`
/// leaves that timer too: this double keeps saying the warning until [theDeskAttended] is
/// called, and until then the watch re-arms itself on every beat.
void closeTheRoom(ProviderContainer container) => container.dispose();

const totalBeads = 12;

const testLanguage = 'pt';

/// The line this room composes for a *terminei* it answered.
const falaDoVeredito = '/api/internalization-room/voice/veredito';

/// The line this room composes for a *terminei* it refused, because a part of the
/// rehearsal is not covered by the report. Its own line, as the refusal is its own answer.
const falaDaParteNaoOuvida = '/api/internalization-room/voice/parte-nao-ouvida';

/// The line this room composes for a *terminei* it refused, because a current part has no
/// stretch told over it. Its own line, as the refusal is its own answer.
const falaDaParteNaoContada =
    '/api/internalization-room/voice/parte-nao-contada';

Coverage coverage({int engaged = 0, int surfaced = 0}) => Coverage(
  engaged: engaged,
  surfaced: surfaced,
  total: totalBeads,
  beadsFilled: engaged,
  beadsTold: true,
);

class FakeVoice implements FacilitatorVoiceService {
  /// The room's one ordered log of sound, shared with the other doubles so a test can
  /// read what happened before what without either double reading the other.
  final List<String> sounds;

  FakeVoice({List<String>? sounds}) : sounds = sounds ?? [];

  final List<String> played = [];
  final List<String> assets = [];
  final List<(String, String)> fixedLines = [];
  final List<(String, String)> readied = [];
  final List<String> fetched = [];

  /// Whether a line is said whole. A stopped line is never whole, as the real service
  /// answers false for a sound cut short (`_sayItWhole`).
  bool succeeds = true;

  /// Lines this voice refuses to say, by url, by asset path or by a fixed line's name.
  final Set<String> refuses = {};

  /// What the next `play()` throws, when the room — not the player — is why the line
  /// does not sound. Distinct from [refuses]: that is the player failing with the file
  /// already in hand.
  RoomFailure? roomFailsWith;
  Completer<bool>? _holding;
  Completer<bool>? _saying;

  /// Where the line being said is, and how long it is when the player knows.
  @override
  Duration linePosition = Duration.zero;

  @override
  Duration? lineLength;

  void holdNextLine() => _holding = Completer<bool>();

  void finishHeldLine() {
    _holding?.complete(succeeds);
    _holding = null;
  }

  void failHeldLine(RoomFailure failure) {
    _holding?.completeError(failure);
    _holding = null;
  }

  Future<bool> _answer() {
    final held = _holding;
    if (held == null) return Future.value(succeeds);
    _saying = held;
    return held.future;
  }

  /// Called the instant a line starts, so a test can read what else was sounding then —
  /// which is the whole of what "the Guide never speaks over the rehearsal" means.
  void Function()? aoFalar;

  @override
  Future<bool> play(String url, {void Function()? onSoundStart}) {
    played.add(url);
    final failure = roomFailsWith;
    if (failure != null) return Future.error(failure);
    sounds.add('voice:line');
    aoFalar?.call();
    onSoundStart?.call();
    if (refuses.contains(url)) return Future.value(false);
    return _answer();
  }

  @override
  Future<File> clipFor(String url) async => File(url);

  /// Lines this tablet does not have yet, by url.
  final Set<String> missing = {};

  @override
  Future<bool> holds(String url) async =>
      url.isNotEmpty && !missing.contains(url);

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
  Future<bool> ready(String url) => fetch(url);

  @override
  Future<bool> readyFixedLine(String line, String language) async {
    readied.add((line, language));
    await _fetching?.future;
    return succeeds;
  }

  @override
  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    assets.add(assetPath);
    sounds.add('voice:asset');
    aoFalar?.call();
    onSoundStart?.call();
    if (refuses.contains(assetPath)) return Future.value(false);
    return _answer();
  }

  @override
  Future<bool> playFixedLine(
    String line,
    String language, {
    void Function()? onSoundStart,
  }) {
    fixedLines.add((line, language));
    sounds.add('voice:fixed');
    aoFalar?.call();
    onSoundStart?.call();
    if (refuses.contains(line)) return Future.value(false);
    return _answer();
  }

  /// How many times the room told this voice to stop, whatever it was saying.
  int stops = 0;

  /// Called the instant the room tells the voice to stop, so a test can read where the
  /// room stood then.
  void Function()? onStop;

  /// Whether a stopped line still reports itself whole, later, as a platform can when the
  /// stop lands on the clip's last frame.
  bool reportsAStoppedLineWhole = false;

  final List<Completer<bool>> _stoppedButNotYetAnswered = [];

  void theStoppedLineReportsWhole() {
    for (final stopped in _stoppedButNotYetAnswered) {
      stopped.complete(true);
    }
    _stoppedButNotYetAnswered.clear();
  }

  @override
  Future<void> stop() async {
    stops++;
    onStop?.call();
    sounds.add('voice:stop');
    final saying = _saying;
    _saying = null;
    if (saying == null || saying.isCompleted) return;
    if (reportsAStoppedLineWhole) {
      _stoppedButNotYetAnswered.add(saying);
    } else {
      saying.complete(false);
    }
    if (identical(saying, _holding)) _holding = null;
  }

  @override
  Future<void> dispose() async {}
}

class FakeRecorder implements RecordingRepository {
  /// The same ordered log the players write to: the microphone opening on a silent room
  /// is an order between two doubles, not a pair of counters.
  final List<String> sounds;

  FakeRecorder({List<String>? sounds}) : sounds = sounds ?? [];

  final StreamController<bool> _interruptions =
      StreamController<bool>.broadcast();
  final Directory home = Directory.systemTemp.createTempSync('sala-gravacoes');
  int captures = 0;
  bool returnsNothing = false;
  bool returnsEmpty = false;
  final List<String> deleted = [];
  String? lastPath;
  MicOwner? lastOwner;
  Uint8List? rehearsalSpeaks;
  String? rehearsalSpeaksAs;

  bool permitted = true;

  bool? answersPermission = true;
  bool startThrows = false;

  /// Whether closing the microphone fails, the way a recorder that lost its file does.
  bool stopThrows = false;

  @override
  Future<bool?> hasPermission() async => permitted ? answersPermission : false;

  final List<Completer<void>> _holdingStarts = [];
  int _startsTaken = 0;

  /// Hold a start, the way a platform answering a minute late does. Held per call, so a
  /// start left in the air by the passage before and one of the passage now are let go
  /// one at a time — a single hold shared by both cannot tell them apart.
  void holdNextStart() => _holdingStarts.add(Completer<void>());

  void finishStart() {
    for (final held in _holdingStarts) {
      if (held.isCompleted) continue;
      held.complete();
      return;
    }
  }

  /// Whether the microphone is genuinely open right now. `stop()` and `discard()`
  /// otherwise answer the same whether or not anything was ever recording, which is
  /// fine for the tests that already drive a real start — but `_clearAll` calls
  /// `discard()` on every passage transition, recording or not, and a discard that
  /// invents a file for a microphone that was never open would delete a piece no
  /// gesture ever made.
  bool _recording = false;

  @override
  Future<Capture> start(
    String fileName, {
    MicOwner owner = MicOwner.conversation,
  }) async {
    lastOwner = owner;
    sounds.add('recorder:start');
    final held = _startsTaken < _holdingStarts.length
        ? _holdingStarts[_startsTaken++]
        : null;
    if (held != null) await held.future;
    captures++;
    if (!permitted) return Capture.denied;
    if (startThrows) return Capture.failed;
    _recording = true;
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
    _recording = false;
    if (stopThrows) {
      throw const FileSystemException('o gravador perdeu o arquivo');
    }
    if (returnsNothing) return null;
    final deliverable =
        lastOwner == MicOwner.rehearsal ||
        lastOwner == MicOwner.scene ||
        lastOwner == MicOwner.frase;
    final fala = rehearsalSpeaks;
    if (fala != null && deliverable) {
      final take = File(
        '${home.path}/captura-$captures.'
        '${rehearsalSpeaksAs ?? (_isWav(fala) ? 'wav' : 'm4a')}',
      )..writeAsBytesSync(fala);
      return lastPath = take.path;
    }
    final file = File('${home.path}/captura-$captures.m4a')
      ..writeAsStringSync(
        returnsEmpty
            ? ''
            : lastOwner == MicOwner.frase
            ? '$_aWholeTake$captures'
            : deliverable
            ? _aWholeTake
            : 'a equipe falou',
      );
    return lastPath = file.path;
  }

  static final _aWholeTake = 'a equipe falou a passagem inteira. ' * 32;

  File aFile(String name) =>
      File('${home.path}/$name.m4a')
        ..writeAsStringSync('a equipe contou a passagem');

  @override
  Future<void> discard() async {
    sounds.add('recorder:discard');
    if (!_recording) return;
    final path = await stop();
    if (path != null) deleted.add(path);
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);

  int sweeps = 0;

  @override
  Future<void> forgetTheKeptRetellings(String sessionId) async {
    for (final entry in home.listSync()) {
      if (entry is File &&
          entry.uri.pathSegments.last.startsWith('kept-$sessionId-')) {
        entry.deleteSync();
      }
    }
  }

  @override
  Future<void> sweepTheFrasesLeftBehind() async => sweeps++;

  /// Whether keeping fetched audio fails, the way a dead disk does.
  bool keepBytesFails = false;

  @override
  Future<String> keepBytes(Uint8List bytes, String fileName) async {
    if (keepBytesFails) throw const FileSystemException('o disco morreu');
    final file = File('${home.path}/$fileName.${_isWav(bytes) ? 'wav' : 'm4a'}')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  /// Whether looking for audio already on the tablet fails, the way a disk does.
  bool heldAsFails = false;

  @override
  Future<String?> heldAs(String fileName) async {
    if (heldAsFails) throw const FileSystemException('o disco falhou');
    for (final extension in ['wav', 'm4a']) {
      final file = File('${home.path}/$fileName.$extension');
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
    }
    return null;
  }

  @override
  Future<String> keepAs(String path, String fileName) async =>
      File(path).renameSync('${home.path}/$fileName${p.extension(path)}').path;

  @override
  Future<void> dispose() async => _interruptions.close();
}

bool _isWav(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
    String.fromCharCodes(bytes, 8, 12) == 'WAVE';

class FakePlayback implements PlaybackRepository {
  final List<String> sounds;

  FakePlayback({List<String>? sounds}) : sounds = sounds ?? [];

  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final StreamController<void> _failures = StreamController<void>.broadcast();
  final StreamController<void> _openings = StreamController<void>.broadcast();
  final List<String> played = [];

  /// Where each clip was asked to start, beside the file it was. A part is put in the air
  /// at a position, and which position is the whole of what some gestures differ by.
  final List<Duration> playedFrom = [];
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

  /// The window an open actually took, so it can be released after the open has taken
  /// it out of [_opening].
  Completer<void>? _segurada;

  /// Which open is the current one, the way the repository counts them: an open a later
  /// one superseded announces nothing and sounds nothing.
  int _opens = 0;

  /// Whether the last gesture asks for sound. A pause or a stop holds the player, a
  /// play, a playRange or a resume wants it.
  bool _wanted = false;
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
  ///
  /// One open, not the player: a second clip asked for while this one is still loading
  /// waits for this load to settle, as the repository makes it (ADR 0041), and then this
  /// one returns without announcing itself and the second opens.
  ///
  /// One window at a time: [finishHeldOpening] releases the one an open took, or the one
  /// still armed, so a second hold armed before the first open has landed is orphaned.
  void holdNextOpening() => _opening = Completer<void>();

  void finishHeldOpening() {
    final segurada = _segurada ?? _opening;
    _segurada = null;
    _opening = null;
    if (segurada != null && !segurada.isCompleted) segurada.complete();
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

  /// The files this player cannot measure, however long they are. A real one answers
  /// nothing for a file it has not finished writing, and the room has a branch for it.
  final Set<String> semMedida = {};

  @override
  Future<Duration?> howLong(String path) async {
    measurements.add(path);
    await _measuring?.future;
    if (semMedida.contains(path)) return null;
    return lengths[path] ?? measured;
  }

  /// Whether a clip is open, which is what [playingLength] answers for. [length] is how
  /// long the file is — the test's fixture — and it survives a stop the way a file does.
  bool _aberto = false;

  /// Whether the source of the current open is still loading.
  bool _abrindo = false;

  /// Where the clip in the air was opened at: what a real player's `position` falls back
  /// to once it is stopped.
  Duration _abertaEm = Duration.zero;

  @override
  Duration? get playingLength => _aberto ? length : null;

  bool get open => _aberto && !_abrindo;

  @override
  Duration get position => at;

  @override
  Future<void> play(String path, {Duration from = Duration.zero}) {
    played.add(path);
    playedFrom.add(from);
    sounds.add('playback:play');
    return _soundUntilItStops(from);
  }

  @override
  Future<void> playRange(String path, Duration from, Duration to) {
    played.add(path);
    ranges.add('${from.inMilliseconds}-${to.inMilliseconds}');
    sounds.add('playback:play');
    // At nought, not at [from]: a clip answers its position counted from its own start,
    // which is the very reason the resumed telling-back is not built on one.
    return _soundUntilItStops(Duration.zero);
  }

  @override
  Future<void> pause() async {
    paused = true;
    _wanted = false;
    sounds.add('playback:pause');
    _stopSounding();
  }

  @override
  Future<void> resume() async {
    paused = false;
    _wanted = true;
    // The clip whose source is still loading sounds when the load comes back, not now:
    // the resume undoes the hold, and the open behind it is what makes the sound.
    if (_abrindo) return;
    // Nothing was ever opened, so there is nothing to bring back.
    if (_opens == 0) return;
    if (stops != _paradasDaAbertura) return;
    // Sound coming back out, not a new clip: the future `play` handed out is long since
    // completed by the pause, so it cannot be what says whether anything is sounding.
    _sounding = true;
    _startWalking();
  }

  /// How many times the room told this player to stop, whatever it was playing.
  int stops = 0;
  int _paradasDaAbertura = 0;

  @override
  Future<void> stop() async {
    stops++;
    _wanted = false;
    sounds.add('playback:stop');
    // As the real one does, and where it differs from a pause. just_audio's `pause()`
    // writes the position down before it stops playing; `stop()` does not, and
    // `position` only extrapolates while the player is playing — so after a stop it
    // answers with the stale place the clip was opened at. A double that kept answering
    // the true playhead hid every read taken after a stop.
    at = _abertaEm;
    // As the real one does. `_openedLength` is cleared with the playback it described —
    // the safety ceiling for the next clip was computed from the length of the last —
    // and a pause is deliberately not a stop here: it keeps the clip open. A double that
    // went on answering for a clip it had stopped hid every transition that stops a part
    // the room means to come back to.
    _aberto = false;
    _stopSounding();
  }

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
    _wanted = true;
    final geracao = ++_opens;
    final paradas = stops;
    _paradasDaAbertura = paradas;
    // A clip is not open the instant it is asked for: the source loads first, and only
    // then does the player know where it starts and how long it is.
    final anterior = _segurada;
    final held = _opening;
    _opening = null;
    if (held != null) _segurada = held;
    _abrindo = true;
    scheduleMicrotask(() async {
      if (anterior != null) await anterior.future;
      await held?.future;
      // A later clip of ours took this one's place while it was still loading. What the
      // clip owed the room dies with the clip: it announces nothing, so no ceiling and
      // no measure hang off a clip that never played, and it is no failure either.
      if (geracao != _opens) return;
      _abrindo = false;
      at = _abertaEm = from;
      _aberto = paradas == stops;
      // Announced either way, held or stopped: the listening ceiling and the measure of
      // the part in the air both hang off this, and a clip that never announces itself
      // strands them.
      _openings.add(null);
      // A hold caught the clip while it was opening: announced, not sounding. A pause
      // leaves the clip open and the ceiling counts what is left of it; a stop cleared
      // the measure on the way past, so this load may not write it back, and a resume
      // does not undo it — the clip the room stopped is not the clip it comes back to.
      if (!_wanted || paradas != stops) return;
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

/// The header the shared key travelled in, named here and nowhere else under `test/`.
const theRoomKeyHeader = 'X-Room-Key';

const turnoUrl = '/api/internalization-room/voice/turno';
const deNovoUrl = '/api/internalization-room/voice/de-novo';

class FakeCurrentSessionLedger implements CurrentSessionLedger {
  CurrentSession? held;

  @override
  Future<CurrentSession?> read() async => held;

  @override
  Future<void> hold(CurrentSession session) async => held = session;

  @override
  Future<void> letGo({String? only}) async {
    if (only == null || held?.sessionId == only) held = null;
  }
}

class FakeRoomLanguageLedger implements RoomLanguageLedger {
  @override
  String? chosen;

  FakeRoomLanguageLedger({this.chosen});

  @override
  Future<void> choose(String language) async => chosen = language;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLookLedger implements LookLedger {
  @override
  String? chosen;

  FakeLookLedger({this.chosen});

  @override
  Future<void> choose(String look) async => chosen = look;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWorkInProgress implements WorkInProgress {
  final Map<String, ResumePoint> rows = {};

  /// Every row this ledger was ever asked to write, in order. A row that is right when
  /// the dust settles can still have been wrong in between, and the one in between is
  /// what the next opening would have read.
  final List<ResumePoint> written = [];

  @override
  Future<Set<String>> startedIn(String book, String language) async => {
    for (final MapEntry(:key, :value) in rows.entries)
      if (key.startsWith('$book/') &&
          (key.endsWith('/$language') || value.language == language))
        key.split('/')[1],
  };

  Completer<void>? _holdingRead;
  Completer<void>? _heldRead;

  void holdNextRead() => _holdingRead = Completer<void>();

  void finishHeldRead() {
    (_heldRead ?? _holdingRead)?.complete();
    _heldRead = null;
    _holdingRead = null;
  }

  @override
  Future<ResumePoint?> of(String book, String pericope, String language) async {
    final row = rows['$book/$pericope/$language'];
    final held = _holdingRead;
    if (held != null) {
      _holdingRead = null;
      _heldRead = held;
      await held.future;
    }
    return row;
  }

  @override
  Future<void> remember(
    String book,
    String pericope,
    String language,
    ResumePoint point,
  ) async {
    written.add(point);
    rows['$book/$pericope/$language'] = point;
  }

  @override
  Future<void> forget(String book, String pericope, String language) async =>
      rows.remove('$book/$pericope/$language');

  Duration? forgetsTheSessionAfter;

  @override
  Future<List<ResumePoint>> forgetTheSession(String sessionId) async {
    final wait = forgetsTheSessionAfter;
    if (wait != null) await Future<void>.delayed(wait);
    final forgotten = [
      for (final row in rows.values)
        if (row.sessionId == sessionId) row,
    ];
    rows.removeWhere((_, row) => row.sessionId == sessionId);
    return forgotten;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInbox implements HandInboxRepository {
  @override
  http.Client get client => throw UnimplementedError();

  /// What this tablet last told the hand to present as itself. What the header actually
  /// carries is measured against real HTTP, not here.
  String? presented;

  @override
  void presents(String? credential) => presented = credential;

  List<HandReply> replies;
  final List<String> heard = [];
  final List<String> questionsSent = [];
  bool cannotBeAsked = false;

  /// What the desk answers a Knot with instead of taking it.
  RoomFailure? knotFailsWith;

  /// Whether the Knot's recording cannot be read off the disk to be sent.
  bool cannotReadTheKnot = false;

  /// How many times the tablet checked for waiting replies.
  int checks = 0;

  FakeInbox({this.replies = const []});

  Completer<void>? _holdingCheck;

  /// Hold the next check on the wire: the desk has already answered with what it held
  /// when asked, and the answer lands only when released.
  void holdNextCheck() => _holdingCheck = Completer<void>();

  void finishHeldCheck() {
    _holdingCheck?.complete();
    _holdingCheck = null;
  }

  final List<Completer<void>> _checksHeldAlone = [];
  int _checksTakenAlone = 0;

  void holdOneCheck() => _checksHeldAlone.add(Completer<void>());

  void finishTheFirstHeldCheck() {
    for (final held in _checksHeldAlone) {
      if (held.isCompleted) continue;
      held.complete();
      return;
    }
  }

  @override
  Future<RoomAnswer<List<HandReply>>> fetchReplies() async {
    checks++;
    final RoomAnswer<List<HandReply>> answer = cannotBeAsked
        ? const NetworkFailed('sem rede')
        : Answered(replies);
    final held = _holdingCheck;
    if (held != null) await held.future;
    if (_checksTakenAlone < _checksHeldAlone.length) {
      await _checksHeldAlone[_checksTakenAlone++].future;
    }
    return answer;
  }

  /// What the mark comes back with instead of the desk agreeing.
  RoomFailure? marksFailWith;

  @override
  Future<RoomAnswer<void>> markHeard(
    String replyId, {
    required String audioUrl,
  }) async {
    final failure = marksFailWith;
    if (failure != null) return failure;
    heard.add(replyId);
    return const Answered(null);
  }

  final _revocations = StreamController<String?>.broadcast();

  @override
  Stream<String?> get revoked => _revocations.stream;

  Completer<void>? _holdingQuestion;

  void holdNextQuestion() => _holdingQuestion = Completer<void>();

  void finishHeldQuestion() {
    _holdingQuestion?.complete();
    _holdingQuestion = null;
  }

  @override
  Future<RoomAnswer<void>> sendQuestion(String sessionId, File audio) async {
    final held = _holdingQuestion;
    if (held != null) await held.future;
    if (cannotReadTheKnot) {
      throw FileSystemException('sem arquivo', audio.path);
    }
    final failure = knotFailsWith;
    if (failure case Refused(code: RefusalCode.deviceRevoked)) {
      _revocations.add(presented);
    }
    if (failure != null) return failure;
    questionsSent.add(sessionId);
    return const Answered(null);
  }

  @override
  void dispose() {}
}

Future<RoomAnswer<String>> noFixedLine(
  String line, {
  required String language,
}) async => const NetworkFailed('nenhuma linha fixa');

class FakeRoom implements RoomRepository {
  @override
  http.Client get client => throw UnimplementedError();

  StreamController<CoverageEvent> _coverage =
      StreamController<CoverageEvent>.broadcast();

  int watchCoverageCalls = 0;

  void pushCoverage(CoverageEvent event) => _coverage.add(event);

  /// Ends the channel a caller is listening to right now, the way Cloud Run's 300 s cut
  /// or a room refusal does — the next [watchCoverage] call gets a fresh stream, since the
  /// old one is gone for good.
  void dropCoverageStream({Object? error}) {
    final dying = _coverage;
    _coverage = StreamController<CoverageEvent>.broadcast();
    if (error != null) dying.addError(error);
    dying.close();
  }

  @override
  Stream<CoverageEvent> watchCoverage(String sessionId) {
    watchCoverageCalls++;
    if (_forgot('watchCoverage', sessionId) case final gone?) {
      return Stream.error(gone);
    }
    return _coverage.stream;
  }

  /// What a turn's own response says about the id classification will settle under, and
  /// whether classification is still running for it. Pending by default — the way a real
  /// conversational turn from the backend behaves — so a double built for some other
  /// behaviour still exercises the wait the way production would. Null generates a fresh
  /// id per turn, as the server does; a test naming a fixed id owns matching it itself.
  String? turnIdInResponse;
  bool classificationPending = true;
  int _turnCount = 0;

  final List<String> calls = [];
  final List<String?> pericopesAsked = [];
  final List<String> languagesSent = [];
  final List<String?> clientTimingsSent = [];
  final List<String> languagesAsked = [];
  final List<List<Map<String, Object?>>> playedByTakeSent = [];
  final List<bool> metBefore = [];
  final List<String> clipsFetched = [];
  bool reachable = true;
  Coverage nextCoverage = coverage();
  Moment? nextMoment;
  List<KeptRetelling> keptRetellings = const [];

  Coverage? settledCoverage;
  bool peerCue = false;

  bool done = false;

  /// What the session read says of the passage's end, when it is not what the turns say.
  bool? readsDone;
  int turnsSent = 0;
  int chunksSent = 0;
  final List<String> chunkSpans = [];

  /// Which recording each told-back stretch named, in order.
  final List<String> chunkTakes = [];

  final List<String> chunkFiles = [];

  /// The names this room gave the recordings it stored, in the order it stored them.
  final List<String> takeIds = [];

  /// Every recording this room is holding, as the route that lists them answers.
  final List<TakeView> takes = [];

  /// The bytes each take's audio comes back as, so a test can tell one file from another.
  final Map<String, Uint8List> takeAudio = {};

  /// What listing the takes throws, when it is set.
  RoomFailure? failTakesWith;

  /// The recordings whose audio this room will not hand over, by take id.
  final Set<String> refuseClipOf = {};

  /// How long this room takes to hand over one recording's audio. A link that answers
  /// every part in time is not a link that has stopped, however long the whole fetch adds
  /// up to.
  Duration? clipDelay;

  Completer<void>? _holdingClip;

  /// Hold the next audio this room is asked for, the way a bad link holds a whole part.
  void holdNextClip() => _holdingClip = Completer<void>();

  void finishHeldClip() {
    _holdingClip?.complete();
    _holdingClip = null;
  }

  final List<String> keptRetellingsFetched = [];
  Map<String, Uint8List> keptAudio = {};
  RoomFailure? failKeptRetellingWith;
  Completer<void>? _holdingKeptRetelling;

  void holdNextKeptRetelling() => _holdingKeptRetelling = Completer<void>();

  void finishHeldKeptRetelling() {
    _holdingKeptRetelling?.complete();
    _holdingKeptRetelling = null;
  }

  @override
  Future<RoomAnswer<Uint8List>> fetchKeptRetelling(String url) async {
    keptRetellingsFetched.add(url);
    final held = _holdingKeptRetelling;
    if (held != null) await held.future;
    final refusal = failKeptRetellingWith;
    if (refusal != null) return refusal;
    return Answered(keptAudio[url] ?? Uint8List.fromList([1, 2, 3]));
  }

  /// The stretches this room kept, in the order they were told. A room that forgets what
  /// it was told cannot hand a telling-back back, and cannot name the stretch a finding
  /// lands on either.
  final List<SegmentView> segments = [];

  List<SegmentView> get _numbered {
    var told = 0;
    return [
      for (final segment in segments)
        SegmentView(
          segmentId: segment.segmentId,
          takeId: segment.takeId,
          startsMs: segment.startsMs,
          endsMs: segment.endsMs,
          told: segment.told,
          frase: segment.told ? ++told : null,
        ),
    ];
  }

  List<String> get segmentIds => [
    for (final segment in segments) segment.segmentId,
  ];
  final List<String> takesKept = [];

  /// What the next takes answer, one each, before [refuseTake] is read.
  final List<RoomFailure> takeAnswersFirst = [];
  final List<({String kind, String scope, int? chunkIndex})> takesReceived = [];
  final List<int?> takePasses = [];
  String? refuseTake;

  /// The code the refusal of [refuseTake] names: a bare `HTTP_<status>` is a server that
  /// named none.
  String refuseTakeCode = 'UNKNOWN_REFERENCE';

  /// The one kind/scope whose upload finds no network, while every other call gets through.
  String? unreachableTake;
  RoomFailure? failReplaceWith;
  RoomFailure? loseTheNextReplaceAnswerWith;
  RoomFailure? loseTheNextReplaceAnswerAndLandItLaterWith;
  final List<RoomFailure> replaceAnswersFirst = [];
  void Function()? _landingLater;

  void landTheLostReplace() {
    final landing = _landingLater;
    _landingLater = null;
    landing?.call();
  }

  final Set<String> _retired = {};

  void recordThePartAgain(String takeId) {
    for (final segment in segments.where((one) => one.takeId == takeId)) {
      _retired.add(segment.segmentId);
    }
    segments.removeWhere((one) => one.takeId == takeId);
  }

  final Set<String> _replacedTakes = {};

  Duration? replacedTakeRefusalAfter;

  void replaceThePart(String takeId) {
    final old = takes.firstWhere((take) => take.takeId == takeId);
    final id = 'gravacao-${takeIds.length + 1}';
    takeIds.add(id);
    takes.add(
      TakeView(
        takeId: id,
        kind: old.kind,
        scope: old.scope,
        ordinal: old.ordinal,
        pass: (old.pass ?? 1) + 1,
      ),
    );
    takeAudio[id] = Uint8List.fromList(utf8.encode('áudio de $id'));
    _replacedTakes.add(takeId);
  }

  RoomFailure? failChunkWith;

  /// What the next stretches told back are answered with, in order, before the room
  /// hears them: the one knob that lets a resend meet a key still in flight.
  final List<RoomFailure> chunkAnswersFirst = [];

  /// The `Idempotency-Key` every stretch told back carried, in order, the ones that
  /// never reached the room included.
  final List<String> chunkKeys = [];

  /// The `Idempotency-Key` every retelling carried, in order, the ones that never
  /// reached the room included.
  final List<String> replaceKeys = [];

  /// What the next call to `fetchState` throws, independent of `failWith` — a case needs
  /// the settle poll to fail exactly once, so the read after it can succeed instead of
  /// failing the same way forever.
  RoomFailure? failStateOnceWith;

  Duration? failedReadsLandAfter;
  int failedReadsInTheAir = 0;

  /// What the next call to `createSession` throws, independent of `failWith` — a case
  /// needs a retry that opens a session for the same passage to fail exactly once too, so
  /// the attempt after it can land.
  RoomFailure? failCreateOnceWith;

  /// What the ask for a verdict throws, when it is set. The one knob that lets a test put
  /// a failure between a correction the room answered and the answer reaching the team.
  RoomFailure? failFinishWith;

  /// Run while the ask for a verdict is still in the air. The seam for a test that needs
  /// the team to do something — leave the passage, say — during that wait.
  void Function()? duranteOVeredito;

  /// Whether the room answers a correction by asking for a person. False is also what a
  /// server that does not send the field at all looks like from here.
  bool replaceNeedsPerson = false;

  /// Which stretch each retelling named, and the slice it sent, in order.
  final List<String> replacesAsked = [];

  /// The recording each retelling carried up, by the file it was, in order.
  final List<String> replacesComArquivo = [];
  int _versoes = 0;

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

  /// Which parts this room says the report does not cover, when that is what stopped the
  /// reading. Empty is a room that refused nothing, which is also what a server that does
  /// not send the field at all looks like from here.
  List<String> verdictUnheardTakeIds = const [];

  /// Which current parts this room says have no stretch told over them, when that is what
  /// stopped the reading. Its own field, as on the wire: read before [verdictUnheardTakeIds]
  /// the way the server's own errands are ordered.
  List<String> verdictUntoldTakeIds = const [];
  bool verdictHasFinding = false;
  List<BtFinding> verdictFindings = const [];
  CheckRefusal? verdictRefusal;
  String verdictFixedLine = '';
  String? verdictCheckAt;
  BtFinding? verdictNamedNuance;
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
  final List<String> booksAsked = [];
  List<Passagem> passages = const [
    Passagem(
      pericope: 'P01',
      audioUrl: '/voice/p01',
      book: 'Ruth',
      reference: 'Ruth 1:1–5',
    ),
    Passagem(
      pericope: 'P02',
      audioUrl: '/voice/p02',
      book: 'Ruth',
      reference: 'Ruth 1:6–14',
    ),
    Passagem(
      pericope: 'P03',
      audioUrl: '/voice/p03',
      book: 'Ruth',
      reference: 'Ruth 1:15–18',
    ),
  ];

  /// The ids this room gave the sessions it opened, in the order it opened them.
  final List<String> sessionIds = [];

  /// When set, the id [createSession] hands back, in place of `sessao-N`.
  String? nextSessionId;

  /// Which session each turn was spoken into, the opening one included, in order.
  final List<String> sessionsSpokenTo = [];

  /// The turn id each opening turn carried, null included, in the order it was asked.
  final List<String?> turnIdsAsked = [];

  /// The sessions that hold a Guide line: an opening answered, or a team turn.
  final Set<String> openedSessions = {};

  /// The sessions this room was asked to say its last line again, in order.
  final List<String> sessionsSaidAgain = [];

  /// Whether the session `createSession` hands back is one the team already talked in,
  /// the way another tablet or a lost row leaves it.
  bool createdOpened = false;

  final List<String> turnIdsSent = [];

  /// Where each turn sent said the Guide was cut, one entry per turn: null for a turn
  /// that followed no interruption.
  final List<CutPoint?> cutsSent = [];

  final List<String> recordingsSent = [];

  int personsAsked = 0;

  final List<String?> codesAskedFor = [];

  /// Which device this room was asked to hand a credential to, in order.
  final List<String> credentialsCollected = [];

  /// What this tablet last told the room to present as itself. What the header actually
  /// carries is measured against real HTTP, not here.
  ///
  /// A linked tablet's by default, so a case about the room need not walk the link first;
  /// a case about the link starts from whatever `findTheTeam` presents.
  String? presented = 'credencial-1';
  String credential = 'credencial-1';
  RoomFailure? refuseCredentialWith;
  RoomFailure? refuseLinkWith;
  int linksRead = 0;
  List<String> claimCodes = const ['QHF-3M7K'];
  Duration claimCodeLife = const Duration(minutes: 15);
  TeamLink? linkedTo;

  RoomFailure? failWith;

  Set<String> passagesThatCannotOpen = {};

  Completer<void>? _holdingPassages;

  void holdNextPassages() => _holdingPassages = Completer<void>();

  /// The Wheel each language is read as, when a case needs to tell two reads apart.
  Map<String, List<Passagem>> passagesIn = {};

  /// The books this room serves, in the order `GET /books` answers them.
  List<String> books = const ['Ruth'];

  /// Each book's list, when a case serves more than one book; a book left out answers
  /// [passagesIn] or [passages].
  Map<String, List<Passagem>> passagesOfBook = {};

  /// What the books read answers, when it fails.
  RoomFailure? failBooksWith;

  /// What one book's list answers, when it fails.
  Map<String, RoomFailure> failPassagesOf = {};

  Completer<void>? _holdingOneRead;

  /// Hold only the next read of the Wheel; a read asked meanwhile answers at once.
  Completer<void> holdOneWheelRead() => _holdingOneRead = Completer<void>();

  void finishHeldPassages() {
    _holdingPassages?.complete();
    _holdingPassages = null;
  }

  Completer<void>? _holdingTurn;
  Completer<void>? _holdingCode;

  void holdNextCode() => _holdingCode = Completer<void>();

  Completer<void>? _holdingCreate;
  Completer<void>? _heldCreate;

  void holdNextCreate() => _holdingCreate = Completer<void>();

  bool get createHeld => _heldCreate != null;

  void finishHeldCreate() {
    _heldCreate?.complete();
    _heldCreate = null;
  }

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
  RoomFailure? failHeldTurnWith;

  RoomFailure? failTurnsWith;

  Future<RoomFailure?> _turnArrives() async {
    final held = _holdingTurn;
    if (held != null) await held.future;
    final never = failTurnsWith;
    if (never != null) return never;
    final failure = failHeldTurnWith;
    failHeldTurnWith = null;
    return failure;
  }

  final Set<String> forgottenSessions = {};
  final List<String> askedOfTheForgotten = [];

  void forgetTheSession(String sessionId) => forgottenSessions.add(sessionId);

  RoomFailure? _forgot(String call, String sessionId) {
    if (!forgottenSessions.contains(sessionId)) return null;
    askedOfTheForgotten.add(call);
    return const SessionGone();
  }

  static const _claimDoors = {
    'askForACode',
    'readTheLink',
    'collectTheCredential',
  };

  static const _sessionless = {
    ..._claimDoors,
    'createSession',
    'passagesOf',
    'servedBooks',
    'fetchClip',
    'openClip',
  };

  /// What the tablet presented as itself on each call, beside [calls].
  final List<String?> presentedOnEachCall = [];

  final _revocations = StreamController<String?>.broadcast();

  /// Announced, with the credential the call carried, for every call [failWith] turns
  /// down as revoked, the way the real repository announces every one it is answered. A
  /// door's own knob is that door's answer, not the tablet's revocation.
  @override
  Stream<String?> get revoked => _revocations.stream;

  RoomFailure? _guard(String call) {
    calls.add(call);
    presentedOnEachCall.add(presented);
    final failure = failWith;
    if (failure is SessionGone && _sessionless.contains(call)) {
      return const Refused(RefusalCode.notFound);
    }
    if (failure case Refused(code: RefusalCode.deviceRevoked)) {
      if (_claimDoors.contains(call)) {
        return reachable ? null : const NetworkFailed('sem rede');
      }
      _revocations.add(presented);
    }
    if (failure == null &&
        reachable &&
        presented == null &&
        !_claimDoors.contains(call)) {
      return const Refused(RefusalCode.unauthorized);
    }
    return failure ?? (reachable ? null : const NetworkFailed('sem rede'));
  }

  @override
  Future<RoomAnswer<ClaimCode>> askForACode(String? deviceId) async {
    if (_guard('askForACode') case final failure?) return failure;
    codesAskedFor.add(deviceId);
    final held = _holdingCode;
    if (held != null) await held.future;
    return Answered(
      ClaimCode(
        deviceId: 'aparelho-1',
        code: claimCodes[min(codesAskedFor.length - 1, claimCodes.length - 1)],
        expiresAt: DateTime.now().toUtc().add(claimCodeLife),
      ),
    );
  }

  @override
  Future<RoomAnswer<TeamLink?>> readTheLink(String deviceId) async {
    if (_guard('readTheLink') case final failure?) return failure;
    linksRead++;
    final refusal = refuseLinkWith;
    if (refusal != null) return refusal;
    return Answered(linkedTo);
  }

  @override
  Future<RoomAnswer<String>> collectTheCredential(String deviceId) async {
    if (_guard('collectTheCredential') case final failure?) return failure;
    credentialsCollected.add(deviceId);
    final refusal = refuseCredentialWith;
    if (refusal != null) return refusal;
    return Answered(credential);
  }

  @override
  void presents(String? credential) => presented = credential;

  @override
  Future<RoomAnswer<Uint8List>> fetchClip(String url) async {
    if (_guard('fetchClip') case final failure?) return failure;
    clipsFetched.add(url);
    final held = _holdingClip;
    if (held != null) await held.future;
    final devagar = clipDelay;
    if (devagar != null) await Future<void>.delayed(devagar);
    final refusal = failClipWith;
    if (refusal != null) return refusal;
    final sceneFailure = failSceneWith;
    if (sceneFailure != null && url.contains('/scene-rehearsals/')) {
      return sceneFailure;
    }
    for (final gone in forgottenSessions) {
      if (url.contains('/sessions/$gone/scene-rehearsals/')) {
        return const Refused(RefusalCode.notFound);
      }
    }
    final sceneBytes = sceneAudio;
    if (sceneBytes != null && url.contains('/scene-rehearsals/')) {
      return Answered(sceneBytes);
    }
    for (final take in refuseClipOf) {
      if (url.endsWith('/takes/$take/audio')) {
        return const Refused(RefusalCode.notFound);
      }
    }
    for (final entry in takeAudio.entries) {
      if (url.endsWith('/takes/${entry.key}/audio')) {
        return Answered(entry.value);
      }
    }
    return Answered(Uint8List.fromList([1, 2, 3]));
  }

  /// What fetching audio throws, when it is set.
  RoomFailure? failClipWith;

  @override
  Future<RoomAnswer<String>> fixedLineAddress(
    String line, {
    required String language,
  }) async {
    if (_guard('fixedLineAddress') case final failure?) return failure;
    return Answered('/api/internalization-room/voice/$language-$line');
  }

  @override
  Future<http.StreamedResponse> openClip(
    String url, {
    int? from,
    String? ifRange,
  }) async {
    if (_guard('openClip') case final failure?) throw failure;
    return http.StreamedResponse(
      Stream.value([1, 2, 3]),
      200,
      contentLength: 3,
    );
  }

  @override
  Future<RoomAnswer<List<TakeView>>> takesOf(String sessionId) async {
    if (_guard('takesOf') case final failure?) return failure;
    if (_forgot('takesOf', sessionId) case final gone?) {
      return gone;
    }
    final refusal = failTakesWith;
    if (refusal != null) return refusal;
    return Answered(List.of(takes));
  }

  /// Every live scene rehearsal of the passage, from every session, as the list answers.
  final List<SceneRehearsalRecord> sceneRehearsals = [];

  /// The session each scene take this room kept was sent for, in order.
  final List<String> scenesKept = [];
  final List<String?> sceneLabels = [];
  final List<Uint8List> sceneTakesSent = [];

  /// Every restart of a scene translation this room was sent.
  final List<({String attempt, String? closes})> restartsSent = [];

  /// What every scene door answers, the scene take's audio included, when it is set.
  RoomFailure? failSceneWith;

  /// What the next keeps answer, one each, before [failSceneWith] is read.
  final List<RoomFailure> sceneAnswersFirst = [];

  /// What the next reads of the scene rehearsals' list answer, one each.
  final List<RoomFailure> sceneListsAnswerFirst = [];

  /// The code a restart is refused with, when it is set.
  String? refuseRestartWith;

  /// The bytes every scene take's audio comes back as, when it is set.
  Uint8List? sceneAudio;

  bool _holdTheNextSceneList = false;
  final List<Completer<void>> _heldSceneLists = [];

  /// Hold the next list of scene rehearsals, the way a slow link holds it. It answers
  /// with what the room held when it was asked.
  void holdNextSceneList() => _holdTheNextSceneList = true;

  void finishHeldSceneList() => _heldSceneLists.removeAt(0).complete();

  Completer<void>? _holdingKeep;
  Completer<void>? _holdingKeepBefore;

  /// Hold the next keep's answer, after the room has taken the take.
  void holdNextKeep() => _holdingKeep = Completer<void>();

  /// Hold the next keep before the room acts, so what it answers is read when it is let
  /// go.
  void holdNextKeepBeforeTheRoomActs() =>
      _holdingKeepBefore = Completer<void>();

  void finishHeldKeep() {
    _holdingKeep?.complete();
    _holdingKeep = null;
    _holdingKeepBefore?.complete();
    _holdingKeepBefore = null;
  }

  Completer<void>? _holdingRestart;

  /// Hold the next restart's answer, after the room has been sent it.
  void holdNextRestart() => _holdingRestart = Completer<void>();

  void finishHeldRestart() {
    _holdingRestart?.complete();
    _holdingRestart = null;
  }

  @override
  Future<RoomAnswer<List<SceneRehearsalRecord>>> sceneRehearsalsOf(
    String sessionId,
  ) async {
    if (_guard('sceneRehearsalsOf') case final failure?) return failure;
    if (sceneListsAnswerFirst.isNotEmpty) {
      return sceneListsAnswerFirst.removeAt(0);
    }
    final listed = List.of(sceneRehearsals);
    if (_holdTheNextSceneList) {
      _holdTheNextSceneList = false;
      final held = Completer<void>();
      _heldSceneLists.add(held);
      await held.future;
    }
    if (_forgot('sceneRehearsalsOf', sessionId) case final gone?) return gone;
    final refusal = failSceneWith;
    if (refusal != null) return refusal;
    return Answered(listed);
  }

  /// The passage's scenes as the scenes door answers them, in passage order. None by
  /// default: the screen then asks nothing and labels nothing.
  List<Scene> passageScenes = const [];

  /// The scenes the room's keep knows as labels, when they are not [passageScenes]'s.
  Set<String>? roomScenes;

  /// What the scenes door answers, when it is set.
  RoomFailure? failScenesWith;

  bool _holdTheNextScenes = false;
  final List<Completer<void>> _heldScenes = [];

  /// Hold the next ask for the passage's scenes, the way a slow link holds it.
  void holdNextScenes() => _holdTheNextScenes = true;

  void finishHeldScenes() => _heldScenes.removeAt(0).complete();

  @override
  Future<RoomAnswer<List<Scene>>> scenesOf(String sessionId) async {
    if (_guard('scenesOf') case final failure?) return failure;
    if (_holdTheNextScenes) {
      _holdTheNextScenes = false;
      final held = Completer<void>();
      _heldScenes.add(held);
      await held.future;
    }
    if (_forgot('scenesOf', sessionId) case final gone?) return gone;
    final refusal = failScenesWith;
    if (refusal != null) return refusal;
    return Answered(List.of(passageScenes));
  }

  @override
  Future<RoomAnswer<SceneRehearsalRecord>> keepSceneRehearsal(
    String sessionId,
    File audio, {
    String? scene,
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
  }) async {
    if (_guard('keepSceneRehearsal') case final failure?) return failure;
    await _holdingKeepBefore?.future;
    if (_forgot('keepSceneRehearsal', sessionId) case final gone?) return gone;
    if (sceneAnswersFirst.isNotEmpty) return sceneAnswersFirst.removeAt(0);
    final refusal = failSceneWith;
    if (refusal != null) return refusal;
    scenesKept.add(sessionId);
    sceneLabels.add(scene);
    sceneTakesSent.add(audio.readAsBytesSync());
    final n = sceneRehearsals.length + 1;
    final known =
        roomScenes ?? {for (final scene in passageScenes) scene.sceneId};
    final kept = SceneRehearsalRecord(
      rehearsalId: 'ensaio-da-cena-$n',
      sessionId: sessionId,
      n: n,
      scene: known.contains(scene) ? scene : null,
    );
    sceneRehearsals.add(kept);
    await _holdingKeep?.future;
    return Answered(kept);
  }

  @override
  Future<RoomAnswer<SceneRehearsalRecord>> restartTheSceneTranslation(
    String sessionId,
    String rehearsalId, {
    required String attempt,
    String? closes,
  }) async {
    if (_guard('restartTheSceneTranslation') case final failure?) {
      return failure;
    }
    restartsSent.add((attempt: attempt, closes: closes));
    await _holdingRestart?.future;
    if (forgottenSessions.contains(sessionId)) {
      return const Refused(RefusalCode.notFound);
    }
    final refusal = failSceneWith;
    if (refusal != null) return refusal;
    final code = refuseRestartWith;
    if (code != null) return Refused(code);
    final at = sceneRehearsals.indexWhere(
      (rehearsal) => rehearsal.rehearsalId == rehearsalId,
    );
    final old = sceneRehearsals[at];
    final restarted = SceneRehearsalRecord(
      rehearsalId: old.rehearsalId,
      sessionId: old.sessionId,
      n: old.n,
      scene: old.scene,
      recordedAt: old.recordedAt,
      sentAt: old.sentAt,
      afterRestart: attempt,
      durationMs: old.durationMs,
    );
    sceneRehearsals[at] = restarted;
    return Answered(restarted);
  }

  /// Every frase this room was sent: its span, the attempt it names, its audio and the
  /// frase it replaces.
  final List<
    ({
      int startsMs,
      int endsMs,
      String? afterRestart,
      Uint8List audio,
      String? replaces,
    })
  >
  frasesKept = [];

  Completer<void>? _holdingFrase;

  /// Hold the next frase's answer, after the room has been sent it, the way hearing it
  /// holds it.
  void holdNextFrase() => _holdingFrase = Completer<void>();

  void finishHeldFrase() {
    _holdingFrase?.complete();
    _holdingFrase = null;
  }

  final List<Completer<void>> _oneFraseHolds = [];

  /// Hold only the next frase the room is sent, the way a slow link holds one request:
  /// the frases after it go through, and it answers when the completer is completed.
  Completer<void> holdTheNextFrase() {
    final hold = Completer<void>();
    _oneFraseHolds.add(hold);
    return hold;
  }

  @override
  Future<RoomAnswer<SceneRehearsalRecord>> keepTheSceneFrase(
    String sessionId,
    String rehearsalId,
    File audio, {
    required int startsMs,
    required int endsMs,
    String? afterRestart,
    String? replaces,
  }) async {
    if (_guard('keepTheSceneFrase') case final failure?) return failure;
    final bytes = audio.readAsBytesSync();
    frasesKept.add((
      startsMs: startsMs,
      endsMs: endsMs,
      afterRestart: afterRestart,
      audio: bytes,
      replaces: replaces,
    ));
    await _holdingFrase?.future;
    if (_oneFraseHolds.isNotEmpty) await _oneFraseHolds.removeAt(0).future;
    for (final late in _frasesLandingLate) {
      _keepAFrase(
        late.rehearsalId,
        late.bytes,
        late.startsMs,
        late.endsMs,
        late.replaces,
      );
    }
    _frasesLandingLate.clear();
    if (forgottenSessions.contains(sessionId)) {
      return const Refused(RefusalCode.notFound);
    }
    final lost = sceneAnswersFirst.isNotEmpty
        ? sceneAnswersFirst.removeAt(0)
        : failSceneWith;
    if (lost != null && frasesLandAfterTheyFail) {
      _frasesLandingLate.add((
        rehearsalId: rehearsalId,
        bytes: bytes,
        startsMs: startsMs,
        endsMs: endsMs,
        replaces: replaces,
      ));
      return lost;
    }
    if (lost != null && !frasesLandBeforeTheyFail) return lost;
    final kept = _keepAFrase(rehearsalId, bytes, startsMs, endsMs, replaces);
    return lost ?? kept;
  }

  /// The newest frase of the chain [replaces] begins, as the room resolves a frase that
  /// names one already replaced.
  static String? _theNewestOf(String? replaces, List<SceneFrase> frases) {
    var head = replaces;
    while (true) {
      final next = frases
          .where((frase) => frase.fraseId == head)
          .firstOrNull
          ?.replacedBy;
      if (next == null) return head;
      head = next;
    }
  }

  /// The room's rule: the same bytes are the same frase, whatever their span. A frase
  /// that names the one it replaces may lie over the newest of its chain, and the
  /// replaced one stays as history.
  RoomAnswer<SceneRehearsalRecord> _keepAFrase(
    String rehearsalId,
    Uint8List bytes,
    int startsMs,
    int endsMs,
    String? replaces,
  ) {
    final at = sceneRehearsals.indexWhere(
      (rehearsal) => rehearsal.rehearsalId == rehearsalId,
    );
    if (at < 0) return const Refused(RefusalCode.notFound);
    final old = sceneRehearsals[at];
    for (final frase in old.frases) {
      final heard = _fraseBytes[frase.fraseId];
      if (heard != null && _sameBytes(heard, bytes)) return Answered(old);
    }
    final head = _theNewestOf(replaces, old.frases);
    final measured = old.durationMs;
    final overlaps =
        refusesOverlappingFrases &&
        old.currentFrases.any(
          (frase) =>
              frase.fraseId != head &&
              frase.placedIn(const Duration(days: 1)) &&
              startsMs < frase.endsMs! &&
              endsMs > frase.startsMs!,
        );
    if (startsMs < 0 ||
        endsMs <= startsMs ||
        (measured != null && endsMs > measured) ||
        overlaps) {
      return const Refused(RefusalCode.fraseOutOfPlace);
    }
    final fraseId = '$rehearsalId-frase-${old.frases.length + 1}';
    _fraseBytes[fraseId] = bytes;
    final kept = SceneRehearsalRecord(
      rehearsalId: old.rehearsalId,
      sessionId: old.sessionId,
      n: old.n,
      scene: old.scene,
      recordedAt: old.recordedAt,
      sentAt: old.sentAt,
      afterRestart: old.afterRestart,
      durationMs: old.durationMs,
      frases: [
        for (final frase in old.frases)
          frase.fraseId == head
              ? SceneFrase(
                  fraseId: frase.fraseId,
                  startsMs: frase.startsMs,
                  endsMs: frase.endsMs,
                  replacedBy: fraseId,
                )
              : frase,
        SceneFrase(fraseId: fraseId, startsMs: startsMs, endsMs: endsMs),
      ],
    );
    sceneRehearsals[at] = kept;
    return Answered(kept);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  final Map<String, Uint8List> _fraseBytes = {};

  final List<
    ({
      String rehearsalId,
      Uint8List bytes,
      int startsMs,
      int endsMs,
      String? replaces,
    })
  >
  _frasesLandingLate = [];

  /// Whether a frase whose answer fails was kept by the room all the same, the way a
  /// reply lost after the room acted is.
  bool frasesLandBeforeTheyFail = false;

  /// Whether the room refuses a frase whose span strictly overlaps a current one, as
  /// shema-api does once its overlap refusal lands.
  bool refusesOverlappingFrases = false;

  /// Whether a frase whose answer fails is kept by the room only after it answered, the
  /// way a frase still being heard when the tablet gave up is: it lands before the next
  /// frase the room is sent.
  bool frasesLandAfterTheyFail = false;

  /// Every «terminei» this room was sent: the rehearsal, its turn and the attempt it closed.
  final List<({String rehearsalId, String turnId, String? closes})> scenesSent =
      [];

  /// The codes the next sends are refused with, one per send, in order.
  final List<String> sendRefusalsFirst = [];

  @override
  Future<RoomAnswer<TurnResult>> sendTheSceneRehearsal(
    String sessionId,
    String rehearsalId, {
    required String turnId,
    String? closes,
  }) async {
    if (_guard('sendTheSceneRehearsal') case final failure?) return failure;
    scenesSent.add((rehearsalId: rehearsalId, turnId: turnId, closes: closes));
    if (sendRefusalsFirst.isNotEmpty) {
      return Refused(sendRefusalsFirst.removeAt(0));
    }
    if (forgottenSessions.contains(sessionId)) {
      return const Refused(RefusalCode.notFound);
    }
    final answer = await _theTurnAnswers(sessionId, turnId);
    final at = sceneRehearsals.indexWhere(
      (rehearsal) => rehearsal.rehearsalId == rehearsalId,
    );
    final landed = answer is Answered<TurnResult> || turnsLandBeforeTheyFail;
    if (landed && at >= 0) {
      final old = sceneRehearsals[at];
      sceneRehearsals[at] = SceneRehearsalRecord(
        rehearsalId: old.rehearsalId,
        sessionId: old.sessionId,
        n: old.n,
        scene: old.scene,
        recordedAt: old.recordedAt,
        sentAt: '2026-10-15T15:00:00+00:00',
        afterRestart: old.afterRestart,
        durationMs: old.durationMs,
        frases: old.frases,
      );
    }
    return answer;
  }

  @override
  Future<RoomAnswer<SessionSnapshot>> createSession({
    String? pericope,
    String? afterSession,
    required String language,
  }) async {
    if (_guard('createSession') case final failure?) return failure;
    final held = _holdingCreate;
    _holdingCreate = null;
    if (held != null) {
      _heldCreate = held;
      await held.future;
    }
    if (pericope != null && passagesThatCannotOpen.contains(pericope)) {
      return const Refused(RefusalCode.passageCannotOpen);
    }
    if (afterSession != null) {
      if (_forgot('createSession', afterSession) case final gone?) {
        return gone;
      }
    }
    final failure = failCreateOnceWith;
    if (failure != null) {
      failCreateOnceWith = null;
      return failure;
    }
    pericopesAsked.add(pericope);
    metBefore.add(afterSession != null);
    languagesSent.add(language);
    final sessionId = nextSessionId ?? 'sessao-${sessionIds.length + 1}';
    sessionIds.add(sessionId);
    return Answered(
      SessionSnapshot(
        sessionId: sessionId,
        pericope: pericope ?? 'rute-1',
        status: serverStatus ?? 'in_progress',
        coverage: nextCoverage,
        done: false,
        halt: serverHalt,
        opened: createdOpened,
        moment: nextMoment,
      ),
    );
  }

  Completer<void>? _holdingBooks;

  /// Hold the next ask for the served books, the way a link that never answers holds it.
  void holdNextBooks() => _holdingBooks = Completer<void>();

  @override
  Future<RoomAnswer<List<String>>> servedBooks() async {
    if (_guard('servedBooks') case final failure?) return failure;
    final held = _holdingBooks;
    _holdingBooks = null;
    if (held != null) await held.future;
    return failBooksWith ?? Answered(books);
  }

  @override
  Future<RoomAnswer<List<Passagem>>> passagesOf(
    String book, {
    required String language,
  }) async {
    if (_guard('passagesOf') case final failure?) return failure;
    await _holdingPassages?.future;
    final heldRead = _holdingOneRead;
    _holdingOneRead = null;
    await heldRead?.future;
    booksAsked.add(book);
    languagesAsked.add(language);
    return failPassagesOf[book] ??
        Answered(passagesOfBook[book] ?? passagesIn[language] ?? passages);
  }

  @override
  Future<RoomAnswer<SessionSnapshot>> fetchState(String sessionId) async {
    if (_guard('fetchState') case final failure?) {
      final wait = failedReadsLandAfter;
      if (wait == null) return failure;
      failedReadsInTheAir++;
      await Future<void>.delayed(wait);
      failedReadsInTheAir--;
      return failure;
    }
    if (_forgot('fetchState', sessionId) case final gone?) {
      return gone;
    }
    final failure = failStateOnceWith;
    if (failure != null) {
      failStateOnceWith = null;
      return failure;
    }
    final held = _holdingState;
    if (held != null) await held.future;
    final answer = Answered(
      SessionSnapshot(
        sessionId: sessionId,
        pericope: 'rute-1',
        status: serverStatus ?? ((readsDone ?? done) ? 'done' : 'in_progress'),
        coverage: silentAboutCoverage
            ? null
            : (settledCoverage ?? nextCoverage),
        done: readsDone ?? done,
        halt: serverHalt,
        opened: openedSessions.contains(sessionId),
        moment: nextMoment,
        keptRetellings: keptRetellings,
        backTranslation:
            retroSoFar ??
            BackTranslationProgress(
              segments: _numbered,
              awaitingSegmentId: awaitingSegmentId,
            ),
      ),
    );
    if (_readsToHold > 0) {
      _readsToHold--;
      final reply = Completer<void>();
      heldReads.add(reply);
      await reply.future;
    }
    return answer;
  }

  @override
  Future<RoomAnswer<TurnResult>> openSession(
    String sessionId, {
    String? turnId,
  }) async {
    if (_guard('openSession') case final failure?) return failure;
    if (_forgot('openSession', sessionId) case final gone?) {
      return gone;
    }
    sessionsSpokenTo.add(sessionId);
    turnIdsAsked.add(turnId);
    if (openedSessions.contains(sessionId)) {
      sessionsSaidAgain.add(sessionId);
      final saidAgain = await _theLineSaidAgainArrives().timeout(
        RoomRepository.turnTimeout,
        onTimeout: () => const NetworkFailed('timeout'),
      );
      if (saidAgain != null) return saidAgain;
      return Answered(
        TurnResult(
          sessionId: sessionId,
          audioUrl: deNovoUrl,
          fixedLine: '',
          transcript: '',
          peerCue: false,
          usedFailSafe: turnsAreCanned,
          degraded: false,
          coverage: silentAboutCoverage ? null : nextCoverage,
          done: done,
          moment: nextMoment,
        ),
      );
    }
    return _theTurnAnswers(sessionId, turnId);
  }

  /// What the room stored for each turn it answered, by session and turn id: what the
  /// one look reads back.
  final Map<(String, String), TurnResult> _stored = {};

  /// Whether the room stores a turn the moment it hears it, so that an answer that never
  /// reaches the tablet (the network dropped on the way back, or the tablet gave up
  /// waiting) is still there for the one look.
  bool turnsLandBeforeTheyFail = false;

  /// How many looks find the turn still being answered, the route's 202, before a look
  /// reads what the room stored.
  int looksStillAnswering = 0;

  /// What the looks after the room's last «still answering» answer instead of reading what
  /// is stored, one each, in order.
  final List<RoomFailure> looksFailAfterwards = [];

  Completer<void>? _holdingTheLineSaidAgain;

  /// Hold the room's last line said again on an Opened session, the way a slow room does.
  void holdTheLineSaidAgain() => _holdingTheLineSaidAgain = Completer<void>();

  void finishTheLineSaidAgain() {
    _holdingTheLineSaidAgain?.complete();
    _holdingTheLineSaidAgain = null;
  }

  /// What the next line said again on an Opened session answers instead of the line.
  RoomFailure? failTheLineSaidAgainWith;

  Future<RoomFailure?> _theLineSaidAgainArrives() async {
    await _holdingTheLineSaidAgain?.future;
    final failure = failTheLineSaidAgainWith;
    failTheLineSaidAgainWith = null;
    return failure;
  }

  RoomFailure? failLooksWith;

  /// The turn id every look asked for, the looks that failed included.
  final List<String> turnIdsLookedAt = [];

  /// A turn gives up the way the client does, at [RoomRepository.turnTimeout].
  Future<RoomAnswer<TurnResult>> _theTurnAnswers(
    String sessionId,
    String? turnId,
  ) async {
    final landed = turnsLandBeforeTheyFail ? _turn(sessionId) : null;
    if (landed != null) {
      openedSessions.add(sessionId);
      if (turnId != null) _stored[(sessionId, turnId)] = landed;
    }
    final failure = await _turnArrives().timeout(
      RoomRepository.turnTimeout,
      onTimeout: () => const NetworkFailed('timeout'),
    );
    if (failure != null) return failure;
    final turn = landed ?? _turn(sessionId);
    openedSessions.add(sessionId);
    if (turnId != null) _stored[(sessionId, turnId)] = turn;
    return Answered(turn);
  }

  @override
  Future<RoomAnswer<TurnResult>> lookAtTheTurn(
    String sessionId,
    String turnId,
  ) async {
    turnIdsLookedAt.add(turnId);
    final held = _holdingLook;
    if (held != null) await held.future;
    if (_guard('lookAtTheTurn') case final failure?) return failure;
    if (failLooksWith case final failure?) return failure;
    if (looksStillAnswering > 0) {
      looksStillAnswering--;
      return Refused(RefusalCode.unnamed(202));
    }
    if (looksFailAfterwards.isNotEmpty) return looksFailAfterwards.removeAt(0);
    final stored = _stored[(sessionId, turnId)];
    return stored == null
        ? const Refused(RefusalCode.notFound)
        : Answered(stored);
  }

  Completer<void>? _holdingLook;

  void holdTheLooks() => _holdingLook = Completer<void>();

  void finishTheLooks() {
    _holdingLook?.complete();
    _holdingLook = null;
  }

  Completer<void>? _substituicaoSegura;

  void holdNextReplace() => _substituicaoSegura = Completer<void>();

  void finishHeldReplace() {
    _substituicaoSegura?.complete();
    _substituicaoSegura = null;
  }

  final List<({String sentenceId, String segmentId})> sentencesSent = [];
  final List<String> sentencesLaid = [];
  final List<RoomFailure> sentenceAnswersFirst = [];
  Duration sentenceLaysInAs = const Duration(milliseconds: 3200);
  String? awaitingSegmentId;
  Completer<void>? holdTheSentence;

  @override
  Future<RoomAnswer<TellingAgain>> reRecordTheSentence(
    String sessionId,
    String segmentId,
    File audio, {
    required String sentenceId,
  }) async {
    if (_guard('reRecordTheSentence') case final failure?) return failure;
    sentencesSent.add((sentenceId: sentenceId, segmentId: segmentId));
    await holdTheSentence?.future;
    if (sentenceAnswersFirst.isNotEmpty) {
      return sentenceAnswersFirst.removeAt(0);
    }
    if (!sentencesLaid.contains(sentenceId)) {
      sentencesLaid.add(sentenceId);
      _layIn(segmentId, audio);
    }
    return Answered(TellingAgain(segments: _numbered));
  }

  void _layIn(String segmentId, File audio) {
    final old = segments.firstWhere((one) => one.segmentId == segmentId);
    final before = takes.firstWhere((take) => take.takeId == old.takeId);
    final laid = 'gravacao-${takeIds.length + 1}';
    takeIds.add(laid);
    takes.add(
      TakeView(
        takeId: laid,
        kind: before.kind,
        scope: before.scope,
        ordinal: before.ordinal,
        pass: before.pass,
      ),
    );
    takeAudio[laid] = audio.readAsBytesSync();
    final shift = sentenceLaysInAs.inMilliseconds - (old.endsMs - old.startsMs);
    for (var at = 0; at < segments.length; at++) {
      final one = segments[at];
      if (one.takeId != old.takeId) continue;
      segments[at] = SegmentView(
        segmentId: one.segmentId,
        takeId: laid,
        startsMs: one.startsMs > old.startsMs
            ? one.startsMs + shift
            : one.startsMs,
        endsMs: one.endsMs >= old.endsMs ? one.endsMs + shift : one.endsMs,
        told: one.told,
      );
    }
    awaitingSegmentId = segmentId;
  }

  @override
  Future<RoomAnswer<TellingAgain>> replaceSegment(
    String sessionId,
    String segmentId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
    required String idempotencyKey,
  }) async {
    replaceKeys.add(idempotencyKey);
    if (_guard('replaceSegment') case final failure?) return failure;
    if (_forgot('replaceSegment', sessionId) case final gone?) {
      return gone;
    }
    if (replaceAnswersFirst.isNotEmpty) return replaceAnswersFirst.removeAt(0);
    final kept = forgetsTheKeys ? null : _replacesKept[idempotencyKey];
    if (kept != null) return kept;
    final answer = await _replaceSegment(
      segmentId,
      audio,
      takeId: takeId,
      from: from,
      to: to,
    );
    final settled = _answerLost ?? answer;
    _answerLost = null;
    if (settled case Answered() || Refused()) {
      _replacesKept[idempotencyKey] = settled;
    }
    return answer;
  }

  /// What this room answered under each `Idempotency-Key`, the way ENG-1170 keeps it:
  /// only a settled answer is kept, and a key sent again gets it back untouched.
  final Map<String, RoomAnswer<TellingAgain>> _replacesKept = {};

  /// A room that keeps no answer under a key: a server before #599, or a key past its
  /// 24 h. Every request it gets is new to it.
  bool forgetsTheKeys = false;
  final Map<String, RoomAnswer<BackTranslationChunk>> _chunksKept = {};

  Future<RoomAnswer<TellingAgain>> _replaceSegment(
    String segmentId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) async {
    final segura = _substituicaoSegura;
    if (segura != null) await segura.future;
    final refusal = failReplaceWith;
    if (refusal != null) return refusal;
    if (_retired.contains(segmentId)) {
      return const Refused(
        RefusalCode.stretchNoLongerCounts,
        'This stretch no longer counts',
      );
    }
    final later = loseTheNextReplaceAnswerAndLandItLaterWith;
    if (later != null) {
      loseTheNextReplaceAnswerAndLandItLaterWith = null;
      _landingLater = () {
        if (_retired.contains(segmentId)) return;
        replacesAsked.add(
          '$segmentId@$takeId:${from.inMilliseconds}-${to.inMilliseconds}',
        );
        replacesComArquivo.add(audio.path);
        _tellAgain(segmentId, to);
      };
      return later;
    }
    replacesAsked.add(
      '$segmentId@$takeId:${from.inMilliseconds}-${to.inMilliseconds}',
    );
    replacesComArquivo.add(audio.path);
    final needsPerson = replaceNeedsPerson;
    if (needsPerson) {
      // The room marks the session in the very transaction that answers the correction,
      // so every state read from here on carries the warning until the desk attends it.
      // A double that said it in the answer and nothing on the read would be a server
      // that does not exist, and nothing the desk did could ever reach the tablet.
      serverStatus = 'needs_person';
      serverHalt = HaltKind.warning;
    }
    _tellAgain(segmentId, to);
    final told = Answered(
      TellingAgain(segments: _numbered, needsPerson: needsPerson),
    );
    final lost = loseTheNextReplaceAnswerWith;
    if (lost != null) {
      loseTheNextReplaceAnswerWith = null;
      _answerLost = told;
      return lost;
    }
    return told;
  }

  Answered<TellingAgain>? _answerLost;

  void _tellAgain(String segmentId, Duration to) {
    final at = segments.indexWhere((one) => one.segmentId == segmentId);
    final antes = at >= 0 ? segments[at] : null;
    if (antes != null) {
      // The explanation was redone over a recording that did not move, so the stretch
      // keeps its take and its slice and is told again.
      // A version is a new row, not an edit in place: the room mints a fresh id for the
      // successor and retires the one it replaces. A double that kept the id would let an
      // app follow a pointer the room has already thrown away.
      segments[at] = SegmentView(
        segmentId: '${antes.segmentId}-v${++_versoes}',
        takeId: antes.takeId,
        startsMs: antes.startsMs,
        endsMs: to.inMilliseconds,
        told: true,
      );
      _retired.add(antes.segmentId);
    }
  }

  /// What the next call to the session-scoped ask throws, independent of `failWith` —
  /// a case needs a turn to succeed (so the halt is reached with a live session) and
  /// only the ask itself to fail, and `failWith` is shared by every guarded call.
  RoomFailure? askForAPersonFailsWith;

  final List<String> personAsksFor = [];

  Completer<void>? _holdingAskForAPerson;

  /// Holds the next session-scoped ask in flight, so a test can act — resolve the halt,
  /// change `askForAPersonFailsWith` — before the answer lands.
  void holdNextAskForAPerson() => _holdingAskForAPerson = Completer<void>();

  void finishHeldAskForAPerson() {
    _holdingAskForAPerson?.complete();
    _holdingAskForAPerson = null;
  }

  @override
  Future<RoomAnswer<void>> askForAPerson(String sessionId) async {
    if (_guard('askForAPerson') case final failure?) return failure;
    personAsksFor.add(sessionId);
    if (_forgot('askForAPerson', sessionId) case final gone?) {
      return gone;
    }
    final held = _holdingAskForAPerson;
    if (held != null) await held.future;
    final failure = askForAPersonFailsWith;
    if (failure != null) return failure;
    personsAsked++;
    // The route is what raises the blocking halt on the server: a double that only
    // counted the call answered the next state read as if nobody had asked.
    serverStatus = 'needs_person';
    serverHalt = HaltKind.blocking;
    return const Answered(null);
  }

  /// What the next call to `personArrived` throws, independent of `failWith` — a case
  /// needs the halt to stay reachable and only the arrival ping itself to fail.
  RoomFailure? personArrivedFailsWith;

  /// Every session id `personArrived` was called for, one entry per attempt.
  final List<String> personArrivedSessions = [];

  Completer<void>? _holdingPersonArrived;

  /// Holds the next arrival ping in flight, so a test can move the room before it lands.
  void holdNextPersonArrived() => _holdingPersonArrived = Completer<void>();

  void finishHeldPersonArrived() {
    _holdingPersonArrived?.complete();
    _holdingPersonArrived = null;
  }

  @override
  Future<RoomAnswer<void>> personArrived(String sessionId) async {
    if (_guard('personArrived') case final failure?) return failure;
    if (_forgot('personArrived', sessionId) case final gone?) {
      return gone;
    }
    personArrivedSessions.add(sessionId);
    final held = _holdingPersonArrived;
    if (held != null) await held.future;
    return personArrivedFailsWith ?? const Answered(null);
  }

  /// Every device id the device-scoped ask was made for, one entry per attempt —
  /// including one that is about to fail, the way `calls` tracks `askForAPerson`.
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

  Duration? takeLandsAfter;

  Duration? takeLandsInRealTime;

  Duration? aHeldTakeAnswersAfter;

  @override
  Future<RoomAnswer<String>> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
  }) async {
    if (_guard('sendTake') case final failure?) return failure;
    if (_forgot('sendTake', sessionId) case final gone?) {
      return gone;
    }
    final wait = takeLandsAfter;
    if (wait != null) await Future<void>.delayed(wait);
    final onTheClock = takeLandsInRealTime;
    if (onTheClock != null) {
      await Zone.root.run(() => Future<void>.delayed(onTheClock));
    }
    if (scope == holdTakeScope) {
      _reachedTakeHold?.complete();
      await _holdingTake?.future;
      final answersAfter = aHeldTakeAnswersAfter;
      if (answersAfter != null) await Future<void>.delayed(answersAfter);
    }
    if (takeAnswersFirst.isNotEmpty) return takeAnswersFirst.removeAt(0);
    if (refuseTake == '$kind/$scope') return Refused(refuseTakeCode);
    if (unreachableTake == '$kind/$scope') {
      return const NetworkFailed('sem rede');
    }
    takesKept.add('$kind/$scope');
    takesReceived.add((kind: kind, scope: scope, chunkIndex: chunkIndex));
    takePasses.add(passNumber);
    final id = 'gravacao-${takeIds.length + 1}';
    takeIds.add(id);
    takes.add(
      TakeView(
        takeId: id,
        kind: kind,
        scope: scope,
        ordinal: kind == 'ensaio' ? chunkIndex : null,
        pass: passNumber,
      ),
    );
    takeAudio[id] = Uint8List.fromList(utf8.encode('áudio de $id'));
    return Answered(id);
  }

  @override
  Future<RoomAnswer<TurnResult>> sendTurn(
    String sessionId,
    File audio, {
    required String turnId,
    String? clientTiming,
    CutPoint? cut,
  }) async {
    if (_guard('sendTurn') case final failure?) return failure;
    if (_forgot('sendTurn', sessionId) case final gone?) {
      return gone;
    }
    sessionsSpokenTo.add(sessionId);
    clientTimingsSent.add(clientTiming);
    turnIdsSent.add(turnId);
    recordingsSent.add(audio.path);
    cutsSent.add(cut);
    turnsSent++;
    return _theTurnAnswers(sessionId, turnId);
  }

  /// Whether a turn is answered with nothing to play: no url and no fixed line.
  bool answersTurnsWithoutAReply = false;

  TurnResult _turn(String sessionId) => TurnResult(
    sessionId: sessionId,
    audioUrl: answersTurnsWithoutAReply || fixedLine.isNotEmpty ? '' : turnoUrl,
    fixedLine: answersTurnsWithoutAReply ? '' : fixedLine,
    transcript: 'a equipe falou',
    peerCue: peerCue,
    usedFailSafe: turnsAreCanned,
    degraded: turnsAreDegraded,
    coverage: silentAboutCoverage ? null : nextCoverage,
    done: done,
    moment: nextMoment,
    turnId: turnIdInResponse ?? 'turno-fake-${++_turnCount}',
    classificationPending: classificationPending,
    bridgeMode: bridgeMode,
  );

  @override
  Future<RoomAnswer<BackTranslationChunk>> sendChunk(
    String sessionId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
    required String idempotencyKey,
  }) async {
    chunkKeys.add(idempotencyKey);
    if (_guard('sendChunk') case final failure?) return failure;
    if (_forgot('sendChunk', sessionId) case final gone?) {
      return gone;
    }
    if (chunkAnswersFirst.isNotEmpty) return chunkAnswersFirst.removeAt(0);
    final kept = forgetsTheKeys ? null : _chunksKept[idempotencyKey];
    if (kept != null) return kept;
    final answer = await _sendChunk(audio, takeId: takeId, from: from, to: to);
    if (answer case Answered() || Refused()) {
      _chunksKept[idempotencyKey] = answer;
    }
    return answer;
  }

  Future<RoomAnswer<BackTranslationChunk>> _sendChunk(
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) async {
    final refusal = failChunkWith;
    if (refusal != null) return refusal;
    if (_replacedTakes.contains(takeId)) {
      final wait = replacedTakeRefusalAfter;
      if (wait != null) await Future<void>.delayed(wait);
      return const Refused(
        RefusalCode.stretchNoLongerCounts,
        'This stretch no longer counts',
      );
    }
    chunksSent++;
    chunkSpans.add('${from.inMilliseconds}-${to.inMilliseconds}');
    chunkTakes.add(takeId);
    chunkFiles.add(audio.path);
    segments.add(
      SegmentView(
        segmentId: 'trecho-${segments.length + 1}',
        takeId: takeId,
        startsMs: from.inMilliseconds,
        endsMs: to.inMilliseconds,
      ),
    );
    final held = _holdingChunk;
    if (held != null) await held.future;
    return Answered(
      BackTranslationChunk(
        frase:
            fraseDaProximaFrase ??
            segments.where((segment) => segment.told).length,
      ),
    );
  }

  Completer<void>? _holdingChunk;

  Completer<void>? _holdingVerdict;

  void holdNextVerdict() => _holdingVerdict = Completer<void>();

  void finishHeldVerdict() {
    _holdingVerdict?.complete();
    _holdingVerdict = null;
  }

  int? fraseDaProximaFrase;

  /// Holds a stretch's delivery in flight, so a test can see the room still thinking.
  void holdNextChunk() => _holdingChunk = Completer<void>();

  void finishHeldChunk() {
    _holdingChunk?.complete();
    _holdingChunk = null;
  }

  String? _oQueOAnalistaAponta() {
    final place = verdictFindingPlace;
    if (place == null) return verdictFindingSegmentId;
    return place >= 0 && place < segments.length
        ? segments[place].segmentId
        : null;
  }

  @override
  Future<RoomAnswer<BackTranslationVerdict>> finishBackTranslation(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) async {
    duranteOVeredito?.call();
    final segurado = _holdingVerdict;
    if (segurado != null) await segurado.future;
    final refusal = failFinishWith;
    if (refusal != null) return refusal;
    playedByTakeSent.add([for (final parte in playedByTake) parte.toJson()]);
    if (_guard('finishBackTranslation') case final failure?) return failure;
    if (_forgot('finishBackTranslation', sessionId) case final gone?) {
      return gone;
    }
    final recusa = verdictRefusal;
    if (recusa != null) {
      return Answered(
        BackTranslationVerdict(
          audioUrl: '',
          fixedLine: verdictFixedLine,
          checked: false,
          findingSegmentId: null,
          untoldSegmentId: verdictUntoldSegmentId,
          unheardTakeIds: verdictUnheardTakeIds,
          findingsRemaining: 0,
          usedFailSafe: false,
          refusal: recusa,
        ),
      );
    }
    final String linha;
    if (verdictUntoldTakeIds.isNotEmpty) {
      linha = falaDaParteNaoContada;
    } else if (verdictUnheardTakeIds.isNotEmpty) {
      linha = falaDaParteNaoOuvida;
    } else {
      linha = falaDoVeredito;
    }
    return Answered(
      BackTranslationVerdict(
        audioUrl: linha,
        fixedLine: '',
        checked: verdictChecked,
        findingSegmentId: _oQueOAnalistaAponta(),
        untoldSegmentId: verdictUntoldSegmentId,
        unheardTakeIds: verdictUnheardTakeIds,
        untoldTakeIds: verdictUntoldTakeIds,
        findings: verdictFindings,
        findingsRemaining: verdictHasFinding ? 1 : 0,
        usedFailSafe: verdictUsedFailSafe,
        checkAt: verdictCheckAt,
        namedNuance: verdictNamedNuance,
      ),
    );
  }

  /// Every report the listen door was sent, in order, as [playedByTakeSent] keeps the
  /// check's.
  final List<List<Map<String, Object?>>> listeningReports = [];

  /// The parts the listen door answers as still unheard. Null is an older room, whose
  /// answer names none.
  List<String>? listeningUnheardTakeIds;

  RoomFailure? failListeningWith;

  @override
  Future<RoomAnswer<List<String>?>> reportTheListening(
    String sessionId, {
    required List<PlayedTake> playedByTake,
  }) async {
    listeningReports.add([for (final parte in playedByTake) parte.toJson()]);
    final falha = failListeningWith;
    if (falha != null) return falha;
    if (!reachable) return const NetworkFailed('sem rede');
    return Answered(listeningUnheardTakeIds);
  }

  final List<String> heardStamps = [];

  RoomFailure? failHeardWith;

  @override
  Future<RoomAnswer<void>> reportTheVerdictHeard(
    String sessionId,
    String at,
  ) async {
    heardStamps.add(at);
    return failHeardWith ?? const Answered<void>(null);
  }

  final List<String> restartsAsked = [];

  RoomFailure? failRestartWith;

  List<SegmentView> standingAfterRestart = const [];

  @override
  Future<RoomAnswer<List<SegmentView>>> startTheTranslationOver(
    String sessionId,
  ) async {
    restartsAsked.add(sessionId);
    final refusal = failRestartWith;
    if (refusal != null) return refusal;
    _retired.addAll(segmentIds);
    segments
      ..clear()
      ..addAll(standingAfterRestart);
    retroSoFar = null;
    awaitingSegmentId = null;
    return Answered(_numbered);
  }

  /// Every session the team's approval was sent for, in order.
  final List<String> releasesAsked = [];

  /// What the room answers the approval with. A second approval of unchanged content
  /// comes back as the release already there, which is the same answer.
  ApprovalAnswer release = const ApprovalAnswer(
    releaseId: 'solta-1',
    version: 1,
  );

  /// Which holes this room says stand between the passage and its release. Empty is a room
  /// that refused nothing, which is what a mint looks like from here.
  List<String> releaseBlockers = const [];

  /// Which current parts this room says carry nobody's words, when `untold_part` is among
  /// the holes above. Its own field, as on the wire, and read only for its own blocker.
  List<String> releaseUntoldTakeIds = const [];

  /// Which parts this room says the team's report does not cover, when
  /// `playback_did_not_cover_the_clip` is among them.
  List<String> releaseUnheardTakeIds = const [];

  /// Which stretch this room says was recorded and never told back, when `untold_stretch`
  /// is among them.
  String? releaseUntoldSegmentId;

  Completer<void>? _holdingState;

  /// Holds a read of the room's state in flight, so a test can press again while the room
  /// is still reading the stretches' names back.
  void holdNextState() => _holdingState = Completer<void>();

  int _readsToHold = 0;
  final List<Completer<void>> heldReads = [];

  void holdTheNextRead() => _readsToHold++;

  void answerHeldRead(int which) => heldReads[which].complete();

  void finishHeldState() {
    _holdingState?.complete();
    _holdingState = null;
  }

  Completer<void>? _holdingRelease;

  /// Holds the approval in flight, so a test can press again before the answer lands.
  void holdNextRelease() => _holdingRelease = Completer<void>();

  void finishHeldRelease() {
    _holdingRelease?.complete();
    _holdingRelease = null;
  }

  /// What the approval throws, independent of `failWith`, which every guarded call
  /// shares: a refused release has to reach a room whose call for a person still works,
  /// and that call is the whole of what the case measures.
  RoomFailure? failReleaseWith;

  @override
  Future<RoomAnswer<ApprovalAnswer>> approveRelease(String sessionId) async {
    if (_guard('approveRelease') case final failure?) return failure;
    if (_forgot('approveRelease', sessionId) case final gone?) {
      return gone;
    }
    releasesAsked.add(sessionId);
    final refusal = failReleaseWith;
    if (refusal != null) return refusal;
    final held = _holdingRelease;
    if (held != null) await held.future;
    if (releaseBlockers.isEmpty) return Answered(release);
    return Answered(
      ApprovalAnswer(
        blockers: releaseBlockers,
        untoldTakeIds: releaseUntoldTakeIds,
        unheardTakeIds: releaseUnheardTakeIds,
        untoldSegmentId: releaseUntoldSegmentId,
      ),
    );
  }

  bool get coverageHasListener => _coverage.hasListener;

  @override
  void dispose() => _coverage.close();
}

class FakeNetwork implements ConnectivityService {
  @override
  http.Client get client => throw UnimplementedError();

  final StreamController<void> _returned = StreamController<void>.broadcast();
  bool reachable = true;
  bool radioSeesNothing = false;
  int checks = 0;
  int answeredChecks = 0;
  Completer<void>? _holdingCheck;
  Completer<void>? _heldCheck;

  void holdNextCheck() => _holdingCheck = Completer<void>();

  void finishHeldCheck() {
    _heldCheck?.complete();
    _heldCheck = null;
  }

  @override
  Future<RoomReach> reachRoom() async {
    checks++;
    final held = _holdingCheck;
    if (held != null) {
      _holdingCheck = null;
      _heldCheck = held;
      await held.future;
    }
    answeredChecks++;
    if (reachable) return RoomReach.fine;
    return radioSeesNothing ? RoomReach.noNetwork : RoomReach.roomSilent;
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
      _keep(deviceId: deviceId);

  @override
  Future<void> rememberTeam(TeamLink team) async => _keep(team: team);

  @override
  Future<void> rememberCredential(
    String credential, {
    required String forDevice,
  }) async => _keep(credential: credential);

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
  String? _keptFor;
  bool unavailable = false;
  bool keepUnavailable = false;

  Completer<bool>? _holdingKeep;
  Completer<bool>? _heldKeep;

  void holdNextKeep() => _holdingKeep = Completer<bool>();

  bool get keepHeld => _heldKeep != null;

  /// Lets the held `keep` go: written, or failing the way a Keychain that refuses
  /// mid-write does.
  void finishHeldKeep({bool unavailable = false}) {
    _heldKeep?.complete(unavailable);
    _heldKeep = null;
  }

  @override
  Future<String?> read() async {
    if (unavailable) throw const VaultUnavailable();
    return _credential;
  }

  /// [forDevice] left out keeps a credential the way a vault from before the device id
  /// existed held one.
  @override
  Future<void> keep(String credential, {String? forDevice}) async {
    if (unavailable || keepUnavailable) throw const VaultUnavailable();
    final held = _holdingKeep;
    _holdingKeep = null;
    if (held != null) {
      _heldKeep = held;
      if (await held.future) throw const VaultUnavailable();
    }
    _credential = credential;
    _keptFor = forDevice;
  }

  @override
  Future<String?> keptFor() async {
    if (unavailable) throw const VaultUnavailable();
    return _keptFor;
  }

  @override
  Future<void> forget() async {
    if (unavailable) throw const VaultUnavailable();
    _credential = null;
    _keptFor = null;
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

  final RecordingRepository? recordings;

  FakeTakeQueue({required this.room, this.recordings});

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final entry = PendingTake(
      id: '${_minted++}',
      path: audio.path,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
      original: kind == sceneTakeKind
          ? p.basenameWithoutExtension(audio.path)
          : null,
    );
    rows.add(entry);
    return entry;
  }

  @override
  Stream<void> get fallsOnTheNetwork => const Stream.empty();

  final StreamController<String> _sessionsGone =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get sessionsGone => _sessionsGone.stream;

  @override
  Future<void> discardTheSession(String sessionId) async =>
      rows.removeWhere((entry) => entry.sessionId == sessionId);

  final Map<String, SceneRehearsalRecord> _keptScenes = {};

  @override
  Future<SceneRehearsalRecord?> keepTheScene(String row) async {
    final at = rows.indexWhere((entry) => entry.id == row);
    for (var i = 0; i < at; i++) {
      final entry = rows[i];
      if (entry.kind == sceneTakeKind &&
          entry.sessionId == rows[at].sessionId &&
          !entry.exhausted) {
        rows[i] = entry.dueNow();
      }
    }
    await flush();
    return keptSceneOf(row);
  }

  @override
  SceneRehearsalRecord? keptSceneOf(String row) => _keptScenes[row];

  @override
  Future<void> dueAgain(String row) async {
    final at = rows.indexWhere((entry) => entry.id == row);
    if (at >= 0) rows[at] = rows[at].dueNow();
  }

  @override
  Future<PendingTake?> sceneWaitingIn(String sessionId) async => rows
      .where(
        (entry) =>
            entry.kind == sceneTakeKind &&
            !entry.stored &&
            !entry.exhausted &&
            entry.sessionId == sessionId,
      )
      .lastOrNull;

  @override
  Future<int> flush({bool withTheCodeless = false}) async {
    var sent = 0;
    for (final id in [for (final entry in rows) entry.id]) {
      final at = rows.indexWhere((entry) => entry.id == id);
      if (at < 0) continue;
      final entry = rows[at];
      if (entry.stored || entry.kind == sentenceKind) continue;
      if (entry.kind == sceneTakeKind) {
        if (entry.exhausted) continue;
        switch (await room.keepSceneRehearsal(
          entry.sessionId,
          File(entry.path),
          scene: entry.scene,
        )) {
          case Answered(:final value):
            _keptScenes[entry.id] = value;
            final held = entry.original == null
                ? null
                : await recordings?.heldAs(entry.original!);
            if (held != null) {
              await recordings?.keepAs(held, 'cena-${value.rehearsalId}');
            }
            rows.removeAt(rows.indexWhere((row) => row.id == entry.id));
            sent++;
          case SessionGone():
            await discardTheSession(entry.sessionId);
            _sessionsGone.add(entry.sessionId);
          case NetworkFailed():
            _writeBack(entry.copyWith(waits: entry.waits + 1));
          case Refused(:final code):
            _writeBack(
              entry.copyWith(attempts: takeUploadAttempts, refusal: code),
            );
        }
        continue;
      }
      switch (await room.sendTake(
        entry.sessionId,
        File(entry.path),
        kind: entry.kind,
        scope: entry.scope,
        passNumber: entry.passNumber,
        chunkIndex: entry.chunkIndex,
      )) {
        case Answered(value: final landed):
          _writeBack(entry.copyWith(takeId: landed, stored: true));
          sent++;
        case SessionGone():
          await discardTheSession(entry.sessionId);
          _sessionsGone.add(entry.sessionId);
        case RoomFailure():
          _writeBack(entry.copyWith(attempts: entry.attempts + 1));
      }
    }
    return sent;
  }

  void _writeBack(PendingTake updated) {
    final at = rows.indexWhere(
      (entry) => entry.id == updated.id && entry.kind == updated.kind,
    );
    if (at >= 0) rows[at] = updated;
  }

  /// Whether the room has stopped naming what it stored: the take is kept and sent,
  /// and the name that should come back for it never does.
  bool forgetsNames = false;

  @override
  Future<String?> takeIdOf(String row) async {
    if (forgetsNames) return null;
    for (final entry in rows) {
      if (entry.id == row) return entry.takeId;
    }
    return null;
  }

  @override
  Future<List<PendingTake>> entries() async => List.of(rows);

  @override
  Future<List<PendingTake>> pending() async => [
    for (final entry in rows)
      if (!entry.stored) entry,
  ];

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
  }) async => {
    for (final entry in rows)
      if (!entry.stored && entry.kind == kind && entry.sessionId == sessionId)
        entry.scope,
  };

  /// How many takes were still unsent each time the room counted, in order.
  final List<int> unsentAtEachTally = [];

  @override
  Future<OutboxTally> tally({required String? sessionId}) async {
    unsentAtEachTally.add(rows.where((entry) => !entry.stored).length);
    final held = _armed;
    _armed = null;
    if (held != null) _holding = held;
    // Nenhum await antes daqui: os números precisam ser tomados no mesmo turno
    // síncrono em que a espera é armada, do jeito que unsentScopesOf já fazia —
    // um await entre as duas coisas muda quando a leitura vê a fila, não só
    // quando ela responde.
    final result = (
      parts: const <String, PartFact>{},
      due: Duration.zero,
      stranded: false,
      unsentTakes: [
        for (final entry in rows)
          if (!entry.stored &&
              entry.kind == 'ensaio' &&
              entry.sessionId == sessionId)
            entry,
      ].length,
      unsentChunks: [
        for (final entry in rows)
          if (!entry.stored &&
              entry.kind == 'retro' &&
              entry.sessionId == sessionId)
            entry,
      ].length,
      unsentTakeScopes: {
        for (final entry in rows)
          if (!entry.stored &&
              entry.kind == 'ensaio' &&
              entry.sessionId == sessionId)
            entry.scope,
      },
    );
    if (held != null) await held.future;
    return result;
  }

  @override
  Future<PendingTake?> sentenceHeldIn(String sessionId) async => rows
      .where((row) => row.kind == sentenceKind && row.sessionId == sessionId)
      .lastOrNull;

  @override
  Future<void> withdraw(PendingTake row) async {
    rows.removeWhere(
      (entry) => !entry.stored && entry.id == row.id && entry.kind == row.kind,
    );
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

Future<void> theRoomNamesTheParts(
  WidgetTester tester,
  ProviderContainer container, {
  required int parts,
  Duration limit = const Duration(seconds: 10),
}) => waitFor(
  'a sala nomear as partes ($parts)',
  () {
    final kept = container.read(salaSessionProvider).partes;
    return kept.length == parts && kept.every((part) => part.takeId != null);
  },
  limit: limit,
  step: () => letTheRehearsalReachTheRoom(tester),
);

Future<void> theClipOpens(SalaHarness harness) =>
    waitFor('o clipe abrir', () => harness.playback.open);

Future<void> theRoomRefusesTheGuardedCopy(SalaHarness harness) => waitFor(
  'a sala recusar a cópia de reserva da tradução',
  () async => (await harness.takes.entries()).any(
    (entry) => entry.kind == 'retro' && entry.refusal != null,
  ),
);

Future<void> confirmarATraducao(ProviderContainer container) async {
  final sala = container.read(salaSessionProvider.notifier);
  sala.retroTap();
  await waitFor(
    'a tradução ficar pendente',
    () => container.read(salaSessionProvider).btTraducaoPendente != null,
  );
  await sala.confirmarTraducao();
}

Future<void> fecharACaptura(ProviderContainer container) async {
  container.read(salaSessionProvider.notifier).retroTap();
  await waitFor('a captura fechar', () {
    final fase = container.read(salaSessionProvider).btPhase;
    return fase != BtPhase.capturing && fase != BtPhase.thinking;
  });
}

Future<void> confirmarATraducaoNaTela(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final sala = container.read(salaSessionProvider.notifier);
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 300));
  expect(
    container.read(salaSessionProvider).btTraducaoPendente,
    isNotNull,
    reason: 'o segundo toque deixa a tradução pendente',
  );
  await sala.confirmarTraducao();
}

class SalaHarness {
  final Directory takesHome;

  /// In memory unless the test hands it a ledger on disk, for widget tests, whose binding
  /// never lets real IO finish. A relaunch hands it on.
  final CurrentSessionLedger currentSession;

  /// Everything that made or stopped a sound, in the order it happened: `playback:play`,
  /// `playback:pause`, `playback:stop`, `voice:line`, `voice:asset`, `voice:stop`,
  /// `recorder:start`, `recorder:discard`. A gesture that moves the room has to silence
  /// it *before* its own sound, and an order is the only way to read that without one
  /// double reading another.
  final List<String> sounds = [];
  late final FakeVoice voice = FakeVoice(sounds: sounds);
  final FacilitatorVoiceService? voiceService;
  late final FakeRecorder recorder = FakeRecorder(sounds: sounds);
  late final FakePlayback playback = FakePlayback(sounds: sounds);
  final FakeInbox inbox;
  final FakeRoom room;
  final FakeNetwork network = FakeNetwork();

  final ConnectivityService? connectivity;
  final FakeScreenAwake awake = FakeScreenAwake();
  final FakeLinkedTeam vinculo;
  final Duration settleDelay;
  final bool watchesWithoutAHalt;
  final List<Duration> retryBackoff;
  final Duration? busyCeiling;
  final Duration lookAgain;
  final Duration? rewarm;
  final Duration? playbackCeiling;
  final Duration clipGrace;
  final CaptureGuard captureGuard;
  final Duration fimLinger;
  final Duration restartLapse;

  /// Whether the outbox keeps its rows in memory instead of on disk. Opt-in, for widget
  /// tests, whose binding never lets the real queue's IO finish.
  final bool filaEmMemoria;

  final String? lingua;

  /// The room language the team chose, shared by a relaunch so a choice outlives closing
  /// the app. Seeded from [lingua] unless the test hands one over.
  final RoomLanguageLedger roomLanguage;

  final LookLedger look;

  SalaHarness({
    this.voiceService,
    List<HandReply> replies = const [],
    RememberedLink linkedAs = const RememberedLink(
      deviceId: 'aparelho-1',
      team: TeamLink(projectId: 'equipe-1'),
    ),
    this.linkPoll,
    this.settleDelay = const Duration(milliseconds: 60),
    this.watchesWithoutAHalt = false,
    this.retryBackoff = const [Duration(milliseconds: 20)],
    this.connectivity,
    this.busyCeiling,
    this.lookAgain = const Duration(seconds: 2),
    this.rewarm,
    this.playbackCeiling,
    this.clipGrace = const Duration(seconds: 10),
    this.captureGuard = const CaptureGuard(
      minDuration: Duration.zero,
      minBytes: 1,
    ),
    this.fimLinger = const Duration(seconds: 30),
    this.restartLapse = const Duration(seconds: 6),
    this.filaEmMemoria = false,
    this.lingua = testLanguage,
    this.emAbertoNoDisco,
    this.inboxService,
    this.inboxWatch,
    FakeRoom? room,
    this.takesOverride,
    Directory? takesHome,
    CurrentSessionLedger? currentSession,
    RoomLanguageLedger? roomLanguage,
    LookLedger? look,
  }) : room = room ?? FakeRoom(),
       roomLanguage = roomLanguage ?? FakeRoomLanguageLedger(chosen: lingua),
       look = look ?? FakeLookLedger(),
       takesHome =
           takesHome ?? Directory.systemTemp.createTempSync('sala-tomadas'),
       currentSession = currentSession ?? FakeCurrentSessionLedger(),
       inbox = FakeInbox(replies: replies),
       vinculo = FakeLinkedTeam(remembered: linkedAs);

  final Duration? linkPoll;

  /// The real inbox, for the cases that need a server that can refuse or go away.
  final HandInboxRepository? inboxService;

  /// How often the open room looks for replies, when a case needs it other than the
  /// room's own.
  final Duration? inboxWatch;

  final FakeWorkInProgress emAberto = FakeWorkInProgress();

  /// The real ledger, for the tests that need a disk that can refuse.
  final WorkInProgress? emAbertoNoDisco;

  /// A queue built by the test itself, for a disk that needs to misbehave in a way
  /// none of the ordinary knobs reach.
  final TakeUploadQueue Function(
    FakeRoom room,
    Directory home,
    RecordingRepository Function() recordings,
  )?
  takesOverride;

  late final TakeUploadQueue takes =
      takesOverride?.call(room, takesHome, () => recorder) ??
      (filaEmMemoria
          ? FakeTakeQueue(room: room, recordings: recorder)
          : TakeUploadQueue(
              room: room,
              home: () async => takesHome,
              recordings: () => recorder,
            ));

  List<Override> get overrides => [
    facilitatorVoiceProvider.overrideWithValue(voiceService ?? voice),
    recordingRepositoryProvider.overrideWithValue(recorder),
    playbackRepositoryProvider.overrideWithValue(playback),
    handInboxRepositoryProvider.overrideWithValue(inboxService ?? inbox),
    roomRepositoryProvider.overrideWithValue(room),
    takeUploadQueueProvider.overrideWithValue(takes),
    workInProgressProvider.overrideWithValue(emAbertoNoDisco ?? emAberto),
    currentSessionLedgerProvider.overrideWithValue(currentSession),
    roomLanguageLedgerProvider.overrideWithValue(roomLanguage),
    lookLedgerProvider.overrideWithValue(look),
    connectivityServiceProvider.overrideWithValue(connectivity ?? network),
    linkedTeamProvider.overrideWithValue(vinculo),
    linkPollIntervalProvider.overrideWithValue(linkPoll),
    screenAwakeProvider.overrideWithValue(awake),
    roomPollDelayProvider.overrideWithValue(settleDelay),
    watchesWithoutAHaltProvider.overrideWithValue(watchesWithoutAHalt),
    coverageFallbackDelayProvider.overrideWithValue(settleDelay),
    roomRetryBackoffProvider.overrideWithValue(retryBackoff),
    busyStateCeilingProvider.overrideWithValue(busyCeiling),
    lookAgainIntervalProvider.overrideWithValue(lookAgain),
    connectionRewarmIntervalProvider.overrideWithValue(rewarm),
    playbackCeilingProvider.overrideWithValue(playbackCeiling),
    clipGraceProvider.overrideWithValue(clipGrace),
    captureGuardProvider.overrideWithValue(captureGuard),
    fimLingerProvider.overrideWithValue(fimLinger),
    restartLapseProvider.overrideWithValue(restartLapse),
    sceneEnvelopeReaderProvider.overrideWithValue(readTheEnvelope),
    if (inboxWatch case final every?)
      roomInboxWatchProvider.overrideWithValue(every),
  ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);

  Completer<void>? _envelopeHeld;

  /// Hold the take's loudness, the way a long take is still being read off the UI
  /// thread when the screen opens.
  void holdTheEnvelope() => _envelopeHeld = Completer<void>();

  void giveTheEnvelope() => _envelopeHeld?.complete();

  Future<Envelope?> readTheEnvelope(String path) async {
    await _envelopeHeld?.future;
    try {
      return envelopeOf(File(path).readAsBytesSync());
    } on FileSystemException {
      return null;
    }
  }
}

class SpeakingPlayer extends Fake implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast();
  Completer<void>? _sounding;
  Duration? lineLength = const Duration(milliseconds: 20);
  bool stopsBeforeTheEnd = false;
  ProcessingState _state = ProcessingState.ready;

  @override
  Duration position = Duration.zero;

  @override
  Duration? get duration => lineLength;

  @override
  ProcessingState get processingState => _state;

  bool get sounding => _sounding?.isCompleted == false;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  /// A load that never settles, for the line the player never manages to open.
  bool neverLoads = false;

  Completer<void>? _holdingLoad;

  /// Hold the next load until the test lets it go, for a line still opening.
  void holdNextLoad() => _holdingLoad = Completer<void>();

  void finishLoad() {
    _holdingLoad?.complete();
    _holdingLoad = null;
  }

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (neverLoads) return Completer<Duration?>().future;
    await _holdingLoad?.future;
    return lineLength;
  }

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    Duration? initialPosition,
    String? package,
    bool preload = true,
    dynamic tag,
  }) async => lineLength;

  StreamAudioSource? arriving;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    arriving = source as StreamAudioSource;
    return lineLength;
  }

  bool _playing = false;

  @override
  bool get playing => _playing;

  /// How many times the player was told to play.
  int plays = 0;

  @override
  Future<void> play() {
    plays++;
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

  void startSounding() {
    _states.add(PlayerState(true, _state));
  }

  void _quiet() {
    if (_sounding?.isCompleted == false) _sounding!.complete();
  }

  @override
  Future<void> dispose() async => _states.close();
}

class QueueHeldOnGiveUps extends TakeUploadQueue {
  QueueHeldOnGiveUps({
    required super.room,
    super.home,
    required super.recordings,
  });

  final Completer<void> asking = Completer<void>();
  final Completer<void> answer = Completer<void>();

  @override
  Future<List<PendingTake>> giveUps() async {
    if (!asking.isCompleted) asking.complete();
    await answer.future;
    return super.giveUps();
  }
}

/// A disk that refuses the withdraw's own write, the way a full one would.
class QueueWithdrawThrows extends TakeUploadQueue {
  QueueWithdrawThrows({
    required super.room,
    super.home,
    required super.recordings,
  });

  @override
  Future<void> withdraw(PendingTake row) async =>
      throw const FileSystemException('disco cheio');
}

class QueueThatDiscardsLate extends TakeUploadQueue {
  QueueThatDiscardsLate({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration? discardsAfter;

  @override
  Future<void> discardTheSession(String sessionId) async {
    final wait = discardsAfter;
    if (wait != null) await Future<void>.delayed(wait);
    await super.discardTheSession(sessionId);
  }
}

class QueueWhoseTranslationLandsLate extends TakeUploadQueue {
  QueueWhoseTranslationLandsLate({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration? landsAfter;
  bool translationLanded = false;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final wait = landsAfter;
    if (kind == 'retro' && wait != null) await Future<void>.delayed(wait);
    final row = await super.enqueue(
      audio,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
    if (kind == 'retro') translationLanded = true;
    return row;
  }
}

class QueueThatFinishesLate extends TakeUploadQueue {
  QueueThatFinishesLate({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration? answersAfter;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final row = await super.enqueue(
      audio,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
    final wait = answersAfter;
    if (kind == 'retro' && wait != null) await Future<void>.delayed(wait);
    return row;
  }
}

class QueueThatFlushesLate extends TakeUploadQueue {
  QueueThatFlushesLate({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration? flushesAfter;
  int flushing = 0;

  @override
  Future<int> flush({bool withTheCodeless = false}) async {
    flushing++;
    try {
      final wait = flushesAfter;
      if (wait != null) await Future<void>.delayed(wait);
      return await super.flush(withTheCodeless: withTheCodeless);
    } finally {
      flushing--;
    }
  }
}

class QueueThatEnqueuesLate extends TakeUploadQueue {
  QueueThatEnqueuesLate({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration? enqueuesAfter;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final wait = enqueuesAfter;
    if (wait != null) await Future<void>.delayed(wait);
    return super.enqueue(
      audio,
      sessionId: sessionId,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }
}

class LedgerThatReadsLate extends CurrentSessionLedger {
  LedgerThatReadsLate({super.home});

  Duration? readsAfter;

  @override
  Future<CurrentSession?> read() async {
    final wait = readsAfter;
    if (wait != null) await Future<void>.delayed(wait);
    return super.read();
  }
}
