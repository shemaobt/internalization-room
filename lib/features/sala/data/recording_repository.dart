import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _permissionAnswerCeiling = Duration(seconds: 60);

/// What came of asking the microphone to start.
///
/// `false` used to mean both "the team said no" and "something went wrong", and the room
/// showed the microphone-denied screen for either — accusing a team that had denied
/// nothing, on a tablet whose disk was full.
enum Capture { started, denied, failed }

class RecordingRepository {
  final AudioRecorder _recorder = AudioRecorder();

  Future<Directory> _recordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'recordings'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Whether the microphone is allowed, or null when the question could not be asked.
  Future<bool?> hasPermission() async {
    try {
      return await _recorder.hasPermission().timeout(_permissionAnswerCeiling);
    } on Object {
      return null;
    }
  }

  Future<Capture> start(String fileName) async {
    if (await hasPermission() == false) return Capture.denied;
    try {
      final dir = await _recordingsDir();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: p.join(dir.path, '$fileName.m4a'),
      );
      return Capture.started;
    } on Object {
      // A full disk, an unwritable directory, another app holding the microphone. This
      // used to escape as an unhandled async error while the screen already showed the
      // room listening, and the team spoke into a recorder that was never running.
      return Capture.failed;
    }
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
