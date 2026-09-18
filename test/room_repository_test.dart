import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';

String _turnBody({bool usedFailSafe = false, bool degraded = false}) => jsonEncode({
      'session_id': 'sessao-1',
      'audio_base64': base64Encode([1, 2, 3]),
      'mime_type': 'audio/mpeg',
      'transcript': '',
      'peer_cue': false,
      'used_fail_safe': usedFailSafe,
      'degraded': degraded,
      'coverage': {
        'engaged': 0,
        'surfaced': 0,
        'total': 29,
        'absence_index': 13,
      },
      'done': false,
    });

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test('the opening turn carries no body at all', () async {
    late http.BaseRequest seen;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen = request;
        return http.Response(_turnBody(), 200);
      }),
    );
    addTearDown(repository.dispose);

    await repository.openSession('sessao-1');

    expect(seen.contentLength, anyOf(isNull, 0),
        reason: 'um multipart sem nenhuma parte é um corpo que o servidor não '
            'consegue ler, e a recusa chega ao app como se fosse falta de rede');
    expect(seen.headers['content-type'] ?? '', isNot(contains('multipart')));
    expect(seen.headers['X-Room-Key'], 'k');
  });

  test('a retried opening turn carries the first attempt\'s id, not a fresh one',
      () async {
    final seenBodies = <String>[];
    final repository = RoomRepository(
      client: MockClient((request) async {
        seenBodies.add(request.body);
        return http.Response(_turnBody(), 200);
      }),
    );
    addTearDown(repository.dispose);

    await repository.openSession('sessao-1', turnId: 'turno-1');
    await repository.openSession('sessao-1', turnId: 'turno-1');

    expect(seenBodies, ['turn_id=turno-1', 'turn_id=turno-1'],
        reason: 'o servidor so responde do jeito que ja respondeu se o id do '
            'reenvio bater com o da primeira tentativa — um id novo a cada '
            'chamada e a mesma falha de nunca reconhecer um retry');
  });

  test('a turn with a recording carries the recording, not an empty envelope',
      () async {
    late String seenBody;
    late http.BaseRequest seen;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen = request;
        seenBody = request.body;
        return http.Response(_turnBody(), 200);
      }),
    );
    addTearDown(repository.dispose);

    final file = await _tempRecording();
    await repository.sendTurn('sessao-1', file);

    expect(seen.headers['content-type'], contains('multipart/form-data'));
    expect(seenBody, contains('name="file"'),
        reason: 'o cabeçalho multipart é escrito mesmo sem nenhuma parte — só o '
            'corpo prova que a gravação foi junto');
    expect(seenBody, contains('filename='));
  });

  test('a canned turn says whether the room was in trouble, not only that it was canned',
      () async {
    var inTrouble = true;
    final repository = RoomRepository(
      client: MockClient((request) async =>
          http.Response(_turnBody(usedFailSafe: true, degraded: inTrouble), 200)),
    );
    addTearDown(repository.dispose);

    final broken = await repository.sendTurn('sessao-1', await _tempRecording());
    inTrouble = false;
    final ensaiando = await repository.sendTurn('sessao-1', await _tempRecording());

    expect(broken.degraded, isTrue);
    expect(ensaiando.usedFailSafe, isTrue);
    expect(ensaiando.degraded, isFalse,
        reason: 'a sala responde da lata tanto quando falha quanto quando a equipe ensaia '
            'na língua dela, e os dois campos juntos só provam alguma coisa se a resposta '
            'trouxer a combinação que existe por causa da correção');
  });

  test('a turn carries the id classification watches, and whether classification is still running',
      () async {
    final repository = RoomRepository(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'turn_id': 'turno-9',
              'classification_pending': true,
            }),
            200,
          )),
    );
    addTearDown(repository.dispose);

    final turn = await repository.openSession('sessao-1');

    expect(turn.turnId, 'turno-9');
    expect(turn.classificationPending, isTrue);
  });

  test('the panorama is asked for by name, a plain session is not', () async {
    final asked = <String>[];
    final types = <String>[];
    final repository = RoomRepository(
      client: MockClient((request) async {
        asked.add(request.body);
        types.add(request.headers['content-type'] ?? '');
        return http.Response(
          jsonEncode({
            'session_id': 's',
            'pericope': 'P01',
            'status': 'in_progress',
            'coverage': {
              'engaged': 0,
              'surfaced': 0,
              'total': 29,
              'absence_index': 13,
            },
            'done': false,
          }),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);

    await repository.createSession(pericope: 'OV', language: 'pt');
    await repository.createSession(afterSession: 'panorama-1', language: 'pt');
    await repository.createSession(language: 'en');

    expect(asked, [
      '{"pericope":"OV","language":"pt"}',
      '{"after_session":"panorama-1","language":"pt"}',
      '{"language":"en"}',
    ], reason: 'nada do que a sala fala é feito aqui — um pedido que não diz a '
        'língua volta no idioma padrão do servidor e a equipe ouve outra');
    expect(types, everyElement(contains('application/json')),
        reason: 'sem esse cabeçalho o FastAPI responde 422 e o app desenha '
            'falta de rede');
  });

  test('a tablet with no device of its own asks for a code without naming one', () async {
    late http.BaseRequest seen;
    late String body;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen = request;
        body = request.body;
        return http.Response(
          jsonEncode({
            'device_id': 'aparelho-1',
            'code': 'QHF-3M7K',
            'expires_at': '2026-08-26T23:15:00Z',
          }),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);

    final asked = await repository.askForACode(null);

    expect(seen.url.path, '/api/internalization-room/devices/code');
    expect(body, '{}',
        reason: 'um device_id nulo virava a string "null" no corpo e o servidor '
            'procurava um aparelho com esse id');
    expect(seen.headers['X-Room-Key'], 'k');
    expect(asked.code, 'QHF-3M7K');
    expect(asked.deviceId, 'aparelho-1');
  });

  test('a tablet whose code ran out asks again under the device it already has', () async {
    late String body;
    final repository = RoomRepository(
      client: MockClient((request) async {
        body = request.body;
        return http.Response(
          jsonEncode({
            'device_id': 'aparelho-1',
            'code': 'WKD-2QP4',
            'expires_at': '2026-08-26T23:30:00Z',
          }),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);

    await repository.askForACode('aparelho-1');

    expect(body, '{"device_id":"aparelho-1"}',
        reason: 'sem o id, cada código novo abandonava um aparelho e a mesa via '
            'um código diferente do que tinha anotado');
  });

  test('an unreadable expiry is a code with no expiry, not a code born dead', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'device_id': 'aparelho-1',
              'code': 'QHF-3M7K',
              'expires_at': 'sometime after lunch',
            }),
            200,
          )),
    );
    addTearDown(repository.dispose);

    final asked = await repository.askForACode(null);

    expect(asked.expiresAt, isNull,
        reason: 'um vencimento no passado como padrão pedia um código novo a cada '
            'volta do relógio, e a mesa nunca via o mesmo duas vezes');
  });

  test('a device nobody has claimed answers nothing, and nothing is not a failure', () async {
    late http.BaseRequest seen;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      }),
    );
    addTearDown(repository.dispose);

    final link = await repository.readTheLink('aparelho-1');

    expect(seen.url.path, '/api/internalization-room/devices/aparelho-1/link');
    expect(link, isNull,
        reason: 'um 204 caía no ramo de não-200 e virava RoomBroke, então esperar '
            'pela mesa parecia a sala quebrada');
  });

  test('a claimed device comes back naming the team it belongs to', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response(
            jsonEncode({'project_id': 'equipe-terena', 'label': 'prateleira'}),
            200,
          )),
    );
    addTearDown(repository.dispose);

    final link = await repository.readTheLink('aparelho-1');

    expect(link?.projectId, 'equipe-terena');
  });

  test('a link with no team named is a room failure, not a team called nothing',
      () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response('{"label":"prateleira"}', 200)),
    );
    addTearDown(repository.dispose);

    expect(
      () => repository.readTheLink('aparelho-1'),
      throwsA(isA<RoomBroke>()),
      reason: 'um project_id ausente virava equipe "" — o aparelho gravava isso em disco, '
          'dava-se por vinculado, e a tela de instalação nunca mais voltava',
    );
  });

  test('a code with no code in it is a room failure, not an empty screen', () async {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response('{"expires_at":"2026-08-26T23:15:00Z"}', 200),
      ),
    );
    addTearDown(repository.dispose);

    expect(
      () => repository.askForACode(null),
      throwsA(isA<RoomBroke>()),
      reason: 'a mesa não pode digitar um código que a tela não mostrou',
    );
  });

  test('a malformed answer is a room failure, never a crash', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response('{"nada":1}', 200)),
    );
    addTearDown(repository.dispose);

    expect(
      () => repository.createSession(language: 'pt'),
      throwsA(isA<RoomBroke>()),
      reason: 'um TypeError escapa de todo `on Exception` e trava a sala em '
          'pensando, sem gesto e sem voz',
    );
  });

  test('each refusal keeps its own meaning', () async {
    Future<void> expectStatus(int status, Matcher matcher) async {
      final repository = RoomRepository(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      addTearDown(repository.dispose);
      await expectLater(() => repository.fetchState('s'), throwsA(matcher));
    }

    await expectStatus(401, isA<RoomRefused>());
    await expectStatus(403, isA<RoomRefused>());
    await expectStatus(404, isA<SessionGone>());
    await expectStatus(400, isA<PassageShut>());
    await expectStatus(422, isA<RoomBroke>());
    await expectStatus(500, isA<RoomBroke>());
  });

  test('a room that cannot be reached is not the same as one that answers badly',
      () async {
    final repository = RoomRepository(
      client: MockClient((_) async => throw const SocketException('sem rota')),
    );
    addTearDown(repository.dispose);

    await expectLater(
      () => repository.fetchState('s'),
      throwsA(isA<RoomUnavailable>()),
      reason: 'só transporte é queda de rede; resposta ruim é sala quebrada',
    );
  });

  test('a room that takes too long is not a room that is gone', () async {
    final repository = RoomRepository(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('{}', 200);
      }),
    );
    addTearDown(repository.dispose);

    await expectLater(
      () => repository.fetchState('s'),
      throwsA(isA<RoomSlow>()),
      reason: 'esperar demais e não achar a sala eram a mesma exceção, e a equipe ouvia '
          'que a internet tinha caído por causa de um servidor pensando',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('cancelling a coverage subscription closes the connection, not only the callback',
      () async {
    final controller = StreamController<List<int>>();
    final repository = RoomRepository(
      client: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(controller.stream, 200),
      ),
    );
    addTearDown(repository.dispose);

    final subscription = repository.watchCoverage('sessao-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.hasListener, isTrue);

    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.hasListener, isFalse,
        reason: 'a sala troca de sessão a cada passagem; uma escuta cancelada que '
            'continua lendo o socket do servidor vaza uma conexão por passagem');
  });

  test('cancelling while the connection is still opening still stops it once it does',
      () async {
    final connecting = Completer<http.StreamedResponse>();
    final controller = StreamController<List<int>>();
    final repository = RoomRepository(
      client: MockClient.streaming((request, bodyStream) => connecting.future),
    );
    addTearDown(repository.dispose);

    final subscription = repository.watchCoverage('sessao-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await subscription.cancel();
    connecting.complete(http.StreamedResponse(controller.stream, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.hasListener, isFalse,
        reason: 'cancelar antes de o GET terminar de conectar não pode deixar a '
            'escuta ser ligada mesmo assim quando a resposta finalmente chega');
  });

  test('cancelling while the connection is still opening still closes the socket, not just the app\'s own read',
      () async {
    final connecting = Completer<http.StreamedResponse>();
    var listens = 0;
    final controller = StreamController<List<int>>(onListen: () => listens++);
    final repository = RoomRepository(
      client: MockClient.streaming((request, bodyStream) => connecting.future),
    );
    addTearDown(repository.dispose);

    final subscription = repository.watchCoverage('sessao-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await subscription.cancel();
    connecting.complete(http.StreamedResponse(controller.stream, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(listens, greaterThan(0),
        reason: 'abandonar a resposta sem nunca tocá-la deixa o socket aberto do '
            'lado do servidor; fechar de verdade passa por escutar e cancelar, '
            'não por simplesmente nunca escutar');
  });

  test('a settled frame on the coverage channel names its turn and its status',
      () async {
    final controller = StreamController<List<int>>();
    final repository = RoomRepository(
      client: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(controller.stream, 200),
      ),
    );
    addTearDown(repository.dispose);

    final frames = <CoverageEvent>[];
    final done = Completer<void>();
    final subscription = repository
        .watchCoverage('sessao-1')
        .listen(frames.add, onDone: done.complete);
    addTearDown(subscription.cancel);

    controller.add(utf8.encode(
      'event: coverage\n'
      'data: {"turn_id": "turno-1", "status": "settled", '
      '"coverage": {"engaged": 3, "surfaced": 4, "total": 29, "absence_index": 13}}\n\n',
    ));
    await controller.close();
    await done.future;

    expect(frames, hasLength(1));
    expect(frames.single.turnId, 'turno-1');
    expect(frames.single.status, CoverageStatus.settled);
  });

  test('a keep-alive on the coverage channel produces nothing, and the channel keeps talking',
      () async {
    final controller = StreamController<List<int>>();
    final repository = RoomRepository(
      client: MockClient.streaming(
        (request, bodyStream) async => http.StreamedResponse(controller.stream, 200),
      ),
    );
    addTearDown(repository.dispose);

    final frames = <CoverageEvent>[];
    final done = Completer<void>();
    final subscription = repository
        .watchCoverage('sessao-1')
        .listen(frames.add, onDone: done.complete);
    addTearDown(subscription.cancel);

    controller.add(utf8.encode(': keep-alive\n\n'));
    controller.add(utf8.encode(
      'event: coverage\n'
      'data: {"turn_id": "turno-2", "status": "settled", '
      '"coverage": {"engaged": 1, "surfaced": 1, "total": 29, "absence_index": -1}}\n\n',
    ));
    await controller.close();
    await done.future;

    expect(frames, hasLength(1),
        reason:
            'um coração sem turno nem status não pode nem virar frame nem travar o '
            'parser antes do próximo evento de verdade chegar');
    expect(frames.single.turnId, 'turno-2');
  });

  test('o terminei manda o que foi ouvido de cada parte, com o nome dela',
      () async {
    late String seenBody;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seenBody = request.body;
        return http.Response(jsonEncode({'checked': true}), 200);
      }),
    );
    addTearDown(repository.dispose);

    await repository.finishBackTranslation('sessao-1', playedByTake: const [
      PlayedTake(
        takeId: 'gravacao-1',
        playedRanges: [
          [0, 10000]
        ],
        clipDurationMs: 10000,
      ),
      PlayedTake(
        takeId: 'gravacao-2',
        playedRanges: [
          [0, 8000]
        ],
        clipDurationMs: 8000,
      ),
    ]);

    expect(jsonDecode(seenBody), {
      'played_by_take': [
        {
          'take_id': 'gravacao-1',
          'played_ranges': [
            [0, 10000]
          ],
          'clip_duration_ms': 10000,
        },
        {
          'take_id': 'gravacao-2',
          'played_ranges': [
            [0, 8000]
          ],
          'clip_duration_ms': 8000,
        },
      ],
    }, reason: 'os dois números soltos não diziam de qual gravação falavam, e '
        'seguiam valendo como prova depois que a equipe regravava uma parte');
  });

  test('sem nada ouvido o terminei vai sem corpo, e a sala ainda responde',
      () async {
    late http.BaseRequest seen;
    final repository = RoomRepository(
      client: MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'checked': true}), 200);
      }),
    );
    addTearDown(repository.dispose);

    final verdict = await repository
        .finishBackTranslation('sessao-1', playedByTake: const []);

    expect(seen.contentLength, anyOf(isNull, 0),
        reason: 'relato nenhum é diferente de relato vazio, e é a sala que '
            'decide o que fazer com a falta dele');
    expect(verdict.checked, isTrue);
  });

  group('a aprovação da equipe', () {
    const aparelho = 'aparelho-de-teste';

    RoomRepository umaSala(MockClient cliente) {
      final repository = RoomRepository(
        client: cliente,
        deviceId: () async => aparelho,
      );
      addTearDown(repository.dispose);
      return repository;
    }

    test('vai pela rota da release, com o aparelho e sem corpo', () async {
      late http.BaseRequest seen;
      final repository = umaSala(MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'release_id': 'solta-1',
            'session_id': 'sessao-1',
            'version': 1,
            'package_sha256': 'abc',
            'approved_at': '2026-09-15T00:00:00Z',
          }),
          200,
        );
      }));
      repository.presents('credencial-1');

      final solta = await repository.approveRelease('sessao-1');

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/internalization-room/sessions/sessao-1/release');
      expect(seen.contentLength, anyOf(isNull, 0),
          reason: 'a sala monta a release do que já guarda: o tablet não tem '
              'nada a mandar junto');
      expect(seen.headers['X-Room-Key'], 'k');
      expect(seen.headers['X-Device-Credential'], 'credencial-1');
      expect(seen.headers['X-Room-Device'], aparelho,
          reason: 'é uma escrita da equipe, e a linha da release carrega o '
              'aparelho que a fez como toda escrita da equipe carrega');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(solta.releaseId, 'solta-1');
      expect(solta.version, 1,
          reason: 'a versão é o que a equipe ganha por aprovar');
    });

    test('uma recusa vira a exceção própria dela, e não uma sala quebrada',
        () async {
      final repository = umaSala(MockClient(
        (request) async => http.Response('a parte 2 não foi ouvida', 409),
      ));

      expect(
        () => repository.approveRelease('sessao-1'),
        throwsA(isA<ReleaseRefused>()),
        reason: 'pela escada comum um 409 é RoomBroke, que só para a sala na '
            'terceira: a equipe apertaria um botão morto duas vezes antes de '
            'alguém ser chamado',
      );
    });

    test('as outras recusas seguem as de sempre', () async {
      for (final caso in [
        (status: 404, erro: isA<SessionGone>()),
        (status: 400, erro: isA<PassageShut>()),
        (status: 403, erro: isA<RoomRefused>()),
      ]) {
        final repository = umaSala(
          MockClient((request) async => http.Response('', caso.status)),
        );

        expect(
          () => repository.approveRelease('sessao-1'),
          throwsA(caso.erro),
          reason: 'a release não inventa escada nenhuma para os estados que a '
              'sala inteira já trata',
        );
      }
    });
  });
}

Future<File> _tempRecording() async {
  final file = File(
    '${Directory.systemTemp.path}/sala-teste-${DateTime.now().microsecondsSinceEpoch}.m4a',
  );
  await file.writeAsBytes([0, 1, 2, 3]);
  addTearDown(() async {
    if (file.existsSync()) await file.delete();
  });
  return file;
}
