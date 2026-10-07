// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'room_answer.dart';
import 'room_repository.dart';

const _libraryFolder = 'voz';
const _clipsKept = 60;
const _lineGrace = Duration(seconds: 8);
const _unknownLineCeiling = Duration(seconds: 90);
const _staleStagingAge = Duration(minutes: 10);
const _slowestBytesPerSecond = 4000;
const _restartsAllowed = 2;

class FacilitatorVoiceService {
  final Future<http.StreamedResponse> Function(
    String url, {
    int? from,
    String? ifRange,
  })
  _open;
  final bool _playsAsItArrives;
  final Future<Directory> Function() _libraryDir;
  Future<Directory>? _dir;
  AudioPlayer? _opened;
  bool _lineOpen = false;
  bool _lineOnDisk = false;
  final Duration _grace;
  final Duration _loadCeiling;
  Future<void> _speaking = Future<void>.value();
  final Map<String, _ArrivingClip> _arriving = {};

  FacilitatorVoiceService({
    required this._open,
    this._playsAsItArrives = true,
    Future<Directory> Function()? libraryDir,
    AudioPlayer? player,
    Duration? lineGrace,
    Duration? loadCeiling,
  }) : _libraryDir = libraryDir ?? _defaultLibraryDir,
       _opened = player,
       _grace = lineGrace ?? _lineGrace,
       _loadCeiling = loadCeiling ?? _unknownLineCeiling;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  /// How far into the line the player is, once the line is open: until then the player
  /// still holds the line before it.
  Duration get linePosition =>
      _lineOpen ? _opened?.position ?? Duration.zero : Duration.zero;

  /// How long the line is, only when the player opened it from a file on disk: a line
  /// streamed as it arrives has only an estimate, which must never pass for its length.
  Duration? get lineLength =>
      _lineOpen && _lineOnDisk ? _opened?.duration : null;

  Future<Directory> get _resolvedDir {
    final dir = _dir ??= _libraryDir();
    return dir.catchError((Object error, StackTrace stackTrace) {
      _dir = null;
      return Future<Directory>.error(error, stackTrace);
    });
  }

  Future<bool> play(String url, {void Function()? onSoundStart}) {
    if (url.isEmpty) return Future.value(false);
    _lineOpen = false;
    return _afterTheCurrentLine(() async {
      final clip = _clipArriving(url);
      final kept =
          await clip.opened ?? (_playsAsItArrives ? null : await clip.file);
      _lineOnDisk = kept != null;
      return _sayItWhole(
        kept != null
            ? () => _player.setFilePath(kept.path)
            : () async {
                clip._heard = null;
                return await _player.setAudioSource(clip) ?? clip._length;
              },
        onSoundStart: () {
          unawaited(_settled(clip).then((_) => _tidyLibrary()));
          onSoundStart?.call();
        },
      );
    });
  }

  Future<bool> fetch(String url) async {
    if (url.isEmpty) return false;
    try {
      await clipFor(url);
      return true;
    } on Exception {
      return false;
    }
  }

  /// Whether the line has sound to give: its first bytes, or the whole file with
  /// streaming switched off.
  ///
  /// The room turns `speaking` on this. An answer that has opened says only that the
  /// room answered — its body can still be seconds away on a field link — and the circle
  /// rippled over that silence, which is exactly what `thinking` exists to cover.
  Future<bool> ready(String url) async {
    if (url.isEmpty) return false;
    try {
      final clip = _clipArriving(url);
      if (await clip.opened == null) {
        await (_playsAsItArrives ? clip.firstBytes : clip.file);
      }
      return true;
    } on Exception {
      return false;
    }
  }

