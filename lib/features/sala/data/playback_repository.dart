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
    this._start,
    AudioPlayer Function()? newPlayer,
  }) : _newPlayer = newPlayer ?? AudioPlayer.new;

  AudioPlayer get _player => _opened ??= _newPlayer();

  /// How long an audio file is, without playing a second of it.
  ///
  /// Null when the file cannot be opened: no missing file is worth taking the room down
  /// over, and the caller decides what the absence means.
  Future<Duration?> howLong(String path) {
    // One at a time. The measurer is a single player with a single source, so two loads in
    // the air replace one another: a resume fires two of these unawaited, and the first
    // came back answering for the second file or for nothing at all.
    final turn = _measuring.then((_) => _measure(path));
    _measuring = turn.then((_) {}, onError: (_) {});
    return turn;
  }

  Future<void> _measuring = Future.value();

  Future<Duration?> _measure(String path) async {
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

  /// Play [path], starting [from] into the file.
  ///
  /// The offset is handed to the load, not sought after it. A seek issued against a
  /// source that has only just been set races the load that is still settling, and the
  /// clip starts at nought anyway — on a fresh load the player has nowhere to seek to
  /// yet. Given at load, the position is already there when the first sound comes out.
  ///
  /// Not a [ClippingAudioSource] either, which would also start the sound at [from]: a
  /// clip answers `position` counted from its own start, and every place the room holds —
  /// the cursor a stretch begins at, the two times a stretch is sent with — is counted
  /// from the beginning of the file. The two would agree only while [from] was nought.
  Future<void> play(String path, {Duration from = Duration.zero}) async {
    try {
      final start = _start;
      if (start != null) {
        await start(path);
      } else {
        await _open(path, from);
      }
    } on Object {
      _endings.add(false);
    }
  }

  Future<void> playRange(String path, Duration from, Duration to) async {
    if (_start != null) return play(path);
    try {
      _watchCompletion();
      await _openThen(
        () => _player.setAudioSource(
          ClippingAudioSource(
            child: AudioSource.file(path),
            start: from,
            end: to,
          ),
        ),
      );
    } on Object {
      _endings.add(false);
    }
  }

  Future<void> _open(String path, Duration from) async {
    _watchCompletion();
    await _openThen(() => _player.setFilePath(path, initialPosition: from));
  }

  /// Load a source and play it, unless a hold arrived while it was still loading.
  ///
  /// just_audio's `pause()` opens with `if (!playing) return;`, and during a load nothing
  /// is playing yet: the hold was a silent no-op, and the `play()` waiting behind the
  /// load started the very clip the team had just stopped. Counting the holds instead of
  /// asking the player what it is doing is what lets a hold issued into that gap win.
  ///
  /// The opening is still announced, hold or no hold: the room hangs the listening
  /// ceiling and the measure of the part in the air off it, and a clip that never
  /// announces itself strands both.
  Future<void> _openThen(Future<Duration?> Function() load) async {
    final segurava = _holds;
    final parada = _stops;
    await _player.stop();
    final Duration? length;
    try {
      length = await load();
    } on PlayerInterruptedException {
      // Our own stop deactivates the platform at once, and the load in the air throws
      // for it. That is the clip not playing, never this tablet failing to play the
      // team's own voice — which calls a person and stops the room over a common gesture.
      if (segurava != _holds) return;
      rethrow;
    }
    // A pause leaves the clip open, and the ceiling counts what is left of it, so the
    // measure stands. A stop does not: it cleared the measure on the way past, and a load
    // settling behind it would write back the length of a clip that never played — which
    // is the very length the ceiling of the next clip would be computed from.
    _openedLength = parada == _stops ? length : null;
    _openings.add(null);
    if (segurava != _holds) return;
    await _player.play();
  }

  /// How many times the room has held what is sounding. Only a hold counts: a resume
  /// asks for the very clip it is resuming.
  int _holds = 0;

  /// How many of those holds were a stop, which is the half that also forgets what the
  /// clip measured.
  int _stops = 0;

  Future<void> pause() {
    _holds++;
    return _quietly(() => _player.pause());
  }

  Future<void> resume() => _quietly(() => _player.play());

  Future<void> stop() {
    _holds++;
    _stops++;
    return _quietly(() async {
      // Cleared with the playback it described. The safety ceiling for the next clip
      // was computed from the length of the last one.
      _openedLength = null;
      await _player.stop();
    });
  }

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
