import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class PlaybackRepository {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(String path) async {
    await _player.stop();
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final repository = PlaybackRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
