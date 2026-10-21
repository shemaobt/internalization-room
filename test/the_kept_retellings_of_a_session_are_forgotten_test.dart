import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:record/record.dart';

class _SilentMicrophone extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platformBefore = RecordPlatform.instance;
  late Directory documents;

  setUp(() {
    RecordPlatform.instance = _SilentMicrophone();
    documents = Directory.systemTemp.createTempSync('sala-documentos');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => documents.path,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    RecordPlatform.instance = platformBefore;
    documents.deleteSync(recursive: true);
  });

  test(
    'forgetting a session deletes the tellings kept for it, and nothing else',
    () async {
      final recordings = Directory('${documents.path}/recordings')
        ..createSync(recursive: true);
      for (final name in [
        'kept-sessao-a-S1-2.wav',
        'kept-sessao-a-S2-1.m4a',
        'kept-sessao-a-S3-4.wav',
        'kept-sessao-ab-S1-1.wav',
        'kept-sessao-b-S1-1.m4a',
        'conversa_1760900000003.m4a',
        'cena-ensaio-da-cena-1.wav',
      ]) {
        File('${recordings.path}/$name').writeAsStringSync('áudio');
      }
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.forgetTheKeptRetellings('sessao-a');

      expect(
        recordings
            .listSync()
            .map((entry) => entry.path.split('/').last)
            .toSet(),
        {
          'kept-sessao-ab-S1-1.wav',
          'kept-sessao-b-S1-1.m4a',
          'conversa_1760900000003.m4a',
          'cena-ensaio-da-cena-1.wav',
        },
      );
    },
  );
}
