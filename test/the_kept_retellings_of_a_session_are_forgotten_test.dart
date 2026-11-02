import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:record/record.dart';

import 'support/temp.dart';

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
    documents = aTempDir('sala-documentos');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => documents.path,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    RecordPlatform.instance = platformBefore;
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
  test('the sweep outside a session deletes the tellings kept for every other '
      'session, and leaves that session, the takes and the rest', () async {
    final recordings = Directory('${documents.path}/recordings')
      ..createSync(recursive: true);
    for (final name in [
      'kept-sessao-a-S1-2.wav',
      'kept-sessao-a-S2-1.m4a',
      'kept-sessao-b-S1-1.m4a',
      'kept-sessao-b-S3-1.wav',
      'kept-sessao-c-S1-1.m4a.part',
      'conversa_1760900000003.m4a',
      'cena-ensaio-da-cena-1.wav',
      'parte-1-gravacao-1-1760900000003-77.m4a',
      'checagem-t1.m4a',
    ]) {
      File('${recordings.path}/$name').writeAsStringSync('áudio');
    }
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.sweepTheKeptRetellingsOutside('sessao-a');

    expect(
      recordings.listSync().map((entry) => entry.path.split('/').last).toSet(),
      {
        'kept-sessao-a-S1-2.wav',
        'kept-sessao-a-S2-1.m4a',
        'conversa_1760900000003.m4a',
        'cena-ensaio-da-cena-1.wav',
        'parte-1-gravacao-1-1760900000003-77.m4a',
        'checagem-t1.m4a',
      },
    );
  });

  test('the sweep outside no session deletes every kept telling', () async {
    final recordings = Directory('${documents.path}/recordings')
      ..createSync(recursive: true);
    for (final name in [
      'kept-sessao-a-S1-2.wav',
      'kept-sessao-b-S1-1.m4a',
      'conversa_1760900000003.m4a',
    ]) {
      File('${recordings.path}/$name').writeAsStringSync('áudio');
    }
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.sweepTheKeptRetellingsOutside(null);

    expect(
      recordings.listSync().map((entry) => entry.path.split('/').last).toSet(),
      {'conversa_1760900000003.m4a'},
    );
  });
  Set<String> after(Directory recordings) =>
      recordings.listSync().map((entry) => entry.path.split('/').last).toSet();

  test(
    'a session whose id begins another\'s keeps only its own tellings',
    () async {
      final recordings = Directory('${documents.path}/recordings')
        ..createSync(recursive: true);
      for (final name in [
        'kept-ab-S1-1.m4a',
        'kept-ab-cd-S1-1.m4a',
        'kept-ab-cd-whole-12.wav',
      ]) {
        File('${recordings.path}/$name').writeAsStringSync('áudio');
      }
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.sweepTheKeptRetellingsOutside('ab');
      expect(after(recordings), {'kept-ab-S1-1.m4a'});

      for (final name in ['kept-ab-cd-S1-1.m4a']) {
        File('${recordings.path}/$name').writeAsStringSync('áudio');
      }
      await recording.sweepTheKeptRetellingsOutside('ab-cd');
      expect(after(recordings), {'kept-ab-cd-S1-1.m4a'});
    },
  );

  test('a file that vanished does not stop the sweep of the others', () async {
    final recordings = Directory('${documents.path}/recordings')
      ..createSync(recursive: true);
    for (final name in ['kept-other-S1-1.m4a', 'checagem-t1.m4a']) {
      File('${recordings.path}/$name').writeAsStringSync('áudio');
    }
    final gone = File('${recordings.path}/kept-gone-S1-1.m4a');

    await sweepTheKeptRetellingsIn(
      _ListingThatStartsWith(gone, recordings),
      'nenhuma',
    );

    expect(after(recordings), {'checagem-t1.m4a'});
  });
}

class _ListingThatStartsWith implements Directory {
  final File vanished;
  final Directory real;

  _ListingThatStartsWith(this.vanished, this.real);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    yield vanished;
    yield* real.list();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
