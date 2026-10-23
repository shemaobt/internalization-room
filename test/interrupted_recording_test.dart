import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/audio/room_audio_session.dart';
import 'package:internalization_room/features/sala/data/recording_repository.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import 'a_wav_take.dart';

class RecorderSpy extends RecordPlatform {
  RecordConfig? openedWith;
  String? openedPath;
  bool refusesToOpen = false;
  bool wavSupported = true;
  bool encoderCheckFails = false;
  bool recordingAgain = false;
  final StreamController<RecordState> states =
      StreamController<RecordState>.broadcast();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    if (refusesToOpen) throw const FileSystemException('disco cheio');
    openedWith = config;
    openedPath = path;
  }

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    if (encoderCheckFails) throw PlatformException(code: 'gravador');
    return encoder != AudioEncoder.wav || wavSupported;
  }

  @override
  Future<bool> isRecording(String recorderId) async => recordingAgain;

  @override
  Future<String?> stop(String recorderId) async => openedPath;

  @override
  Stream<RecordState> onStateChanged(String recorderId) => states.stream;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Plain extends IOOverrides {}

/// A directory listed by position, the way a listing can skip the entry after one deleted
/// while it is still open.
class _ListedByPosition implements Directory {
  final Directory _real;

  _ListedByPosition(String path)
    : _real = IOOverrides.runWithIOOverrides(() => Directory(path), _Plain());

  @override
  String get path => _real.path;

  @override
  Future<Directory> create({bool recursive = false}) async {
    await _real.create(recursive: recursive);
    return this;
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    for (var at = 0; ; at++) {
      final now = _real.listSync()..sort((a, b) => a.path.compareTo(b.path));
      if (at >= now.length) return;
      yield now[at];
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A file whose write dies halfway, the way it does when the app is killed mid-write.
class _DiesHalfway implements File {
  final File _real;

  _DiesHalfway(String path)
    : _real = IOOverrides.runWithIOOverrides(() => File(path), _Plain());

  @override
  String get path => _real.path;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await _real.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2), flush: true);
    throw const FileSystemException('o app morreu no meio da escrita');
  }

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<int> length() => _real.length();

