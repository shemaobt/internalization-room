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

class FacilitatorVoiceService {
  final Future<Uint8List> Function(String url) _fetch;
  final Future<Directory> Function() _libraryDir;
  AudioPlayer? _opened;

  FacilitatorVoiceService({
    required Future<Uint8List> Function(String url) fetch,
    Future<Directory> Function()? libraryDir,
  })  : _fetch = fetch,
        _libraryDir = libraryDir ?? _defaultLibraryDir;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  Future<bool> play(String url) async {
    if (url.isEmpty) return false;
    try {
      final file = await clipFor(url);
      await _player.setFilePath(file.path);
      await _player.play();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<bool> playAsset(String assetPath) async {
    try {
      await _player.setAsset(assetPath);
      await _player.play();
      return true;
    } on Exception {
      return false;
    }
  }
  Future<File> clipFor(String url) async {
    final dir = await _libraryDir();
    final file = File(p.join(dir.path, '${_nameFor(url)}.mp3'));
    if (file.existsSync() && file.lengthSync() > 0) {
      unawaited(_touch(file));
      return file;
    }
    await file.writeAsBytes(await _fetch(url));
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