  /// Whether this line is already on the tablet, so nothing has to be waited for.
  ///
  /// A replay is not the room thinking — it already holds the words. Passing through the
  /// thinking face on the way to repeating something it has in hand made the circle change
  /// colour twice for a line that starts instantly.
  Future<bool> holds(String url) async {
    if (url.isEmpty) return false;
    try {
      final dir = await _resolvedDir;
      final file = File(p.join(dir.path, '${_nameFor(url)}.mp3'));
      return file.existsSync() && file.lengthSync() > 0;
    } on Exception {
      return false;
    }
  }

  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    _lineOpen = false;
    return _afterTheCurrentLine(() {
      _lineOnDisk = false;
      return _sayItWhole(
        () => _player.setAsset(assetPath),
        onSoundStart: onSoundStart,
      );
    });
  }

  Future<bool> _afterTheCurrentLine(Future<bool> Function() speak) {
    final spoken = _speaking.then((_) async {
      try {
        return await speak();
      } on RoomFailure {
        rethrow;
      } on Exception {
        return false;
      }
    });
    _speaking = spoken.then((_) {}, onError: (_) {});
    return spoken;
  }

  /// Whether the line played to its end.
  ///
  /// just_audio completes the future of `play()` when the sound stops — at the end of the
  /// line, but equally on a pause, on a stop, or when another app takes the output. Reading
  /// that as success let a line cut short clear every health counter the room keeps, and
  /// pushed the team on to answer a question they were never asked. A stop the team asked
  /// for is an interruption, which the room counts as heard before this answers.
  Future<bool> _sayItWhole(
    Future<Duration?> Function() load, {
    void Function()? onSoundStart,
  }) async {
    // The load has a ceiling of its own. Since the room stopped judging a line it is
    // speaking (the voice is the judge), a `setFilePath` that never settled would leave
    // `play` hanging and the team in front of a circle that never speaks, with nobody
    // called. The unknown-length ceiling is the honest bound: nothing is known yet.
    // Injectable only so a test can prove the bound without waiting ninety seconds.
    final Duration? length;
    try {
      length = await () async {
        await _player.stop();
        return load();
      }().timeout(_loadCeiling + _grace);
    } on TimeoutException {
      await _giveUp();
      return false;
    }
    if (length == Duration.zero) return false;
    _lineOpen = true;
    StreamSubscription<PlayerState>? soundStart;
    if (onSoundStart != null) {
      soundStart = _player.playerStateStream
          .where((playerState) => playerState.playing)
          .listen((_) {
            onSoundStart();
            soundStart?.cancel();
          });
    }
    try {
      await _player.play().timeout((length ?? _unknownLineCeiling) + _grace);
    } on TimeoutException {
      await _giveUp();
      return false;
    } finally {
      await soundStart?.cancel();
    }
    return _player.processingState == ProcessingState.completed;
  }

  /// The recovery has a bound too. It runs against the very player that just failed to
  /// open or finish a file, and a stop that wedges there would keep the line from ever
  /// being reported as not heard.
  Future<void> _giveUp() async {
    try {
      await stop().timeout(_grace);
    } on TimeoutException {
      return;
    }
  }

  /// The line on disk, downloading it once however many callers ask at the same moment.
  ///
  /// The opening fetches its second movement while the first is still being spoken, and
  /// two downloads of one line wrote the same staging file and renamed it out from under
  /// each other. The loser threw, the throw was swallowed as a line that would not play,
  /// and the room went quiet between two breaths of the same sentence.
  Future<File> clipFor(String url) => _clipArriving(url).file;

  _ArrivingClip _clipArriving(String url) {
    final arriving = _arriving[url];
    if (arriving != null) return arriving;
    final clip = _ArrivingClip(_open, url, _loadCeiling + _grace);
    _arriving[url] = clip;
    clip.file = _bringItIn(url, clip);
    unawaited(
      clip.file
          .then<void>((_) {}, onError: clip._fail)
          .whenComplete(() => _arriving.remove(url)),
    );
    return clip;
  }

  Future<File> _fileFor(String url) async {
    final dir = await _resolvedDir;
    return File(p.join(dir.path, '${_nameFor(url)}.mp3'));
  }

  Future<File> _bringItIn(String url, _ArrivingClip clip) async {
    final file = await _fileFor(url);
    if (file.existsSync() && file.lengthSync() > 0) {
      unawaited(_touch(file));
      clip._kept(file);
      return file;
    }
    // Staged and renamed, like the take queue two files away. `writeAsBytes` truncates
    // first, so a kill mid-write left a short file that passes `length > 0` and is served
    // from then on: the room goes mute on that one line, and stays mute across restarts.
    final staging = File('${file.path}.novo');
    await staging.writeAsBytes(await clip._arrive(), flush: true);
    await staging.rename(file.path);
    return file;
  }

  String _nameFor(String url) => url.split('/').last;

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(clock.now());
    } on Exception {
      return;
    }
  }

  Future<void> _tidyLibrary() async {
    final dir = await _resolvedDir;
    await _dropOldestBeyondBudget(dir);
    await _sweepStaleStaging(dir);
  }

  Future<void> _sweepStaleStaging(Directory dir) async {
    try {
      final protected = _arriving.keys
          .map((url) => p.join(dir.path, '${_nameFor(url)}.mp3.novo'))
          .toSet();
      final novos = await dir
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.novo'))
          .cast<File>()
          .toList();
      final cutoff = clock.now().subtract(_staleStagingAge);
      for (final novo in novos) {
        if (protected.contains(novo.path)) continue;
        if ((await novo.stat()).modified.isBefore(cutoff)) {
          await novo.delete();
        }
      }
    } on Exception {
      return;
    }
  }

  Future<void> _dropOldestBeyondBudget(Directory dir) async {
    try {
      final clips = await dir
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.mp3'))
          .cast<File>()
          .toList();
      if (clips.length <= _clipsKept) return;
      final dated = await Future.wait(
        clips.map((clip) async => (clip, (await clip.stat()).modified)),
      );
      dated.sort((a, b) => a.$2.compareTo(b.$2));
      for (final entry in dated.take(dated.length - _clipsKept)) {
        await entry.$1.delete();
      }
    } on Exception {
      return;
    }
  }

  Future<void> stop() async {
    try {
      await _opened?.stop();
    } on Exception {
      return;
    }
  }

  Future<void> _settled(_ArrivingClip clip) =>
      clip.file.then((_) {}, onError: (_) {});

  Future<void> dispose() async {
    await _giveUp();
    await Future.wait(_arriving.values.map(_settled));
    await _opened?.dispose();
  }
}