  @override
  Future<File> rename(String newPath) => _real.rename(newPath);

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
      pathProvider,
      (call) async => documents.path,
    );
    microphone = RecorderSpy();
    RecordPlatform.instance = microphone;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    RecordPlatform.instance = platformBefore;
    unawaited(microphone.states.close());
    documents.deleteSync(recursive: true);
  });

  test(
    'a take interrupted by a ring is opened to come back on its own',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('ensaio');

      expect(
        microphone.openedWith?.audioInterruption,
        AudioInterruptionMode.pauseResume,
        reason:
            'aberto para pausar e não retomar, o gravador ficava parado o '
            'resto da tomada e um pedaço de noventa segundos era entregue como '
            'se fosse a passagem inteira',
      );
    },
  );

  test(
    'a conversation turn is still recorded as AAC in an .m4a file',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('conversa');

      expect(
        microphone.openedWith?.encoder,
        AudioEncoder.aacLc,
        reason:
            'a fala com a sala não é entregável; só a parte do ensaio muda de '
            'formato',
      );
      expect(
        microphone.openedPath,
        p.join(documents.path, 'recordings', 'conversa.m4a'),
      );
      expect(microphone.openedWith?.echoCancel, isTrue);
      expect(microphone.openedWith?.noiseSuppress, isTrue);
      expect(microphone.openedWith?.autoGain, isTrue);
    },
  );

  test(
    'the microphone opens ready for a room where five people talk at once',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('conversa');

      final config = microphone.openedWith;
      expect(
        config?.echoCancel,
        isTrue,
        reason:
            'a fala do gravador voltando pela caixa nunca devia contar como a '
            'equipe falando',
      );
      expect(
        config?.noiseSuppress,
        isTrue,
        reason: 'a sala grava perto de outras conversas, não sozinha',
      );
      expect(
        config?.autoGain,
        isTrue,
        reason: 'uma voz mais baixa não pode virar um trecho perdido',
      );
      expect(
        config?.numChannels,
        1,
        reason:
            'a passagem falada é uma faixa, e um canal a menos é metade do '
            'arquivo que a fila de upload carrega à toa',
      );
    },
  );

  test(
    'a deliverable take keeps the room\'s own filters off and its echo cancel on',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('ensaio_tomada', owner: MicOwner.rehearsal);

      final config = microphone.openedWith;
      expect(
        config?.echoCancel,
        isTrue,
        reason:
            'o microfone fica na mesma mesa das caixas, e o eco delas não '
            'pode virar fala da equipe',
      );
      expect(
        config?.noiseSuppress,
        isFalse,
        reason:
            'a tomada que vai para o Refine não pode ganhar um filtro que '
            'colore a voz da equipe antes de alguém ouvir',
      );
      expect(
        config?.autoGain,
        isFalse,
        reason:
            'o ganho automático coloriria a mesma voz que o Refine precisa '
            'ouvir sem tratamento',
      );
    },
  );

  test(
    'a discard leaves the last take alone when no recording is open',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);
      await recording.start('ensaio_parte1', owner: MicOwner.rehearsal);
      final kept = File(microphone.openedPath!)..createSync(recursive: true);

      await recording.discard();

      expect(
        kept.existsSync(),
        isTrue,
        reason:
            'o stop de um gravador parado responde o caminho da última gravação; '
            'descartar apagava a tomada que a equipe acabava de guardar',
      );
    },
  );

  test('a discard stops and deletes the recording that is open', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);
    await recording.start('ensaio_parte1', owner: MicOwner.rehearsal);
    microphone.recordingAgain = true;
    final open = File(microphone.openedPath!)..createSync(recursive: true);

    await recording.discard();

    expect(open.existsSync(), isFalse);
  });

  test('a rehearsal take opens the microphone as 16 kHz mono WAV', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('ensaio_parte1', owner: MicOwner.rehearsal);

    final config = microphone.openedWith;
    expect(
      config?.encoder,
      AudioEncoder.wav,
      reason: 'o Refine recebe a parte sem perda, como o app dela grava',
    );
    expect(config?.sampleRate, 16000);
    expect(config?.numChannels, 1);
  });

  test('a rehearsal take is written to a .wav file in recordings/', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('ensaio_parte1', owner: MicOwner.rehearsal);

    expect(
      microphone.openedPath,
      p.join(documents.path, 'recordings', 'ensaio_parte1.wav'),
      reason:
          'o player escolhe como ler o arquivo pela extensão, e um WAV '
          'chamado .m4a não toca',
    );
  });

  test(
    'a capture is still AAC in an .m4a file with the draft filters',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('retro_passada1_pedaco1', owner: MicOwner.capture);

      final config = microphone.openedWith;
      expect(
        config?.encoder,
        AudioEncoder.aacLc,
        reason: 'o contar de volta fica comprimido, como no app dela',
      );
      expect(
        microphone.openedPath,
        p.join(documents.path, 'recordings', 'retro_passada1_pedaco1.m4a'),
      );
      expect(config?.echoCancel, isTrue);
      expect(config?.noiseSuppress, isFalse);
      expect(config?.autoGain, isFalse);
      expect(config?.numChannels, 1);
    },
  );

  test('a capture keeps the plugin\'s own sample rate and bit rate', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('retro_passada1_pedaco1', owner: MicOwner.capture);

    expect(
      [microphone.openedWith?.sampleRate, microphone.openedWith?.bitRate],
      [44100, 128000],
      reason: 'o contar de volta abre como antes; só a conversa encolheu',
    );
  });

  test('a question keeps the plugin\'s own sample rate and bit rate', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('pergunta_1', owner: MicOwner.question);

    expect(
      [microphone.openedWith?.sampleRate, microphone.openedWith?.bitRate],
      [44100, 128000],
      reason: 'a pergunta da mão sobe como antes; só a conversa encolheu',
    );
  });

  test('a conversation turn opens the microphone at 32 kbps', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('conversa');

    expect(
      microphone.openedWith?.bitRate,
      32000,
      reason:
          'sem taxa, o plugin gravava a 128 kbps, uns 16 KB por segundo de '
          'fala subindo antes de a transcrição poder começar',
    );
  });

  test('a conversation turn opens the microphone at 16 kHz', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('conversa');

    expect(
      microphone.openedWith?.sampleRate,
      16000,
      reason:
          'a fala com a sala subia gravada a 44,1 kHz, mais do que a '
          'transcrição usa, numa rede de campo lenta',
    );
  });

  test(
    'a take fetched back from the room as WAV is kept as a .wav file',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);
      final wav = aWavTake();

      final kept = await recording.keepBytes(wav, 'parte-1');

      expect(
        kept,
        endsWith('.wav'),
        reason:
            'a retomada toca a parte buscada de volta, e o player lê um WAV '
            'chamado .m4a como AAC',
      );
      expect(File(kept).readAsBytesSync(), wav);
    },
  );

  test(
    'an older AAC take fetched back from the room is kept as .m4a',
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      final kept = await recording.keepBytes(
        Uint8List.fromList([0, 0, 0, 24, ...'ftypM4A '.codeUnits]),
        'parte-1',
      );

      expect(kept, endsWith('.m4a'));
    },
  );

  test(
    "a scene take's staging left by a kill mid-download is swept, and a fresh one is not",
    () async {
      final recording = RecordingRepository();
      addTearDown(recording.dispose);
      final recordings = Directory(p.join(documents.path, 'recordings'))
        ..createSync(recursive: true);
      final now = DateTime.now();
      final old = File(p.join(recordings.path, 'cena-old.wav.part'))
        ..writeAsBytesSync(aWavTake())
        ..setLastModifiedSync(now.subtract(const Duration(minutes: 11)));
      final older = File(p.join(recordings.path, 'cena-older.wav.part'))
        ..writeAsBytesSync(aWavTake())
        ..setLastModifiedSync(now.subtract(const Duration(minutes: 30)));
      final fresh = File(p.join(recordings.path, 'cena-new.wav.part'))
        ..writeAsBytesSync(aWavTake())
        ..setLastModifiedSync(now.subtract(const Duration(minutes: 1)));

      final kept = await IOOverrides.runZoned(
        () => recording.keepBytes(aWavTake(), 'cena-x'),
        createDirectory: _ListedByPosition.new,
      );

      expect(old.existsSync(), isFalse);
      expect(older.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(kept, p.join(recordings.path, 'cena-x.wav'));
      expect(File(kept).readAsBytesSync(), aWavTake());
    },
  );

  group('one take is kept by one write at a time', () {
    late RecordingRepository recording;
    late Directory recordings;

    setUp(() {
      recording = RecordingRepository();
      addTearDown(recording.dispose);
      recordings = Directory(p.join(documents.path, 'recordings'))
        ..createSync(recursive: true);
    });

    test(
      'two keeps of one scene take at once leave one whole file, and neither fails',
      () async {
        final kept = await Future.wait([
          for (var i = 0; i < 4; i++) recording.keepBytes(aWavTake(), 'cena-x'),
        ]);

        final whole = p.join(recordings.path, 'cena-x.wav');
        expect(kept, everyElement(whole));
        expect(File(whole).readAsBytesSync(), aWavTake());
        expect(
          recordings.listSync().where((entry) => entry.path.endsWith('.part')),
          isEmpty,
        );
      },
    );

    test(
      'a keep after a finished keep of the same name writes again',
      () async {
        final first = aWavTake(samples: const [0, 100, -100, 0]);
        final second = aWavTake(samples: const [0, 900, -900, 0]);

        await recording.keepBytes(first, 'cena-x');
        final kept = await recording.keepBytes(second, 'cena-x');

        expect(File(kept).readAsBytesSync(), second);
      },
    );

    test('a failed keep does not stick to its name', () async {
      Process.runSync('chmod', ['a-w', recordings.path]);
      addTearDown(() => Process.runSync('chmod', ['u+w', recordings.path]));

      await expectLater(
        recording.keepBytes(aWavTake(), 'cena-y'),
        throwsA(isA<FileSystemException>()),
      );

      Process.runSync('chmod', ['u+w', recordings.path]);
      final kept = await recording.keepBytes(aWavTake(), 'cena-y');

      expect(File(kept).readAsBytesSync(), aWavTake());
    });
  });

  test('a recording that starts hands back a usable file', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    final capture = await recording.start('ensaio');

    expect(capture, Capture.started);
    expect(
      microphone.openedPath,
      p.join(documents.path, 'recordings', 'ensaio.m4a'),
      reason:
          'a tomada guardada é procurada pelo nome dentro de recordings/, '
          'e um caminho fora dali some na hora de enfileirar',
    );
  });

  test(
    'a microphone that will not open gives the room back to the team',
    () async {
      microphone.refusesToOpen = true;
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      expect(
        await recording.start('ensaio'),
        Capture.failed,
        reason:
            'o disco cheio escapava como erro assíncrono não tratado '
            'enquanto a tela já mostrava a sala ouvindo',
      );
    },
  );

  test('a recorder the system pauses says the microphone was taken, and says '
      'it came back', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);
    final reported = <bool>[];
    recording.interrupted.listen(reported.add);

    await recording.start('ensaio');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    microphone.states.add(RecordState.pause);
    microphone.states.add(RecordState.record);
    microphone.states.add(RecordState.stop);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(
      reported,
      [true, false, false],
      reason:
          'a pausa que a ligação provoca é o único aviso que sai do '
          'gravador; sem lê-lo a sala seguia desenhando uma captura parada, e '
          'o fim da tomada não pode ser lido como microfone tomado',
    );
  });

  test('audio whose write dies halfway is never held as kept', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);
    final bytes = Uint8List.fromList(List.filled(64, 7));

    await IOOverrides.runZoned(() async {
      await expectLater(
        recording.keepBytes(bytes, 'cena-1'),
        throwsA(isA<FileSystemException>()),
      );
    }, createFile: _DiesHalfway.new);

    expect(
      await recording.heldAs('cena-1'),
      isNull,
      reason:
          'um take pela metade sob o nome final seria confiado por toda '
          'reabertura, e o ensaio ficaria preso sem lugar para as frases',
    );
  });
  test('a scene take opens the microphone as 16 kHz mono WAV with echo '
      'cancellation and no noise suppression or automatic gain', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    await recording.start('cena_1', owner: MicOwner.scene);

    final config = microphone.openedWith;
    expect(
      config?.encoder,
      AudioEncoder.wav,
      reason: 'o Refine recebe o ensaio da cena no formato dela, sem perda',
    );
    expect(config?.sampleRate, 16000);
    expect(config?.numChannels, 1);
    expect(config?.echoCancel, isTrue);
    expect(config?.noiseSuppress, isFalse);
    expect(config?.autoGain, isFalse);
    expect(
      microphone.openedPath,
      p.join(documents.path, 'recordings', 'cena_1.wav'),
    );
  });

  test(
    'a scene take is compressed only when the tablet cannot capture raw audio',
    () async {
      microphone.wavSupported = false;
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      await recording.start('cena_1', owner: MicOwner.scene);

      final config = microphone.openedWith;
      expect(config?.encoder, AudioEncoder.aacLc);
      expect(
        microphone.openedPath,
        p.join(documents.path, 'recordings', 'cena_1.m4a'),
        reason: 'o player escolhe o leitor pela extensão',
      );
      expect(config?.noiseSuppress, isFalse);
      expect(config?.autoGain, isFalse);

      microphone.wavSupported = true;
      await recording.start('cena_2', owner: MicOwner.scene);

      expect(microphone.openedWith?.encoder, AudioEncoder.wav);
    },
  );

  test('a scene take is compressed when the tablet cannot say whether it '
      'captures raw audio', () async {
    microphone.encoderCheckFails = true;
    final recording = RecordingRepository();
    addTearDown(recording.dispose);

    final capture = await recording.start('cena_1', owner: MicOwner.scene);

    expect(
      capture,
      Capture.started,
      reason:
          'uma pergunta ao gravador que falhou não é um microfone que '
          'não abriu, e duas seguidas chamavam uma pessoa',
    );
    expect(microphone.openedWith?.encoder, AudioEncoder.aacLc);
  });

  test('a WAV take kept under the rehearsal\'s name is still a .wav', () async {
    final recording = RecordingRepository();
    addTearDown(recording.dispose);
    final take = File(p.join(documents.path, 'recordings', 'cena_1.wav'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(aWavTake());

    final kept = await recording.keepAs(take.path, 'cena-ensaio-1');

    expect(
      kept,
      p.join(documents.path, 'recordings', 'cena-ensaio-1.wav'),
      reason: 'um WAV chamado .m4a não toca, e a reabertura o baixaria de novo',
    );
    expect(File(kept).readAsBytesSync(), aWavTake());
  });

  group('the audio session', () {
    const audioSession = MethodChannel('internalization_room/audio_session');
    late List<MethodCall> heard;

    setUp(() {
      heard = [];
      messenger.setMockMethodCallHandler(audioSession, (call) async {
        heard.add(call);
        return call.method == 'sampleRate' ? 48000.0 : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(audioSession, null));

    Future<void> recordAndThen(
      Future<void> Function(RecordingRepository) end, {
      MicOwner owner = MicOwner.conversation,
    }) async {
      await configureRoomAudio();
      final recording = RecordingRepository();
      addTearDown(recording.dispose);
      await recording.start('tomada', owner: owner);
      heard.clear();
      await end(recording);
    }

    void expectTheRateGivenBack() => expect(
      [for (final call in heard) (call.method, call.arguments)],
      [('preferSampleRate', 48000.0)],
      reason:
          'o gravador deixa a sessão preferindo 16 kHz, e a voz do Guia que '
          'toca depois sai abafada',
    );

    test('after a WAV part the audio session prefers the sample rate it had '
        'before the first recording', () async {
      await recordAndThen(
        (recording) => recording.stop(),
        owner: MicOwner.rehearsal,
      );

      expectTheRateGivenBack();
    });

    test('a conversation turn gives the rate back too', () async {
      await recordAndThen((recording) => recording.stop());

      expectTheRateGivenBack();
    });

    test(
      'the rate is never given back over a recording that started meanwhile',
      () async {
        await recordAndThen((recording) {
          microphone.recordingAgain = true;
          return recording.discard();
        });

        expect(
          heard,
          isEmpty,
          reason:
              'a devolução atrasada de um descarte trocaria a taxa no meio da '
              'tomada nova',
        );
      },
    );

    test('a start that fails gives the rate back too', () async {
      await configureRoomAudio();
      final recording = RecordingRepository();
      addTearDown(recording.dispose);
      microphone.refusesToOpen = true;
      heard.clear();

      expect(
        await recording.start('tomada', owner: MicOwner.rehearsal),
        Capture.failed,
      );

      expectTheRateGivenBack();
    });

    test(
      'a failed start never gives the rate back over a recording that started '
      'meanwhile',
      () async {
        await configureRoomAudio();
        final recording = RecordingRepository();
        addTearDown(recording.dispose);
        microphone
          ..refusesToOpen = true
          ..recordingAgain = true;
        heard.clear();

        await recording.start('tomada', owner: MicOwner.rehearsal);

        expect(heard, isEmpty);
      },
    );

    test('a discarded recording gives the rate back too', () async {
      await recordAndThen((recording) => recording.discard());

      expectTheRateGivenBack();
    });
  });

  test(
    'the room still records on a tablet with no audio-session channel',
    () async {
      await configureRoomAudio();
      final recording = RecordingRepository();
      addTearDown(recording.dispose);

      expect(
        await recording.start('tomada', owner: MicOwner.rehearsal),
        Capture.started,
      );
      expect(await recording.stop(), isNotNull);
      await recording.discard();
    },
  );
}
