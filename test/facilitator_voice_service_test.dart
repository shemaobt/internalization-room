import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:just_audio/just_audio.dart';

import 'fakes.dart';

const _clip = '/api/internalization-room/voice/aaa';
const _other = '/api/internalization-room/voice/bbb';
const _lenta = '/api/internalization-room/voice/lenta';

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

  FacilitatorVoiceService service({
    AudioPlayer? player,
    Duration? grace,
    Duration? loadCeiling,
  }) => FacilitatorVoiceService(
    fetch: (url) async {
      fetched.add(url);
      return Uint8List.fromList([1, 2, 3]);
    },
    libraryDir: () async => library,
    player: player,
    lineGrace: grace,
    loadCeiling: loadCeiling,
  );

  test(
    'two callers asking for the same line at once share one download',
    () async {
      final voice = service();

      final together = await Future.wait([
        voice.clipFor(_clip),
        voice.clipFor(_clip),
        voice.clipFor(_clip),
      ]);

      expect(
        fetched,
        [_clip],
        reason:
            'a abertura busca o segundo movimento enquanto o primeiro ainda '
            'está sendo falado, e dois downloads da mesma fala escreviam o mesmo '
            'arquivo de staging e o renomeavam por cima um do outro',
      );
      expect(together.map((file) => file.path).toSet(), hasLength(1));
      for (final file in together) {
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      }
    },
  );

  test('a line already fetched alongside its own play still plays', () async {
    final voice = service();

    final arriving = voice.fetch(_clip);
    final file = await voice.clipFor(_clip);
    await arriving;

    expect(
      file.existsSync(),
      isTrue,
      reason:
          'o perdedor da corrida estourava, o estouro era engolido como '
          'uma fala que não toca, e a sala ficava muda entre dois fôlegos',
    );
    expect(fetched, [_clip]);
  });

  test('a line already heard is never fetched again', () async {
    final voice = service();

    await voice.clipFor(_clip);
    await voice.clipFor(_other);
    await voice.clipFor(_clip);

    expect(
      fetched,
      [_clip, _other],
      reason:
          'o endereço é endereçado por conteúdo — os bytes nunca mudam, '
          'então buscar de novo é pagar duas vezes pela mesma frase',
    );
  });

  test(
    'each line keeps its own file, instead of overwriting the last',
    () async {
      final voice = service();

      await voice.clipFor(_clip);
      await voice.clipFor(_other);

      expect(library.listSync().whereType<File>(), hasLength(2));
    },
  );

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

    expect(
      fetched,
      [_clip],
      reason:
          'um arquivo de zero byte de uma escrita interrompida tocaria '
          'silêncio, e a equipe ouve cada frase uma vez só',
    );
  });

  test('a line the player paused in the middle is not counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(player: player);

    final speaking = voice.play(_clip);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    player.pauseIt();

    expect(
      await speaking,
      isFalse,
      reason:
          'o just_audio resolve o future do play() na pausa e no stop, nao so '
          'no fim — a sala contava como falada uma linha que a equipe nao ouviu',
    );
  });

  test('a line that overruns its ceiling is not counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(
      player: player,
      grace: const Duration(milliseconds: 30),
    );

    expect(
      await voice.play(_clip),
      isFalse,
      reason: 'a sala para o tocador e ainda assim dizia que tinha falado',
    );
  });

  test(
    'a line the player never opens is given up, not waited on forever',
    () async {
      final player = SpeakingPlayer()..neverLoads = true;
      final voice = service(
        player: player,
        grace: const Duration(milliseconds: 30),
        loadCeiling: const Duration(milliseconds: 30),
      );

      expect(
        await voice.play(_clip).timeout(const Duration(seconds: 5)),
        isFalse,
        reason:
            'o teto só cobria o play(); um setFilePath que nunca resolvia deixava '
            'a sala em "falando" para sempre, e desde que a sala parou de julgar a '
            'própria fala (ENG-935) ninguém mais chamaria uma pessoa',
      );
    },
  );

  test(
    'a player that wedges on stop still reports the line as not heard',
    () async {
      final player = SpeakingPlayer()..neverStops = true;
      final voice = service(
        player: player,
        grace: const Duration(milliseconds: 30),
        loadCeiling: const Duration(milliseconds: 30),
      );

      expect(
        await voice.play(_clip).timeout(const Duration(seconds: 5)),
        isFalse,
        reason:
            'o stop() antes da carga e o stop() da desistência corriam sem teto '
            'contra o mesmo tocador que acabou de falhar; se ele travasse ali, a '
            'linha nunca era dada como não ouvida',
      );
    },
  );

  test(
    'a second line actually sounds, instead of riding the first one\'s latch',
    () async {
      final player = SpeakingPlayer();
      final voice = service(player: player);

      final first = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      player.reachTheEnd();
      expect(await first, isTrue);

      final second = voice.play(_other);
      await waitFor('o tocador soar', () => player.sounding);

      expect(
        player.sounding,
        isTrue,
        reason:
            'o player já se julgava tocando, então o play seguinte voltava na hora '
            'sem tocar nada, e o estado de "terminado" da linha anterior era lido como '
            'sucesso — a sala se dava por falada em silêncio',
      );
      player.reachTheEnd();
      expect(await second, isTrue);
    },
  );

  test(
    'onSoundStart fires when the player itself says it is sounding, not when play() is called',
    () async {
      final player = SpeakingPlayer();
      final voice = service(player: player);
      var started = false;

      final speaking = voice.play(_clip, onSoundStart: () => started = true);
      await waitFor('o tocador soar', () => player.sounding);

      expect(
        started,
        isFalse,
        reason:
            'o just_audio pode levar um tempo real para começar a soar depois '
            'do play() — contar do play() emitido mediria o carregamento, não '
            'a espera que a equipe sente',
      );

      player.startSounding();
      await waitFor('onSoundStart disparar', () => started);
      player.reachTheEnd();

      expect(await speaking, isTrue);
    },
  );

  test(
    'onSoundStart fires once, not moved by the iOS quirk of reporting playing again at the end',
    () async {
      final player = SpeakingPlayer();
      final voice = service(player: player);
      var starts = 0;

      final speaking = voice.play(_clip, onSoundStart: () => starts++);
      await waitFor('o tocador soar', () => player.sounding);

      player.startSounding();
      await waitFor('onSoundStart disparar', () => starts == 1);

      player.startSounding();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        starts,
        1,
        reason:
            'o iOS nunca limpa playing no fim de uma fala — o mesmo evento '
            'que soa o começo soa de novo o fim, e um ouvinte que não se '
            'desliga move a marca para o fim da fala inteira',
      );
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test('a line played to the end is still counted as heard', () async {
    final player = SpeakingPlayer();
    final voice = service(player: player);

    final speaking = voice.play(_clip);
    await waitFor('o tocador soar', () => player.sounding);
    expect(
      player.sounding,
      isTrue,
      reason:
          'o fim chegava antes do play e o aviso caia no vazio, entao a linha '
          'esperava os oito segundos do teto e voltava como nao ouvida',
    );
    player.reachTheEnd();

    expect(
      await speaking,
      isTrue,
      reason:
          'se tudo passar a valer falso a sala se declara doente estando sa',
    );
  });

  test(
    'the clip cache is pruned once the reply actually sounds, not while it downloads',
    () async {
      final player = SpeakingPlayer();
      final voice = service(player: player);

      for (var i = 0; i < 65; i++) {
        await voice.clipFor('/api/internalization-room/voice/c$i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        library.listSync().whereType<File>(),
        hasLength(65),
        reason:
            'com o cache cheio, a sala listava e ordenava cada clipe guardado '
            'para apagar o mais velho bem na hora em que a resposta começava a tocar',
      );

      final speaking = voice.play('/api/internalization-room/voice/c64');
      await waitFor('o tocador soar', () => player.sounding);

      expect(
        library.listSync().whereType<File>(),
        hasLength(65),
        reason:
            'o play() já foi chamado, mas o tocador ainda não confirmou que soa '
            '— podar aqui é a mesma trava de antes, só que adiada um passo',
      );

      player.startSounding();
      await waitFor(
        'a poda rodar',
        () => library.listSync().whereType<File>().length <= 60,
      );

      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'the budget prune counts only the mp3 clips, never a staging leftover',
    () async {
      final player = SpeakingPlayer();
      final voice = service(player: player);

      for (var i = 0; i < 65; i++) {
        File('${library.path}/c$i.mp3')
          ..writeAsBytesSync([1])
          ..setLastModifiedSync(DateTime(2026).add(Duration(minutes: i)));
      }
      for (var i = 0; i < 3; i++) {
        File('${library.path}/staging$i.mp3.novo').writeAsBytesSync([1]);
      }

      final speaking = voice.play('/api/internalization-room/voice/played');
      await waitFor('o tocador soar', () => player.sounding);
      player.startSounding();
      await waitFor(
        'a poda terminar',
        () =>
            library
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.mp3'))
                .length <=
            60,
      );

      expect(
        library.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.mp3'),
        ),
        hasLength(60),
        reason: 'os 60 clipes mais recentes ficam, o resto sai',
      );
      expect(
        library.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.novo'),
        ),
        hasLength(3),
        reason:
            'contar o .novo no orçamento apaga um download em andamento por '
            'baixo do outro',
      );
      expect(File('${library.path}/c0.mp3').existsSync(), isFalse);
      expect(File('${library.path}/c64.mp3').existsSync(), isTrue);
      expect(File('${library.path}/played.mp3').existsSync(), isTrue);

      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'the library directory is resolved once, not on every call that needs it',
    () async {
      var calls = 0;
      final voice = FacilitatorVoiceService(
        fetch: (url) async {
          fetched.add(url);
          return Uint8List.fromList([1, 2, 3]);
        },
        libraryDir: () async {
          calls++;
          return library;
        },
      );

      await voice.holds(_clip);
      await voice.clipFor(_clip);
      await voice.holds(_other);

      expect(
        calls,
        1,
        reason:
            'cada holds() e clipFor() refazia getApplicationSupportDirectory() '
            'mais create(recursive: true), disco de novo a cada pergunta',
      );
    },
  );

  test(
    'a stale .novo leftover is swept; a fresh one, or one still downloading, is not',
    () async {
      final player = SpeakingPlayer();
      final downloading = Completer<Uint8List>();
      final voice = FacilitatorVoiceService(
        fetch: (url) async {
          fetched.add(url);
          return url == _lenta
              ? downloading.future
              : Uint8List.fromList([1, 2, 3]);
        },
        libraryDir: () async => library,
        player: player,
        staleStagingAge: const Duration(milliseconds: 30),
      );

      File('${library.path}/orfao.mp3.novo')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 20)),
        );
      File('${library.path}/fresco.mp3.novo').writeAsBytesSync([1]);

      final arriving = voice.clipFor(_lenta);
      await waitFor('a busca lenta começar', () => fetched.contains(_lenta));
      File('${library.path}/lenta.mp3.novo')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 20)),
        );

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      player.startSounding();

      await waitFor(
        'a poda varrer o órfão',
        () => !File('${library.path}/orfao.mp3.novo').existsSync(),
      );

      expect(
        File('${library.path}/fresco.mp3.novo').existsSync(),
        isTrue,
        reason:
            'um .novo recente pode ser uma escrita em andamento; a idade '
            'segura existe exatamente para não confundir isso com lixo',
      );
      expect(
        File('${library.path}/lenta.mp3.novo').existsSync(),
        isTrue,
        reason:
            'a linha ainda está em _arriving — uma busca lenta não é uma '
            'baixa morta, mesmo que o arquivo pareça velho',
      );

      downloading.complete(Uint8List.fromList([9, 9, 9]));
      await arriving;
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );
}
