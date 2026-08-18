import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class PlaybackRepository {
  final Future<void> Function(String path)? _start;
  /// Every ending, and whether the audio was actually heard.
  ///
  /// A file that will not open used to be published as a completion, so "the team heard
  /// it" and "there was nothing to hear" arrived on the same wire. In the retro that
  /// meant a corrupt rehearsal marked the clip as played to the end, which is the one
  /// condition the `terminei` gesture waits for.
  final StreamController<bool> _endings = StreamController<bool>.broadcast();
  StreamSubscription<PlayerState>? _states;
  AudioPlayer? _opened;
  Duration? _openedLength;

  PlaybackRepository({Future<void> Function(String path)? start}) : _start = start;

  AudioPlayer get _player => _opened ??= AudioPlayer();

  Stream<void> get completions =>
      _endings.stream.where((heard) => heard).map((_) {});

  Stream<void> get failures =>
      _endings.stream.where((heard) => !heard).map((_) {});

  Duration? get playingLength => _openedLength;

  Duration get position => _opened?.position ?? Duration.zero;

  Future<void> seek(Duration to) => _quietly(() => _player.seek(to));

  void _watchCompletion() {
    _states ??= _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _endings.add(true);
      }
    });
  }

  Future<void> play(String path) async {
    try {
      await (_start ?? _open)(path);
    } on Object {
      _endings.add(false);
    }
  }

  Future<void> playRange(String path, Duration from, Duration to) async {
    if (_start != null) return play(path);
    try {
      _watchCompletion();
      await _player.stop();
      _openedLength = await _player.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.file(path),
          start: from,
          end: to,
        ),
      );
      await _player.play();
    } on Object {
      _endings.add(false);
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

  Future<void> stop() => _quietly(() async {
        // Cleared with the playback it described. The safety ceiling for the next clip
        // was computed from the length of the last one.
        _openedLength = null;
        await _player.stop();
      });

  Future<void> _quietly(Future<void> Function() act) async {
    if (_opened == null) return;
    try {
      await act();
    } on Object {
      // `on Exception` while `play` was widened to `on Object`: a `StateError` from a
      // disposed player escaped these four fire-and-forget calls with nothing to catch it.
      return;
    }
  }

  Future<void> dispose() async {
    await _states?.cancel();
    await _endings.close();
    await _opened?.dispose();
  }
}

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final repository = PlaybackRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
