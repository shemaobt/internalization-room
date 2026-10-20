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
    'the sweep at launch deletes every scene frase a killed app left, and nothing else',
    () async {
      final recordings = Directory('${documents.path}/recordings')
        ..createSync(recursive: true);
      for (final name in [
        'frase_1760900000000.m4a',
        'frase_1760900000001.m4a',
        'cena-ensaio-da-cena-1.wav',
        'cena_1760900000002.wav',
        'conversa_1760900000003.m4a',
      ]) {
        File('${recordings.path}/$name').writeAsStringSync('áudio');
      }
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.sweepTheFrasesLeftBehind();

      expect(
        recordings
            .listSync()
            .map((entry) => entry.path.split('/').last)
            .toSet(),
        {
          'cena-ensaio-da-cena-1.wav',
          'cena_1760900000002.wav',
          'conversa_1760900000003.m4a',
        },
      );
    },
  );
}
