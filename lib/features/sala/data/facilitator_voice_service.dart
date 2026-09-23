import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'room_repository.dart';

const _libraryFolder = 'voz';
const _clipsKept = 60;
const _lineGrace = Duration(seconds: 8);
const _unknownLineCeiling = Duration(seconds: 90);

class FacilitatorVoiceService {
  final Future<Uint8List> Function(String url) _fetch;
  final Future<Directory> Function() _libraryDir;
  AudioPlayer? _opened;
  final Duration _grace;
  final Duration _loadCeiling;
  Future<void> _speaking = Future<void>.value();
  final Map<String, Future<File>> _arriving = {};

  FacilitatorVoiceService({
    required this._fetch,
    Future<Directory> Function()? libraryDir,
    AudioPlayer? player,
    Duration? lineGrace,
    Duration? loadCeiling,
  }) : _libraryDir = libraryDir ?? _defaultLibraryDir,
       _opened = player,
       _grace = lineGrace ?? _lineGrace,
       _loadCeiling = loadCeiling ?? _unknownLineCeiling;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  Future<bool> play(String url, {void Function()? onSoundStart}) {
    if (url.isEmpty) return Future.value(false);
    return _afterTheCurrentLine(() async {
      final file = await clipFor(url);
      return _sayItWhole(
        () => _player.setFilePath(file.path),
        onSoundStart: () {
          unawaited(_tidyLibrary());
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

  /// Whether this line is already on the tablet, so nothing has to be waited for.
  ///
  /// A replay is not the room thinking — it already holds the words. Passing through the
  /// thinking face on the way to repeating something it has in hand made the circle change
  /// colour twice for a line that starts instantly.
  Future<bool> holds(String url) async {
    if (url.isEmpty) return false;
    try {
      final dir = await _libraryDir();
      final file = File(p.join(dir.path, '${_nameFor(url)}.mp3'));
      return file.existsSync() && file.lengthSync() > 0;
    } on Exception {
      return false;
    }
  }

  Future<bool> playAsset(String assetPath, {void Function()? onSoundStart}) {
    return _afterTheCurrentLine(
      () => _sayItWhole(
        () => _player.setAsset(assetPath),
        onSoundStart: onSoundStart,
      ),
    );
  }

  Future<bool> _afterTheCurrentLine(Future<bool> Function() speak) {
    final spoken = _speaking.then((_) async {
      try {
        return await speak();
      } on Exception {
        return false;
      }
    });
    _speaking = spoken.then((_) {}, onError: (_) {});
    return spoken;
  }

  /// Whether the team heard the whole line.
  ///
  /// just_audio completes the future of `play()` when the sound stops — at the end of the
  /// line, but equally on a pause, on a stop, or when another app takes the output. Reading
  /// that as success let an interrupted line clear every health counter the room keeps, and
  /// pushed the team on to answer a question they were never asked.
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
  Future<File> clipFor(String url) {
    final arriving = _arriving[url];
    if (arriving != null) return arriving;
    final started = _bringItIn(url);
    _arriving[url] = started;
    return started.whenComplete(() => _arriving.remove(url));
  }

  Future<File> _bringItIn(String url) async {
    final dir = await _libraryDir();
    final file = File(p.join(dir.path, '${_nameFor(url)}.mp3'));
    if (file.existsSync() && file.lengthSync() > 0) {
      unawaited(_touch(file));
      return file;
    }
    // Staged and renamed, like the take queue two files away. `writeAsBytes` truncates
    // first, so a kill mid-write left a short file that passes `length > 0` and is served
    // from then on: the room goes mute on that one line, and stays mute across restarts.
    final staging = File('${file.path}.novo');
    await staging.writeAsBytes(await _fetch(url), flush: true);
    await staging.rename(file.path);
    return file;
  }

  String _nameFor(String url) => url.split('/').last;

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } on Exception {
      return;
    }
  }

  Future<void> _tidyLibrary() async {
    final dir = await _libraryDir();
    await _dropOldestBeyondBudget(dir);
  }

  Future<void> _dropOldestBeyondBudget(Directory dir) async {
    try {
      final clips = dir.listSync().whereType<File>().toList();
      if (clips.length <= _clipsKept) return;
      clips.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      for (final clip in clips.take(clips.length - _clipsKept)) {
        await clip.delete();
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

  Future<void> dispose() async => _opened?.dispose();
}

Future<Directory> _defaultLibraryDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, _libraryFolder)).create(recursive: true);
}

final facilitatorVoiceProvider = Provider<FacilitatorVoiceService>((ref) {
  final service = FacilitatorVoiceService(
    fetch: ref.read(roomRepositoryProvider).fetchClip,
  );
  ref.onDispose(service.dispose);
  return service;
});
