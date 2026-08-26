import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

class RecorderSpy extends RecordPlatform {
  RecordConfig? openedWith;
  String? openedPath;
  bool refusesToOpen = false;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    if (refusesToOpen) throw const FileSystemException('disco cheio');
    openedWith = config;
    openedPath = path;
  }

  @override
  Future<String?> stop(String recorderId) async => openedPath;

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

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

  late RecorderSpy microphone;
  late Directory documents;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('sala-documentos');
    messenger.setMockMethodCallHandler(
        pathProvider, (call) async => documents.path);
    microphone = RecorderSpy();
    RecordPlatform.instance = microphone;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    RecordPlatform.instance = platformBefore;
    documents.deleteSync(recursive: true);
  });

  test('a take interrupted by a ring is opened to come back on its own',
      () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('ensaio');

    expect(microphone.openedWith?.audioInterruption,
        AudioInterruptionMode.pauseResume,
        reason: 'aberto para pausar e não retomar, o gravador ficava parado o '
            'resto da tomada e um pedaço de noventa segundos era entregue como '
            'se fosse a passagem inteira');
  });

  test('the take is still captured in AAC-LC', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('ensaio');

    expect(microphone.openedWith?.encoder, AudioEncoder.aacLc,
        reason: 'o ensaio inteiro, o retro e a fila de upload contam com m4a — '
            'trocar o encoder de passagem deixaria a sala gravando um formato '
            'que o resto do caminho não abre');
  });

  test('a recording that starts hands back a usable file', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    final capture = await recording.start('ensaio');

    expect(capture, Capture.started);
    expect(microphone.openedPath,
        p.join(documents.path, 'recordings', 'ensaio.m4a'),
        reason: 'a tomada guardada é procurada pelo nome dentro de recordings/, '
            'e um caminho fora dali some na hora de enfileirar');
  });

  test('a microphone that will not open gives the room back to the team',
      () async {
    microphone.refusesToOpen = true;
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    expect(await recording.start('ensaio'), Capture.failed,
        reason: 'o disco cheio escapava como erro assíncrono não tratado '
            'enquanto a tela já mostrava a sala ouvindo');
  });
}
