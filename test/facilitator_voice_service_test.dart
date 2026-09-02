import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:just_audio/just_audio.dart';

import 'fakes.dart';

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

  FacilitatorVoiceService service({AudioPlayer? player, Duration? grace}) =>
      FacilitatorVoiceService(
        fetch: (url) async {
          fetched.add(url);
          return Uint8List.fromList([1, 2, 3]);
        },
        libraryDir: () async => library,
        player: player,
        lineGrace: grace,
      );

  test('two callers asking for the same line at once share one download', () async {
    final voice = service();

    final together = await Future.wait([
      voice.clipFor(_clip),
      voice.clipFor(_clip),
      voice.clipFor(_clip),
    ]);

    expect(fetched, [_clip],
        reason: 'a abertura busca o segundo movimento enquanto o primeiro ainda '
            'está sendo falado, e dois downloads da mesma fala escreviam o mesmo '
            'arquivo de staging e o renomeavam por cima um do outro');
    expect(together.map((file) => file.path).toSet(), hasLength(1));
    for (final file in together) {
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(0));
    }
  });

  test('a line already fetched alongside its own play still plays', () async {
    final voice = service();

    final arriving = voice.fetch(_clip);
    final file = await voice.clipFor(_clip);
    await arriving;

    expect(file.existsSync(), isTrue,
        reason: 'o perdedor da corrida estourava, o estouro era engolido como '
            'uma fala que não toca, e a sala ficava muda entre dois fôlegos');
    expect(fetched, [_clip]);
  });

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

  test('a line the player paused in the middle is not counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(player: player);

    final speaking = voice.play(_clip);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    player.pauseIt();

    expect(await speaking, isFalse,
        reason: 'o just_audio resolve o future do play() na pausa e no stop, nao so '
            'no fim — a sala contava como falada uma linha que a equipe nao ouviu');
  });

  test('a line that overruns its ceiling is not counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(player: player, grace: const Duration(milliseconds: 30));

    expect(await voice.play(_clip), isFalse,
        reason: 'a sala para o tocador e ainda assim dizia que tinha falado');
  });

  test('a second line actually sounds, instead of riding the first one\'s latch',
      () async {
    final player = SpeakingPlayer();
    final voice = service(player: player);

    final first = voice.play(_clip);
    await waitFor('o tocador soar', () => player.sounding);
    player.reachTheEnd();
    expect(await first, isTrue);

    final second = voice.play(_other);
    await waitFor('o tocador soar', () => player.sounding);

    expect(player.sounding, isTrue,
        reason: 'o player já se julgava tocando, então o play seguinte voltava na hora '
            'sem tocar nada, e o estado de "terminado" da linha anterior era lido como '
            'sucesso — a sala se dava por falada em silêncio');
    player.reachTheEnd();
    expect(await second, isTrue);
  });

  test('a line played to the end is still counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(player: player);

    final speaking = voice.play(_clip);
    await waitFor('o tocador soar', () => player.sounding);
    expect(player.sounding, isTrue,
        reason: 'o fim chegava antes do play e o aviso caia no vazio, entao a linha '
            'esperava os oito segundos do teto e voltava como nao ouvida');
    player.reachTheEnd();

    expect(await speaking, isTrue,
        reason: 'se tudo passar a valer falso a sala se declara doente estando sa');
  });
}
