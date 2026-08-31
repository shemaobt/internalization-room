import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class PlaybackRepository {
  final Future<void> Function(String path)? _start;
  final AudioPlayer Function() _newPlayer;
  final StreamController<bool> _endings = StreamController<bool>.broadcast();
  final StreamController<void> _openings = StreamController<void>.broadcast();
  StreamSubscription<PlayerState>? _states;
  AudioPlayer? _opened;
  Duration? _openedLength;
  /// The player that only ever measures, separate from [_opened] on purpose: loading a
  /// source replaces it, so measuring on the playing one would take the clip out of its
  /// hands — its length, its position, and the events the room hangs off both.
  AudioPlayer? _measurer;

  PlaybackRepository({
    Future<void> Function(String path)? start,
    AudioPlayer Function()? newPlayer,
  })  : _start = start,
        _newPlayer = newPlayer ?? AudioPlayer.new;

  AudioPlayer get _player => _opened ??= _newPlayer();

  /// How long an audio file is, without playing a second of it.
  ///
  /// Null when the file cannot be opened: no missing file is worth taking the room down
  /// over, and the caller decides what the absence means.
  Future<Duration?> howLong(String path) async {
    try {
      return await (_measurer ??= _newPlayer()).setFilePath(path);
    } on Object {
      return null;
    }
  }

  Stream<void> get completions =>
      _endings.stream.where((heard) => heard).map((_) {});

  Stream<void> get failures =>
      _endings.stream.where((heard) => !heard).map((_) {});

  /// The clip is loaded and its length is known. Until this, `playingLength` still
  /// answers for the clip before it.
  Stream<void> get openings => _openings.stream;

  Duration? get playingLength => _openedLength;

  Duration get position => _opened?.position ?? Duration.zero;

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
      _openings.add(null);
      await _player.play();
    } on Object {
      _endings.add(false);
    }
  }

  Future<void> _open(String path) async {
    _watchCompletion();
    await _player.stop();
    _openedLength = await _player.setFilePath(path);
    _openings.add(null);
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
    await _openings.close();
    await _opened?.dispose();
    await _measurer?.dispose();
  }
}

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final repository = PlaybackRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
