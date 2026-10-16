import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/audio/room_audio_session.dart';
import '../domain/channel.dart';

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

  // A rehearsal, a scene take or a capture drops noise suppression and gain, as the
  // reference's DRAFT_MIC_CONSTRAINTS (wavRecorder.ts:141-144); a rehearsal and a scene
  // take are WAV (ADR 0054, ADR 0086).
  Future<Capture> start(
    String fileName, {
    MicOwner owner = MicOwner.conversation,
  }) async {
    if (await hasPermission() == false) return Capture.denied;
    final roomFilters =
        owner != MicOwner.rehearsal &&
        owner != MicOwner.scene &&
        owner != MicOwner.capture;
    final conversation = owner == MicOwner.conversation;
    try {
      final wav =
          owner == MicOwner.rehearsal ||
          (owner == MicOwner.scene && await _capturesRawAudio());
      final dir = await _recordingsDir();
      await _recorder.start(
        RecordConfig(
          encoder: wav ? AudioEncoder.wav : AudioEncoder.aacLc,
          sampleRate: wav || conversation
              ? 16000
              : const RecordConfig().sampleRate,
          bitRate: conversation ? 32000 : const RecordConfig().bitRate,
          audioInterruption: AudioInterruptionMode.pauseResume,
          echoCancel: true,
          noiseSuppress: roomFilters,
          autoGain: roomFilters,
          numChannels: 1,
        ),
        path: p.join(dir.path, '$fileName.${wav ? 'wav' : 'm4a'}'),
      );
      return Capture.started;
    } on Object {
      // A full disk, an unwritable directory, another app holding the microphone. This
      // used to escape as an unhandled async error while the screen already showed the
      // room listening, and the team spoke into a recorder that was never running.
      await restoreTheSampleRate();
      return Capture.failed;
    }
  }

  Future<bool> _capturesRawAudio() => _recorder
      .isEncoderSupported(AudioEncoder.wav)
      .catchError((Object _) => false);

  Stream<bool> get interrupted =>
      _recorder.onStateChanged().map((state) => state == RecordState.pause);

  Future<String?> stop() async {
    try {
      return await _recorder.stop();
    } finally {
      if (!await _recorder.isRecording().catchError((Object _) => false)) {
        await restoreTheSampleRate();
      }
    }
  }

  Future<void> discard() async {
    final path = await stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Keep audio that arrived from somewhere else beside the recordings this tablet made.
  ///
  /// The part a resume fetches back from the room comes through here, and it writes to the
  /// one directory: a part of the rehearsal is a part of the rehearsal whoever's tablet
  /// recorded it, the resume point names its takes by file there, and a second home would
  /// be a second thing to keep alive.
  Future<String> keepBytes(Uint8List bytes, String fileName) async {
    final dir = await _recordingsDir();
    final extension = _isWav(bytes) ? 'wav' : 'm4a';
    final target = p.join(dir.path, '$fileName.$extension');
    final whole = await File('$target.part').writeAsBytes(bytes, flush: true);
    return (await whole.rename(target)).path;
  }

  /// Where audio kept under [fileName] already is on this tablet, or null when it is not.
  Future<String?> heldAs(String fileName) async {
    final dir = await _recordingsDir();
    for (final extension in ['wav', 'm4a']) {
      final file = File(p.join(dir.path, '$fileName.$extension'));
      if (await file.exists() && await file.length() > 0) return file.path;
    }
    return null;
  }

  Future<String> keepAs(String path, String fileName) async {
    final dir = await _recordingsDir();
    final target = p.join(dir.path, '$fileName${p.extension(path)}');
    await File(path).rename(target);
    return target;
  }

  Future<void> dispose() => _recorder.dispose();
}

bool _isWav(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
    String.fromCharCodes(bytes, 8, 12) == 'WAVE';

final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final repository = RecordingRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
