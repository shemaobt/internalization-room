import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';

const _clip = '/api/internalization-room/voice/aaa';
const _other = '/api/internalization-room/voice/bbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory library;
  late List<String> fetched;

  setUp(() {
    library = Directory.systemTemp.createTempSync('sala-voz');
    fetched = [];
  });

  tearDown(() {
    if (library.existsSync()) library.deleteSync(recursive: true);
  });

  FacilitatorVoiceService service() => FacilitatorVoiceService(
        fetch: (url) async {
          fetched.add(url);
          return Uint8List.fromList([1, 2, 3]);
        },
        libraryDir: () async => library,
      );

  test('a line already heard is never fetched again', () async {
    final voice = service();

    await voice.clipFor(_clip);
    await voice.clipFor(_other);
    await voice.clipFor(_clip);

    expect(fetched, [_clip, _other],
        reason: 'o endereço é endereçado por conteúdo — os bytes nunca mudam, '
            'então buscar de novo é pagar duas vezes pela mesma frase');
  });

  test('each line keeps its own file, instead of overwriting the last', () async {
    final voice = service();

    await voice.clipFor(_clip);
    await voice.clipFor(_other);

    expect(library.listSync().whereType<File>(), hasLength(2));
  });

  test('an empty address is refused without touching the network', () async {
    expect(await service().play(''), isFalse);
    expect(fetched, isEmpty);
  });

  test('a fetch that fails is a failure to play, never a crash', () async {
    final voice = FacilitatorVoiceService(
      fetch: (_) async => throw const SocketException('sem rede'),
      libraryDir: () async => library,
    );

    expect(await voice.play(_clip), isFalse);
  });

  test('a truncated file on disk is fetched again, not played', () async {
    File('${library.path}/aaa.mp3').writeAsBytesSync([]);
    final voice = service();

    await voice.clipFor(_clip);

    expect(fetched, [_clip],
        reason: 'um arquivo de zero byte de uma escrita interrompida tocaria '
            'silêncio, e a equipe ouve cada frase uma vez só');
  });
}
