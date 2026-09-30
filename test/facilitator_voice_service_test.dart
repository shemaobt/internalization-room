import 'dart:async';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:just_audio/just_audio.dart';

import 'fakes.dart';

const _clip = '/api/internalization-room/voice/aaa';
const _other = '/api/internalization-room/voice/bbb';
const _lenta = '/api/internalization-room/voice/lenta';

typedef _Open =
    Future<http.StreamedResponse> Function(
      String url, {
      int? from,
      String? ifRange,
    });

http.StreamedResponse _whole(List<int> bytes, {String etag = 'e1'}) =>
    http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      headers: {'etag': etag},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  late Directory library;
  late List<String> fetched;

  _Open roomAnswering(
    FutureOr<http.StreamedResponse> Function(http.BaseRequest request) answer,
  ) {
    final room = RoomRepository(
      client: MockClient.streaming((request, _) async {
        fetched.add(request.url.path);
        return answer(request);
      }),
    );
    addTearDown(room.dispose);
    return room.openClip;
  }

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
    open: roomAnswering((_) => _whole([1, 2, 3])),
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

  test(
    'a reply starts sounding on its first bytes, not after the whole clip',
    () async {
      final player = SpeakingPlayer();
      final body = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        player: player,
      );
      body.add([1, 2, 3]);

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      final heard = await player.arriving!.request(0);

      expect(
        await heard.stream.first,
        [1, 2, 3],
        reason:
            'o tablet baixava a resposta inteira antes de tocar, e a equipe '
            'ficava em silêncio esperando o arquivo todo numa rede lenta',
      );
      expect(fetched, [_clip]);

      body
        ..add([4, 5, 6])
        ..close();
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'a request past what has arrived waits for those bytes, instead of ending short',
    () async {
      final player = SpeakingPlayer();
      final body = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        player: player,
      );
      body.add([1, 2, 3]);

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      final tail = await player.arriving!.request(3);
      final got = <int>[];
      final served = tail.stream.forEach(got.addAll);
      body
        ..add([4, 5, 6])
        ..close();
      await served;

      expect(
        got,
        [4, 5, 6],
        reason:
            'o AVPlayer sonda o fim do arquivo antes de ele chegar, e um pedido '
            'além do que já tinha chegado terminava vazio no meio da fala',
      );
      expect(tail.offset, 3);
      expect(tail.sourceLength, 6);

      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'a line fetched, asked for and played at once is downloaded once',
    () async {
      final player = SpeakingPlayer();
      final bodies = <StreamController<List<int>>>[];
      final voice = FacilitatorVoiceService(
        open: roomAnswering((_) {
          final body = StreamController<List<int>>();
          bodies.add(body);
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: 3,
            headers: {'etag': 'e1'},
          );
        }),
        libraryDir: () async => library,
        player: player,
      );

      final fetching = voice.fetch(_clip);
      final speaking = voice.play(_clip);
      final asked = voice.clipFor(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      for (final body in bodies) {
        body
          ..add([1, 2, 3])
          ..close();
      }

      expect(
        fetched,
        [_clip],
        reason:
            'a pré-busca e o play abriam cada um o seu GET da mesma fala, '
            'pagando duas vezes a rede lenta que o streaming existe para poupar',
      );
      expect(await fetching, isTrue);
      expect((await asked).readAsBytesSync(), [1, 2, 3]);
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'a reply still arriving is not held, so a replay never gets it cut short',
    () async {
      final player = SpeakingPlayer();
      final body = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        player: player,
      );
      body.add([1, 2, 3]);

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await voice.holds(_clip),
        isFalse,
        reason:
            'um .mp3 escrito enquanto a fala ainda chega passa no length > 0, e '
            'o "ouvir de novo" tocaria a metade que tinha chegado',
      );
      expect(File('${library.path}/aaa.mp3').existsSync(), isFalse);

      body
        ..add([4, 5, 6])
        ..close();
      await voice.clipFor(_clip);

      expect(File('${library.path}/aaa.mp3').readAsBytesSync(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(File('${library.path}/aaa.mp3.novo').existsSync(), isFalse);
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'a streamed line the platform cannot time is bounded by its size, not by ninety seconds',
    () async {
      final player = SpeakingPlayer()..lineLength = null;
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (request) =>
              _whole(List.filled(request.url.path == _clip ? 1600 : 32000, 0)),
        ),
        libraryDir: () async => library,
        player: player,
        lineGrace: const Duration(milliseconds: 30),
      );

      expect(
        await voice.play(_clip).timeout(const Duration(seconds: 5)),
        isFalse,
        reason:
            'sem a duração da plataforma o teto caía nos 90 s do desconhecido, e '
            'uma fala de 0,1 s travada deixava a sala muda um minuto e meio',
      );

      final longer = voice.play(_other);
      await waitFor('o tocador soar', () => player.sounding);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        player.sounding,
        isTrue,
        reason: '32 000 bytes a 128 kbps são 2 s de fala; desistir antes corta',
      );
      player.reachTheEnd();
      expect(await longer, isTrue);
    },
  );

  testWidgets('a long line sent at a lower bitrate is not cut before its end', (
    tester,
  ) async {
    const grace = Duration(seconds: 8);
    final player = SpeakingPlayer()..lineLength = null;
    final body = StreamController<List<int>>();
    final voice = FacilitatorVoiceService(
      open: (_, {from, ifRange}) async => http.StreamedResponse(
        body.stream,
        200,
        contentLength: 480000,
        headers: {'etag': 'e1'},
      ),
      libraryDir: () async => library,
      player: player,
      lineGrace: grace,
    );

    bool? heard;
    unawaited(voice.play(_clip).then((played) => heard = played));
    await tester.pump();
    expect(player.sounding, isTrue);

    await tester.pump(const Duration(seconds: 60) + grace);
    expect(
      player.sounding,
      isTrue,
      reason:
          '480 000 bytes a 64 kbps são 60 s de fala; o teto lido a 128 kbps '
          'desistia aos 38 s e dava a fala como não ouvida no meio da frase',
    );

    player.reachTheEnd();
    unawaited(body.close());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(heard, isTrue);
  });

  test(
    'with streaming switched off a reply reaches the player only once it is whole',
    () async {
      final player = SpeakingPlayer();
      final body = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        playsAsItArrives: false,
        libraryDir: () async => library,
        player: player,
      );
      body.add([1, 2, 3]);

      final speaking = voice.play(_clip);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        player.sounding,
        isFalse,
        reason:
            'a chave existe para o iPad cujo AVPlayer se enrosca no streaming: '
            'desligada, nada pode chegar ao tocador antes do arquivo inteiro',
      );

      body
        ..add([4, 5, 6])
        ..close();
      await waitFor('o tocador soar', () => player.sounding);
      expect(player.arriving, isNull);
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );

  test(
    'a line is ready on its first bytes, or only once whole with streaming switched off',
    () async {
      for (final streams in [true, false]) {
        fetched.clear();
        final body = StreamController<List<int>>();
        final voice = FacilitatorVoiceService(
          open: roomAnswering(
            (_) => http.StreamedResponse(
              body.stream,
              200,
              contentLength: 6,
              headers: {'etag': 'e1'},
            ),
          ),
          playsAsItArrives: streams,
          libraryDir: () async =>
              Directory('${library.path}/$streams').create(),
        );
        var ready = false;
        unawaited(voice.ready(_clip).then((_) => ready = true));
        body.add([1, 2, 3]);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          ready,
          streams,
          reason:
              'a sala fica em "pensando" até a fala estar pronta; com a chave '
              'desligada, pronta volta a ser o arquivo inteiro como antes',
        );
        body
          ..add([4, 5, 6])
          ..close();
        await waitFor('a fala ficar pronta', () => ready);
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
    // A raw exception, not one of the room's: through the repository a dead socket is
    // already `RoomUnavailable`, and that one is the room's failure and is let through
    // (the test after this one).
    final voice = FacilitatorVoiceService(
      open: (_, {from, ifRange}) async =>
          throw const SocketException('sem rede'),
      libraryDir: () async => library,
    );

    expect(await voice.play(_clip), isFalse);
  });

  test(
    'a clip the room will not serve fails as the room, not as a line that will not play',
    () async {
      for (final (status, failure) in [
        (403, isA<Refused>()),
        (401, isA<Refused>()),
        (503, isA<NetworkFailed>()),
      ]) {
        final voice = FacilitatorVoiceService(
          open: roomAnswering(
            (_) => http.StreamedResponse(const Stream.empty(), status),
          ),
          libraryDir: () async => library,
        );

        await expectLater(
          voice.clipFor(_clip),
          throwsA(failure),
          reason:
              'a recusa do servidor chegava como um erro qualquer e a sala a '
              'lia como uma fala que não toca, sem nunca chamar ninguém',
        );
      }
    },
  );

  test(
    'a reply that breaks before any byte arrives fails as the room being gone',
    () async {
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            Stream.error(http.ClientException('a conexão caiu')),
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
      );

      await expectLater(
        voice.clipFor(_clip),
        throwsA(isA<NetworkFailed>()),
        reason:
            'a queda no meio do corpo subia como ClientException cru, que a '
            'sala não reconhece como a rede indo embora',
      );
    },
  );

  test(
    'a player waiting on bytes that will never come is told, instead of hanging',
    () async {
      final player = SpeakingPlayer();
      final body = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        player: player,
      );

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      final tail = await player.arriving!.request(0);
      body.addError(http.ClientException('a conexão caiu'));

      await expectLater(
        tail.stream.toList().timeout(const Duration(seconds: 2)),
        throwsA(isA<NetworkFailed>()),
        reason:
            'o pedido do tocador esperava para sempre por bytes de um download '
            'que já tinha morrido',
      );
      player.reachTheEnd();
      await speaking;
    },
  );

  test(
    'a reply cut mid-way resumes from the byte it stopped at, and the file is the whole clip',
    () async {
      final asked = <http.BaseRequest>[];
      final first = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering((request) {
          asked.add(request);
          if (asked.length == 1) {
            return http.StreamedResponse(
              first.stream,
              200,
              contentLength: 6,
              headers: {'etag': 'e1'},
            );
          }
          return http.StreamedResponse(
            Stream.value([4, 5, 6]),
            206,
            contentLength: 3,
            headers: {'etag': 'e1', 'content-range': 'bytes 3-5/6'},
          );
        }),
        libraryDir: () async => library,
      );

      final arriving = voice.clipFor(_clip);
      first
        ..add([1, 2, 3])
        ..addError(http.ClientException('a conexão caiu'));

      expect(
        (await arriving).readAsBytesSync(),
        [1, 2, 3, 4, 5, 6],
        reason:
            'uma queda no meio perdia a fala inteira, e numa rede de campo a '
            'queda é o caso comum, não a exceção',
      );
      expect(asked, hasLength(2));
      expect(asked[1].headers['Range'], 'bytes=3-');
      expect(
        asked[1].headers['If-Range'],
        'e1',
        reason:
            'sem o If-Range, uma retomada contra outra renderização da mesma '
            'fala emendava duas vozes no meio de uma frase',
      );
    },
  );

  test(
    'a reply that keeps ending short gives up, instead of asking forever',
    () async {
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (request) => request.headers.containsKey('Range')
              ? http.StreamedResponse(
                  const Stream.empty(),
                  206,
                  contentLength: 3,
                  headers: {'etag': 'e1', 'content-range': 'bytes 3-5/6'},
                )
              : http.StreamedResponse(
                  Stream.value([1, 2, 3]),
                  200,
                  contentLength: 6,
                  headers: {'etag': 'e1'},
                ),
        ),
        libraryDir: () async => library,
      );

      await expectLater(
        voice.clipFor(_clip).timeout(const Duration(seconds: 2)),
        throwsA(isA<Refused>()),
        reason:
            'uma retomada que não traz byte novo pedia de novo sem fim, e a '
            'fala nunca terminava nem falhava',
      );
      expect(fetched, hasLength(2));
    },
  );

  test(
    'a clip whose resumes keep starting over gives up, instead of pulling forever',
    () async {
      for (final (drop, failure) in [
        (null, isA<Refused>()),
        (http.ClientException('a conexão caiu'), isA<NetworkFailed>()),
      ]) {
        fetched.clear();
        Stream<List<int>> cutMidway() async* {
          yield [1, 2, 3];
          if (drop != null) throw drop;
        }

        final voice = FacilitatorVoiceService(
          open: roomAnswering((_) async {
            // A real pause between answers: a loop that never ends would otherwise
            // starve the timer below and hang the suite instead of failing it.
            await Future<void>.delayed(Duration.zero);
            return http.StreamedResponse(
              cutMidway(),
              200,
              contentLength: 6,
              headers: {'etag': 'e1'},
            );
          }),
          libraryDir: () async => library,
        );

        await expectLater(
          voice.clipFor(_clip).timeout(const Duration(seconds: 2)),
          throwsA(failure),
          reason:
              'um backend sem Range responde 200 a toda retomada; o recomeço '
              'zerava o que tinha chegado, e num link que cai sempre a fala '
              'baixava o MP3 inteiro de novo sem fim, sem nunca falhar',
        );
        expect(
          fetched,
          hasLength(4),
          reason:
              'a primeira resposta, dois recomeços, e a retomada que seria o '
              'terceiro é onde a fala desiste',
        );
      }
    },
  );

  test(
    'a resume answered with the whole clip starts over, and never splices two renderings',
    () async {
      final first = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (request) => request.headers.containsKey('Range')
              ? _whole([7, 8, 9, 10, 11, 12])
              : http.StreamedResponse(
                  first.stream,
                  200,
                  contentLength: 6,
                  headers: {'etag': 'e1'},
                ),
        ),
        libraryDir: () async => library,
      );

      final arriving = voice.clipFor(_clip);
      first
        ..add([1, 2, 3])
        ..addError(http.ClientException('a conexão caiu'));

      expect(
        (await arriving).readAsBytesSync(),
        [7, 8, 9, 10, 11, 12],
        reason:
            'um 200 na retomada é o servidor mandando tudo de novo, talvez outra '
            'renderização; colar o que veio depois do byte 3 emendava duas vozes',
      );
    },
  );

  test(
    'a resume that cannot prove it is the same rendering starts over from nothing',
    () async {
      for (final firstTag in <String?>['e1', null]) {
        fetched.clear();
        final asked = <http.BaseRequest>[];
        final first = StreamController<List<int>>();
        final voice = FacilitatorVoiceService(
          open: roomAnswering((request) {
            asked.add(request);
            if (asked.length == 1) {
              return http.StreamedResponse(
                first.stream,
                200,
                contentLength: 6,
                headers: {'etag': ?firstTag},
              );
            }
            if (request.headers.containsKey('Range')) {
              return http.StreamedResponse(
                Stream.value([10, 11, 12]),
                206,
                contentLength: 3,
                headers: {
                  'etag': ?(firstTag == null ? null : 'e2'),
                  'content-range': 'bytes 3-5/6',
                },
              );
            }
            return _whole([7, 8, 9, 10, 11, 12], etag: 'e2');
          }),
          libraryDir: () async =>
              Directory('${library.path}/${firstTag ?? 'sem'}').create(),
        );

        final arriving = voice.clipFor(_clip);
        first
          ..add([1, 2, 3])
          ..addError(http.ClientException('a conexão caiu'));

        expect(
          (await arriving).readAsBytesSync(),
          [7, 8, 9, 10, 11, 12],
          reason:
              'um 206 de outra etiqueta (ou de nenhuma) é um servidor que '
              'ignorou o If-Range: o resto era de outra renderização',
        );
        expect(asked.last.headers.containsKey('Range'), isFalse);
      }
    },
  );

  test(
    'a partial answer that is not the part still missing starts over, instead of overrunning the clip',
    () async {
      final asked = <http.BaseRequest>[];
      final first = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering((request) {
          asked.add(request);
          if (request.headers.containsKey('Range')) {
            return http.StreamedResponse(
              Stream.value([1, 2, 3, 4, 5, 6]),
              206,
              contentLength: 6,
              headers: {'etag': 'e1', 'content-range': 'bytes 0-5/6'},
            );
          }
          if (asked.length == 1) {
            return http.StreamedResponse(
              first.stream,
              200,
              contentLength: 6,
              headers: {'etag': 'e1'},
            );
          }
          return _whole([1, 2, 3, 4, 5, 6]);
        }),
        libraryDir: () async => library,
      );

      final arriving = voice.clipFor(_clip);
      first
        ..add([1, 2, 3])
        ..addError(http.ClientException('a conexão caiu'));

      expect(
        (await arriving).readAsBytesSync(),
        [1, 2, 3, 4, 5, 6],
        reason:
            'um Range que ignorava o deslocamento respondia 206 com a fala '
            'inteira sob a mesma etiqueta; escrita depois do byte 3 ela passava '
            'do fim do buffer num RangeError, que nenhum on Exception da sala pega',
      );
      expect(asked.last.headers.containsKey('Range'), isFalse);
    },
  );

  test(
    'a player that heard the first rendering is never handed the second',
    () async {
      final player = SpeakingPlayer();
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (request) => http.StreamedResponse(
            request.headers.containsKey('Range') ? second.stream : first.stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        player: player,
      );

      final speaking = voice.play(_clip);
      await waitFor('o tocador soar', () => player.sounding);
      final heard = await player.arriving!.request(0);
      final got = <int>[];
      final served = heard.stream.forEach(got.addAll);
      first.add([1, 2, 3]);
      await waitFor('os primeiros bytes chegarem', () => got.length == 3);
      first.addError(http.ClientException('a conexão caiu'));
      second
        ..add([7, 8, 9, 10, 11, 12])
        ..close();

      await expectLater(served, throwsA(isA<Refused>()));
      expect(
        got,
        [1, 2, 3],
        reason:
            'o tocador já tinha ouvido o começo de uma renderização e recebia o '
            'resto da outra: a frase mudava de voz no meio',
      );
      player.reachTheEnd();
      await speaking;
    },
  );

  test(
    'a reply whose bytes stop coming is given up as slow, not waited on forever',
    () async {
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(
            StreamController<List<int>>().stream,
            200,
            contentLength: 6,
            headers: {'etag': 'e1'},
          ),
        ),
        libraryDir: () async => library,
        lineGrace: const Duration(milliseconds: 30),
        loadCeiling: const Duration(milliseconds: 30),
      );

      await expectLater(
        voice.clipFor(_clip).timeout(const Duration(seconds: 2)),
        throwsA(isA<NetworkFailed>()),
        reason:
            'o fetchClip inteiro tinha teto; o corpo em stream não, e uma '
            'conexão muda prendia a fala e todo play dela até reabrir o app',
      );
    },
  );

  test(
    'a reply with no declared size fails as the room, not as a crash',
    () async {
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (_) => http.StreamedResponse(Stream.value([1, 2, 3]), 200),
        ),
        libraryDir: () async => library,
      );

      await expectLater(
        voice.clipFor(_clip),
        throwsA(isA<Refused>()),
        reason:
            'sem Content-Length o buffer não tem tamanho, e o ! virava um '
            'TypeError que nenhum on Exception da sala pega',
      );
    },
  );

  test(
    'a fetch that fails because the room is down is not a failure to play',
    () async {
      Future<void> expectSurfaced(Exception error) async {
        final voice = FacilitatorVoiceService(
          open: (_, {from, ifRange}) async => throw error,
          libraryDir: () async => library,
        );

        await expectLater(
          voice.play(_clip),
          throwsA(same(error)),
          reason:
              'o GET do clipe caía no mesmo catch do player e virava "não '
              'toca" — uma queda de rede ou um 5xx da sala precisam chegar '
              'ao mesmo tratamento que o POST do turno já recebe',
        );
      }

      await expectSurfaced(const Refused('BAD_REQUEST', 'HTTP 503'));
      await expectSurfaced(const NetworkFailed('sem rede'));
      await expectSurfaced(const NetworkFailed('timeout'));
      await expectSurfaced(const Refused('UNAUTHORIZED'));
    },
  );

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

  test('a clip that opens with no length is not counted as heard', () async {
    final player = SpeakingPlayer()..lineLength = Duration.zero;
    final voice = service(player: player);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        player.reachTheEnd,
      ),
    );

    expect(
      await voice.play(_clip),
      isFalse,
      reason:
          'um clipe sem duração "terminava" na hora, o player dizia completo '
          'e a sala contava como falada uma linha que não soou',
    );
    expect(player.sounding, isFalse);
  });

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
        open: roomAnswering((_) => _whole([1, 2, 3])),
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
    'a library directory that fails once is tried again, not remembered as broken',
    () async {
      var attempt = 0;
      final voice = FacilitatorVoiceService(
        open: roomAnswering((_) => _whole([1, 2, 3])),
        libraryDir: () async {
          attempt++;
          if (attempt == 1) throw Exception('disco cheio');
          return library;
        },
      );

      await voice.holds(_clip);
      expect(attempt, 1);

      await voice.holds(_clip);
      expect(
        attempt,
        2,
        reason:
            'a Future rejeitada ficava guardada para sempre; toda chamada '
            'seguinte reusava a mesma falha em vez de tentar o diretório de novo',
      );
    },
  );

  test(
    'a stale .novo leftover is swept; a fresh one, or one still downloading, is not',
    () async {
      final player = SpeakingPlayer();
      final downloading = Completer<List<int>>();
      final voice = FacilitatorVoiceService(
        open: roomAnswering(
          (request) => request.url.path == _lenta
              ? http.StreamedResponse(
                  Stream.fromFuture(downloading.future),
                  200,
                  contentLength: 3,
                  headers: {'etag': 'e1'},
                )
              : _whole([1, 2, 3]),
        ),
        libraryDir: () async => library,
        player: player,
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

      downloading.complete([9, 9, 9]);
      await arriving;
      player.reachTheEnd();
      expect(await speaking, isTrue);
    },
  );
}
