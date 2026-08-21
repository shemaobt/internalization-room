import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class PlaybackRepository {
  final Future<void> Function(String path)? _start;
  final StreamController<void> _completions = StreamController<void>.broadcast();
  StreamSubscription<PlayerState>? _states;
  AudioPlayer? _opened;
  Duration? _openedLength;

  PlaybackRepository({Future<void> Function(String path)? start}) : _start = start;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  Stream<void> get completions => _completions.stream;

  Duration? get playingLength => _openedLength;

  Duration get position => _opened?.position ?? Duration.zero;

  void _watchCompletion() {
    _states ??= _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _completions.add(null);
      }
    });
  }

  Future<void> play(String path) async {
    try {
      await (_start ?? _open)(path);
    } on Exception {
      _completions.add(null);
    }
  }

  Future<void> _open(String path) async {
    _watchCompletion();
    await _player.stop();
    _openedLength = await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> pause() => _quietly(() => _player.pause());

  Future<void> resume() => _quietly(() => _player.play());

  Future<void> stop() => _quietly(() => _player.stop());

  Future<void> _quietly(Future<void> Function() act) async {
    if (_opened == null) return;
    try {
      await act();
    } on Exception {
      return;
    }
  }

  Future<void> dispose() async {
    await _states?.cancel();
    await _completions.close();
    await _opened?.dispose();
  }
}

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final repository = PlaybackRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
