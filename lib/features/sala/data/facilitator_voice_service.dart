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
  Future<void> _speaking = Future<void>.value();

  FacilitatorVoiceService({
    required Future<Uint8List> Function(String url) fetch,
    Future<Directory> Function()? libraryDir,
  })  : _fetch = fetch,
        _libraryDir = libraryDir ?? _defaultLibraryDir;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  Future<bool> play(String url) {
    if (url.isEmpty) return Future.value(false);
    return _afterTheCurrentLine(() async {
      final file = await clipFor(url);
      return _sayItWhole(() => _player.setFilePath(file.path));
    });
  }

  /// Fetch a line without speaking it, so the room can wait in the state it is really in.
  ///
  /// The speaking ripples used to start before this download, which can take as long as
  /// the request allows: the circle was visibly talking and audibly saying nothing.
  Future<bool> fetch(String url) async {
    if (url.isEmpty) return false;
    try {
      await clipFor(url);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> playAsset(String assetPath) {
    return _afterTheCurrentLine(
      () => _sayItWhole(() => _player.setAsset(assetPath)),
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

  Future<bool> _sayItWhole(Future<Duration?> Function() load) async {
    final length = await load();
    try {
      await _player.play().timeout((length ?? _unknownLineCeiling) + _lineGrace);
    } on TimeoutException {
      await stop();
    }
    return true;
  }
  Future<File> clipFor(String url) async {
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
    unawaited(_dropOldestBeyondBudget(dir));
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