class _ArrivingClip extends StreamAudioSource {
  final Future<http.StreamedResponse> Function(
    String url, {
    int? from,
    String? ifRange,
  })
  _open;
  final String _url;
  final Duration _stall;
  final _opened = Completer<File?>();
  final _firstBytes = Completer<void>();
  late final Future<File> file;
  Object? _broke;
  String? _etag;
  int _rendering = 0;
  int? _heard;
  Uint8List _bytes = Uint8List(0);
  int _received = 0;
  Completer<void> _arrival = Completer<void>();

  _ArrivingClip(this._open, this._url, this._stall) {
    _opened.future.ignore();
    _firstBytes.future.ignore();
  }

  Future<File?> get opened => _opened.future;

  Future<void> get firstBytes => _firstBytes.future;

  /// The longest the line can last, read off its size at the slowest bitrate a voice is
  /// plausibly sent at.
  ///
  /// It is the play ceiling of a line the platform cannot time, so it errs long. The clips
  /// are `mp3_44100_128` today, but the size says nothing of the rate: read at 128 kbps, a
  /// 60 s line sent at 64 kbps was given up at 38 s and reported unheard mid-sentence. Read
  /// at 32 kbps, a line that truly wedges is still bounded, only later; the grace is added
  /// on top as before.
  Duration get _length =>
      Duration(milliseconds: _bytes.length * 1000 ~/ _slowestBytesPerSecond);

  void _kept(File file) => _opened.complete(file);

  void _fail(Object error) {
    _broke = error;
    if (!_opened.isCompleted) _opened.completeError(error);
    if (!_firstBytes.isCompleted) _firstBytes.completeError(error);
    _wake();
  }

  void _firstBytesIn() {
    if (!_firstBytes.isCompleted) _firstBytes.complete();
  }

