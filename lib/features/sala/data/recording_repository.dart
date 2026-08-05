import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingRepository {
  final AudioRecorder _recorder = AudioRecorder();

  Future<Directory> _recordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'recordings'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<bool> start(String fileName) async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await _recordingsDir();
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: p.join(dir.path, '$fileName.m4a'),
    );
    return true;
  }

  Future<String?> stop() => _recorder.stop();

  Future<void> discard() async {
    final path = await _recorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<String> keepAs(String path, String fileName) async {
    final dir = await _recordingsDir();
    final target = p.join(dir.path, '$fileName.m4a');
    await File(path).rename(target);
    return target;
  }

  Future<void> dispose() => _recorder.dispose();
}

final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final repository = RecordingRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