  /// The line, resumed across drops and started over when a resume cannot prove it is
  /// the same rendering.
  ///
  /// Progress is what bounds a resume, and a restart throws the progress away: against a
  /// room that answers every range with the whole clip, a link that keeps dropping pulled
  /// the MP3 again and again, and the line never arrived nor failed. Restarts get a count
  /// of their own, and past it the line gives up as a resume that brings nothing does.
  Future<Uint8List> _arrive() async {
    var response = await _open(_url);
    _begin(response);
    _opened.complete(null);
    var restarts = 0;
    while (true) {
      final before = _received;
      Object? drop;
      try {
        await for (final chunk in response.stream.timeout(_stall)) {
          _bytes.setRange(_received, _received + chunk.length, chunk);
          _received += chunk.length;
          _firstBytesIn();
          _wake();
        }
      } on TimeoutException {
        drop = const NetworkFailed('timeout');
      } on Exception catch (error) {
        drop = NetworkFailed('$error');
      }
      if (_received == _bytes.length) {
        _firstBytesIn();
        return _bytes;
      }
      final cut = drop ?? const Refused(RefusalCode.unreadable, 'fala cortada');
      if (_received == before) throw cut;
      final etag = _etag;
      response = await _open(_url, from: _received, ifRange: etag);
      if (_isTheRest(response, etag)) continue;
      if (restarts == _restartsAllowed) {
        unawaited(response.stream.listen(null).cancel());
        throw cut;
      }
      restarts++;
      if (response.statusCode == 206) {
        unawaited(response.stream.listen(null).cancel());
        response = await _open(_url);
      }
      _begin(response);
    }
  }

  /// Whether a resume answered with the rest of this rendering, and only the rest.
  ///
  /// The ETag says which rendering; only the size and the range say which bytes. A range
  /// implementation that ignored the offset answered 206 with the whole clip under the
  /// right ETag, and writing it after what had arrived ran past the end of the buffer — a
  /// `RangeError`, which no `on Exception` in the room catches. Anything else is started
  /// over, like a resume from another rendering.
  bool _isTheRest(http.StreamedResponse response, String? etag) {
    if (response.statusCode != 206 ||
        etag == null ||
        response.headers['etag'] != etag) {
      return false;
    }
    final range = response.headers['content-range'];
    return response.contentLength == _bytes.length - _received &&
        (range == null ||
            range == 'bytes $_received-${_bytes.length - 1}/${_bytes.length}');
  }

  void _begin(http.StreamedResponse response) {
    _bytes = Uint8List(
      response.contentLength ??
          (throw const Refused(RefusalCode.unreadable, 'fala sem tamanho')),
    );
    _received = 0;
    _etag = response.headers['etag'];
    _rendering++;
    _wake();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final until = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: until - from,
      offset: start,
      stream: _between(from, until),
      contentType: 'audio/mpeg',
    );
  }

  Stream<List<int>> _between(int from, int until) async* {
    var at = from;
    while (at < until) {
      final broke = _broke;
      if (broke != null) throw broke;
      if (_heard != null && _heard != _rendering) {
        throw const Refused(RefusalCode.unreadable, 'a fala mudou no meio');
      }
      if (_received > at) {
        _heard ??= _rendering;
        final upto = min(_received, until);
        yield Uint8List.sublistView(_bytes, at, upto);
        at = upto;
      } else {
        await _arrival.future;
      }
    }
  }

  void _wake() {
    final arrival = _arrival;
    _arrival = Completer<void>();
    arrival.complete();
  }
}

Future<Directory> _defaultLibraryDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, _libraryFolder)).create(recursive: true);
}

final voicePlaysAsItArrivesProvider = Provider<bool>((ref) => true);

final facilitatorVoiceProvider = Provider<FacilitatorVoiceService>((ref) {
  final service = FacilitatorVoiceService(
    open: ref.read(roomRepositoryProvider).openClip,
    playsAsItArrives: ref.read(voicePlaysAsItArrivesProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
