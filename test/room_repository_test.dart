import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

import 'a_wav_take.dart';

String _turnBody({bool usedFailSafe = false, bool degraded = false}) =>
    jsonEncode({
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

    expect(
      seen.contentLength,
      anyOf(isNull, 0),
      reason:
          'um multipart sem nenhuma parte é um corpo que o servidor não '
          'consegue ler, e a recusa chega ao app como se fosse falta de rede',
    );
    expect(seen.headers['content-type'] ?? '', isNot(contains('multipart')));
    expect(seen.headers['X-Room-Key'], 'k');
  });

  test(
    'a retried opening turn carries the first attempt\'s id, not a fresh one',
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

      expect(
        seenBodies,
        ['turn_id=turno-1', 'turn_id=turno-1'],
        reason:
            'o servidor so responde do jeito que ja respondeu se o id do '
            'reenvio bater com o da primeira tentativa — um id novo a cada '
            'chamada e a mesma falha de nunca reconhecer um retry',
      );
    },
  );

  test(
    'a turn with a recording carries the recording, not an empty envelope',
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
      await repository.sendTurn('sessao-1', file, turnId: 'turno-1');

      expect(seen.headers['content-type'], contains('multipart/form-data'));
      expect(
        seenBody,
        contains('name="file"'),
        reason:
            'o cabeçalho multipart é escrito mesmo sem nenhuma parte — só o '
            'corpo prova que a gravação foi junto',
      );
      expect(seenBody, contains('filename='));
    },
  );

  test(
    'a resent recording carries the id of its first send, so the room can answer it once',
    () async {
      final seenBodies = <String>[];
      final repository = RoomRepository(
        client: MockClient((request) async {
          seenBodies.add(request.body);
          return http.Response(_turnBody(), 200);
        }),
      );
      addTearDown(repository.dispose);

      final take = await _tempRecording();
      await repository.sendTurn('sessao-1', take, turnId: 'turno-7');
      await repository.sendTurn('sessao-1', take, turnId: 'turno-7');

      expect(seenBodies, hasLength(2));
      for (final body in seenBodies) {
        expect(
          body,
          contains('name="turn_id"\r\n\r\nturno-7\r\n'),
          reason:
              'o turno falado ia sem id, e o servidor não tinha como '
              'reconhecer o reenvio de uma resposta que ele já tinha dado',
        );
      }
    },
  );

  test(
    'a voiced turn names itself on every send, with or without marks from the last one',
    () async {
      final seenBodies = <String>[];
      final repository = RoomRepository(
        client: MockClient((request) async {
          seenBodies.add(request.body);
          return http.Response(_turnBody(), 200);
        }),
      );
      addTearDown(repository.dispose);

      await repository.sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-3',
        clientTiming: 'stop_to_answer=120',
      );
      await repository.sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-4',
      );

      expect(
        seenBodies,
        [
          contains('name="turn_id"\r\n\r\nturno-3\r\n'),
          contains('name="turn_id"\r\n\r\nturno-4\r\n'),
        ],
        reason: 'um turno falado sem id não pode ser reenviado como ele mesmo',
      );
    },
  );

  test(
    'a turn with marks from the previous one carries them, a turn with none carries no field at all',
    () async {
      late String seenBodyWithTiming;
      late String seenBodyWithout;
      final repository = RoomRepository(
        client: MockClient((request) async {
          final body = request.body;
          if (body.contains('client_timing')) {
            seenBodyWithTiming = body;
          } else {
            seenBodyWithout = body;
          }
          return http.Response(_turnBody(), 200);
        }),
      );
      addTearDown(repository.dispose);

      await repository.sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-1',
        clientTiming: 'stop_to_answer=120',
      );
      await repository.sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-2',
      );

      expect(seenBodyWithTiming, contains('name="client_timing"'));
      expect(seenBodyWithTiming, contains('stop_to_answer=120'));
      expect(
        seenBodyWithout,
        isNot(contains('client_timing')),
        reason:
            'sem marcas do turno anterior o campo não pode ir — o backend '
            'ignora o formato errado, mas um campo vazio ainda é um campo',
      );
    },
  );

  test(
    'a canned turn says whether the room was in trouble, not only that it was canned',
    () async {
      var inTrouble = true;
      final repository = RoomRepository(
        client: MockClient(
          (request) async => http.Response(
            _turnBody(usedFailSafe: true, degraded: inTrouble),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final broken = _value(
        await repository.sendTurn(
          'sessao-1',
          await _tempRecording(),
          turnId: 'turno-1',
        ),
      );
      inTrouble = false;
      final ensaiando = _value(
        await repository.sendTurn(
          'sessao-1',
          await _tempRecording(),
          turnId: 'turno-2',
        ),
      );

      expect(broken.degraded, isTrue);
      expect(ensaiando.usedFailSafe, isTrue);
      expect(
        ensaiando.degraded,
        isFalse,
        reason:
            'a sala responde da lata tanto quando falha quanto quando a equipe ensaia '
            'na língua dela, e os dois campos juntos só provam alguma coisa se a resposta '
            'trouxer a combinação que existe por causa da correção',
      );
    },
  );

  test(
    'a turn carries the id classification watches, and whether classification is still running',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'turn_id': 'turno-9',
              'classification_pending': true,
            }),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final turn = _value(await repository.openSession('sessao-1'));

      expect(turn.turnId, 'turno-9');
      expect(turn.classificationPending, isTrue);
    },
  );

  test(
    'the one look reads the reply the room stored for one turn, and anything else as nothing to play',
    () async {
      final looked = <String>[];
      var status = 200;
      final repository = RoomRepository(
        client: MockClient((request) async {
          looked.add('${request.method} ${request.url.path}');
          return status == 200
              ? http.Response(
                  jsonEncode({
                    'session_id': 'sessao-1',
                    'turn_id': 'turno-9',
                    'audio_url': '/voice/turno-9',
                    'transcript': 'a equipe falou',
                  }),
                  200,
                )
              : http.Response('', status);
        }),
      );
      addTearDown(repository.dispose);
      final container = ProviderContainer(
        overrides: [roomRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final room = container.read(roomPortProvider);
      const turn = Turn('sessao-1', 'turno-9');

      expect((await room.lookAt(turn))?.turnId, 'turno-9');
      expect(looked, [
        'GET /api/internalization-room/sessions/sessao-1/turns/turno-9',
      ]);
      for (final nothing in [202, 404, 500]) {
        status = nothing;
        expect(await room.lookAt(turn), isNull, reason: 'HTTP $nothing');
      }
    },
  );

  test('a session read says whether the room has opened it, and a server that '
      'does not say reads as not opened', () async {
    Map<String, Object?> state(String id) => {
      'session_id': id,
      'pericope': 'P01',
      'status': 'in_progress',
      'done': false,
      if (id == 'aberta') 'opened': true,
    };
    final repository = RoomRepository(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(state(request.url.pathSegments.last)),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    expect(
      await repository.fetchState('aberta'),
      isA<Answered<SessionSnapshot>>().having(
        (read) => read.value.opened,
        'opened',
        isTrue,
      ),
    );
    expect(
      await repository.fetchState('antiga'),
      isA<Answered<SessionSnapshot>>().having(
        (read) => read.value.opened,
        'opened',
        isFalse,
      ),
    );
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

    expect(
      asked,
      [
        '{"pericope":"OV","language":"pt"}',
        '{"after_session":"panorama-1","language":"pt"}',
        '{"language":"en"}',
      ],
      reason:
          'nada do que a sala fala é feito aqui — um pedido que não diz a '
          'língua volta no idioma padrão do servidor e a equipe ouve outra',
    );
    expect(
      types,
      everyElement(contains('application/json')),
      reason:
          'sem esse cabeçalho o FastAPI responde 422 e o app desenha '
          'falta de rede',
    );
  });

  test(
    'a tablet with no device of its own asks for a code without naming one',
    () async {
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

      final asked = _value(await repository.askForACode(null));

      expect(seen.url.path, '/api/internalization-room/devices/code');
      expect(
        body,
        '{}',
        reason:
            'um device_id nulo virava a string "null" no corpo e o servidor '
            'procurava um aparelho com esse id',
      );
      expect(seen.headers['X-Room-Key'], 'k');
      expect(asked.code, 'QHF-3M7K');
      expect(asked.deviceId, 'aparelho-1');
    },
  );

  test(
    'a tablet whose code ran out asks again under the device it already has',
    () async {
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

      expect(
        body,
        '{"device_id":"aparelho-1"}',
        reason:
            'sem o id, cada código novo abandonava um aparelho e a mesa via '
            'um código diferente do que tinha anotado',
      );
    },
  );

  test(
    'an unreadable expiry is a code with no expiry, not a code born dead',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'device_id': 'aparelho-1',
              'code': 'QHF-3M7K',
              'expires_at': 'sometime after lunch',
            }),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final asked = _value(await repository.askForACode(null));

      expect(
        asked.expiresAt,
        isNull,
        reason:
            'um vencimento no passado como padrão pedia um código novo a cada '
            'volta do relógio, e a mesa nunca via o mesmo duas vezes',
      );
    },
  );

  test(
    'a device nobody has claimed answers nothing, and nothing is not a failure',
    () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
      );
      addTearDown(repository.dispose);

      final link = _value(await repository.readTheLink('aparelho-1'));

      expect(
        seen.url.path,
        '/api/internalization-room/devices/aparelho-1/link',
      );
      expect(
        link,
        isNull,
        reason:
            'um 204 caía no ramo de não-200 e virava RoomBroke, então esperar '
            'pela mesa parecia a sala quebrada',
      );
    },
  );

  test('a claimed device comes back naming the team it belongs to', () async {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'project_id': 'equipe-terena', 'label': 'prateleira'}),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    final link = _value(await repository.readTheLink('aparelho-1'));

    expect(link?.projectId, 'equipe-terena');
  });

  test(
    'a link with no team named is a room failure, not a team called nothing',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response('{"label":"prateleira"}', 200),
        ),
      );
      addTearDown(repository.dispose);

      expect(
        await repository.readTheLink('aparelho-1'),
        isA<Refused>(),
        reason:
            'um project_id ausente virava equipe "" — o aparelho gravava isso em disco, '
            'dava-se por vinculado, e a tela de instalação nunca mais voltava',
      );
    },
  );

  test(
    'a code with no code in it is a room failure, not an empty screen',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async =>
              http.Response('{"expires_at":"2026-08-26T23:15:00Z"}', 200),
        ),
      );
      addTearDown(repository.dispose);

      expect(
        await repository.askForACode(null),
        isA<Refused>(),
        reason: 'a mesa não pode digitar um código que a tela não mostrou',
      );
    },
  );

  test('a malformed answer is a room failure, never a crash', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response('{"nada":1}', 200)),
    );
    addTearDown(repository.dispose);

    expect(
      await repository.createSession(language: 'pt'),
      isA<Refused>(),
      reason:
          'um TypeError escapa de todo `on Exception` e trava a sala em '
          'pensando, sem gesto e sem voz',
    );
  });

  test('each refusal keeps its own meaning', () async {
    Future<void> expectStatus(int status, Matcher matcher) async {
      final repository = RoomRepository(
        client: MockClient((_) async => http.Response('{}', status)),
      );
      addTearDown(repository.dispose);
      expect(await repository.fetchState('s'), matcher);
    }

    await expectStatus(401, _refusedWith(RefusalCode.unauthorized));
    await expectStatus(403, _refusedWith(RefusalCode.forbidden));
    await expectStatus(404, isA<SessionGone>());
    await expectStatus(400, isA<Refused>());
    await expectStatus(422, isA<Refused>());
    await expectStatus(500, isA<NetworkFailed>());
  });

  test(
    'a room that cannot be reached is not the same as one that answers badly',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => throw const SocketException('sem rota'),
        ),
      );
      addTearDown(repository.dispose);

      expect(
        await repository.fetchState('s'),
        isA<NetworkFailed>(),
        reason: 'só transporte é queda de rede; resposta ruim é sala quebrada',
      );
    },
  );

  test(
    'a room that takes too long is not a room that is gone',
    () async {
      final repository = RoomRepository(
        client: MockClient((_) => Completer<http.Response>().future),
        stateTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(repository.dispose);

      expect(
        await repository.fetchState('s'),
        isA<NetworkFailed>(),
        reason:
            'esperar demais e não achar a sala eram a mesma exceção, e a equipe ouvia '
            'que a internet tinha caído por causa de um servidor pensando',
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'cancelling a coverage subscription closes the connection, not only the callback',
    () async {
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(controller.stream, 200),
        ),
      );
      addTearDown(repository.dispose);

      final subscription = repository.watchCoverage('sessao-1').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.hasListener, isTrue);

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        controller.hasListener,
        isFalse,
        reason:
            'a sala troca de sessão a cada passagem; uma escuta cancelada que '
            'continua lendo o socket do servidor vaza uma conexão por passagem',
      );
    },
  );

  test(
    'cancelling while the connection is still opening still stops it once it does',
    () async {
      final connecting = Completer<http.StreamedResponse>();
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) => connecting.future,
        ),
      );
      addTearDown(repository.dispose);

      final subscription = repository.watchCoverage('sessao-1').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await subscription.cancel();
      connecting.complete(http.StreamedResponse(controller.stream, 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        controller.hasListener,
        isFalse,
        reason:
            'cancelar antes de o GET terminar de conectar não pode deixar a '
            'escuta ser ligada mesmo assim quando a resposta finalmente chega',
      );
    },
  );

  test(
    'cancelling while the connection is still opening still closes the socket, not just the app\'s own read',
    () async {
      final connecting = Completer<http.StreamedResponse>();
      var listens = 0;
      final controller = StreamController<List<int>>(onListen: () => listens++);
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) => connecting.future,
        ),
      );
      addTearDown(repository.dispose);

      final subscription = repository.watchCoverage('sessao-1').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await subscription.cancel();
      connecting.complete(http.StreamedResponse(controller.stream, 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        listens,
        greaterThan(0),
        reason:
            'abandonar a resposta sem nunca tocá-la deixa o socket aberto do '
            'lado do servidor; fechar de verdade passa por escutar e cancelar, '
            'não por simplesmente nunca escutar',
      );
    },
  );

  test(
    'a settled frame on the coverage channel names its turn and its status',
    () async {
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(controller.stream, 200),
        ),
      );
      addTearDown(repository.dispose);

      final frames = <CoverageEvent>[];
      final done = Completer<void>();
      final subscription = repository
          .watchCoverage('sessao-1')
          .listen(frames.add, onDone: done.complete);
      addTearDown(subscription.cancel);

      controller.add(
        utf8.encode(
          'event: coverage\n'
          'data: {"turn_id": "turno-1", "status": "settled", '
          '"coverage": {"engaged": 3, "surfaced": 4, "total": 29, "absence_index": 13}}\n\n',
        ),
      );
      await controller.close();
      await done.future;

      expect(frames, hasLength(1));
      expect(frames.single.turnId, 'turno-1');
      expect(frames.single.status, CoverageStatus.settled);
    },
  );

  test(
    'a settled frame carries the same beads the state endpoint would answer with',
    () async {
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(controller.stream, 200),
        ),
      );
      addTearDown(repository.dispose);

      final frames = <CoverageEvent>[];
      final done = Completer<void>();
      final subscription = repository
          .watchCoverage('sessao-1')
          .listen(frames.add, onDone: done.complete);
      addTearDown(subscription.cancel);

      controller.add(
        utf8.encode(
          'event: coverage\n'
          'data: {"turn_id": "turno-1", "status": "settled", '
          '"coverage": {"engaged": 3, "surfaced": 4, "total": 29, "absence_index": 13}}\n\n',
        ),
      );
      await controller.close();
      await done.future;

      final coverage = frames.single.coverage;
      expect(
        coverage,
        isNotNull,
        reason:
            'o aviso já carrega as contas — esperar o fetchState pedia de '
            'novo o que o próprio evento acabou de responder',
      );
      expect(coverage!.engaged, 3);
      expect(coverage.surfaced, 4);
      expect(coverage.total, 29);
    },
  );

  test(
    'a keep-alive on the coverage channel produces nothing, and the channel keeps talking',
    () async {
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(controller.stream, 200),
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
      controller.add(
        utf8.encode(
          'event: coverage\n'
          'data: {"turn_id": "turno-2", "status": "settled", '
          '"coverage": {"engaged": 1, "surfaced": 1, "total": 29, "absence_index": -1}}\n\n',
        ),
      );
      await controller.close();
      await done.future;

      expect(
        frames,
        hasLength(1),
        reason:
            'um coração sem turno nem status não pode nem virar frame nem travar o '
            'parser antes do próximo evento de verdade chegar',
      );
      expect(frames.single.turnId, 'turno-2');
    },
  );

  test('each refusal on the coverage channel keeps its own meaning', () async {
    Future<void> expectStatus(int status, Matcher matcher) async {
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(const Stream<List<int>>.empty(), status),
        ),
      );
      addTearDown(repository.dispose);

      final frames = <CoverageEvent>[];
      Object? error;
      final done = Completer<void>();
      final subscription = repository
          .watchCoverage('sessao-1')
          .listen(
            frames.add,
            onError: (Object e) => error = e,
            onDone: done.complete,
          );
      addTearDown(subscription.cancel);

      await done.future;
      expect(frames, isEmpty);
      expect(
        error,
        matcher,
        reason:
            'um corpo de erro sem eventos de coverage lia como um stream '
            'vazio comum, e o canal fechava quieto em vez de dizer o que '
            'a sala respondeu',
      );
    }

    await expectStatus(401, _refusedWith(RefusalCode.unauthorized));
    await expectStatus(403, _refusedWith(RefusalCode.forbidden));
    await expectStatus(404, isA<SessionGone>());
    await expectStatus(500, isA<NetworkFailed>());
  });

  test(
    'a coverage channel that never manages to connect says so, instead of reading the drop as an empty stream',
    () async {
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              throw const SocketException('sem rota'),
        ),
      );
      addTearDown(repository.dispose);

      final frames = <CoverageEvent>[];
      Object? error;
      final done = Completer<void>();
      final subscription = repository
          .watchCoverage('sessao-1')
          .listen(
            frames.add,
            onError: (Object e) => error = e,
            onDone: done.complete,
          );
      addTearDown(subscription.cancel);

      await done.future;
      expect(frames, isEmpty);
      expect(
        error,
        isA<NetworkFailed>(),
        reason:
            'uma sala inalcançável fechava o canal quieto, e o lado que '
            'escuta não tinha como distinguir isso de um fim comum e parar '
            'de reabrir a cada queda',
      );
    },
  );

  test(
    'a coverage channel whose body drops mid-stream says so, instead of reading the drop as an empty stream',
    () async {
      final controller = StreamController<List<int>>();
      final repository = RoomRepository(
        client: MockClient.streaming(
          (request, bodyStream) async =>
              http.StreamedResponse(controller.stream, 200),
        ),
      );
      addTearDown(repository.dispose);

      final frames = <CoverageEvent>[];
      Object? error;
      final done = Completer<void>();
      final subscription = repository
          .watchCoverage('sessao-1')
          .listen(
            frames.add,
            onError: (Object e) => error = e,
            onDone: done.complete,
          );
      addTearDown(subscription.cancel);

      controller.addError(const SocketException('conexão caiu'));

      await done.future;
      expect(frames, isEmpty);
      expect(
        error,
        isA<NetworkFailed>(),
        reason:
            'o corpo caindo no meio da leitura fechava o canal quieto, do '
            'mesmo jeito que uma sala nunca alcançada',
      );
    },
  );

  test(
    'a conferência manda o que foi ouvido de cada parte, com o nome dela',
    () async {
      late String seenBody;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seenBody = request.body;
          return http.Response(jsonEncode({'checked': true}), 200);
        }),
      );
      addTearDown(repository.dispose);

      await repository.finishBackTranslation(
        'sessao-1',
        playedByTake: const [
          PlayedTake(
            takeId: 'gravacao-1',
            playedRanges: [
              [0, 10000],
            ],
            clipDurationMs: 10000,
          ),
          PlayedTake(
            takeId: 'gravacao-2',
            playedRanges: [
              [0, 8000],
            ],
            clipDurationMs: 8000,
          ),
        ],
      );

      expect(
        jsonDecode(seenBody),
        {
          'played_by_take': [
            {
              'take_id': 'gravacao-1',
              'played_ranges': [
                [0, 10000],
              ],
              'clip_duration_ms': 10000,
            },
            {
              'take_id': 'gravacao-2',
              'played_ranges': [
                [0, 8000],
              ],
              'clip_duration_ms': 8000,
            },
          ],
        },
        reason:
            'os dois números soltos não diziam de qual gravação falavam, e '
            'seguiam valendo como prova depois que a equipe regravava uma parte',
      );
    },
  );

  test(
    'sem nada ouvido a conferência vai sem corpo, e a sala ainda responde',
    () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'checked': true}), 200);
        }),
      );
      addTearDown(repository.dispose);

      final verdict = _value(
        await repository.finishBackTranslation(
          'sessao-1',
          playedByTake: const [],
        ),
      );

      expect(
        seen.contentLength,
        anyOf(isNull, 0),
        reason:
            'relato nenhum é diferente de relato vazio, e é a sala que '
            'decide o que fazer com a falta dele',
      );
      expect(verdict.checked, isTrue);
    },
  );

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
      final repository = umaSala(
        MockClient((request) async {
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
        }),
      );
      repository.presents('credencial-1');

      final solta = _value(await repository.approveRelease('sessao-1'));

      expect(seen.method, 'POST');
      expect(
        seen.url.path,
        '/api/internalization-room/sessions/sessao-1/release',
      );
      expect(
        seen.contentLength,
        anyOf(isNull, 0),
        reason:
            'a sala monta a release do que já guarda: o tablet não tem '
            'nada a mandar junto',
      );
      expect(seen.headers['X-Room-Key'], 'k');
      expect(seen.headers['X-Device-Credential'], 'credencial-1');
      expect(
        seen.headers['X-Room-Device'],
        aparelho,
        reason:
            'é uma escrita da equipe, e a linha da release carrega o '
            'aparelho que a fez como toda escrita da equipe carrega',
      );
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(solta.releaseId, 'solta-1');
      expect(
        solta.version,
        1,
        reason: 'a versão é o que a equipe ganha por aprovar',
      );
      expect(
        solta.blockers,
        isEmpty,
        reason:
            'e nada ficou de pé: é o que separa esta resposta de uma '
            'recusa, que vem no mesmo estado e no mesmo corpo',
      );
    });

    test('uma recusa vem no corpo, com os buracos que ela nomeia', () async {
      final repository = umaSala(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'version': null,
              'release_id': null,
              'package_sha256': null,
              'approved_at': null,
              'blockers': ['telling_back_not_checked', 'untold_part'],
              'untold_take_ids': ['gravacao-2'],
              'unheard_take_ids': [],
              'untold_segment_id': null,
            }),
            200,
          );
        }),
      );

      final resposta = _value(await repository.approveRelease('sessao-1'));

      expect(
        resposta.minted,
        isFalse,
        reason:
            'sem versão não há release nenhuma, e o colar não tem o que '
            'fechar',
      );
      expect(
        resposta.blockers,
        ['telling_back_not_checked', 'untold_part'],
        reason:
            'os buracos chegam nomeados, na ordem em que o portão os '
            'levantou: é a única coisa que diz à equipe para onde ir',
      );
      expect(
        resposta.untoldTakeIds,
        ['gravacao-2'],
        reason:
            'e o buraco que tem chão traz o chão: sem a gravação, a '
            'parte não contada é um código que não leva a lugar nenhum',
      );
    });

    test('um 200 sem versão e sem buracos não passa por aprovado', () async {
      final repository = umaSala(
        MockClient(
          (request) async =>
              http.Response(jsonEncode({'session_id': 'sessao-1'}), 200),
        ),
      );

      final resposta = _value(await repository.approveRelease('sessao-1'));

      expect(
        resposta.minted,
        isFalse,
        reason:
            'lida como zero, a versão que o servidor não nomeou fechava '
            'a passagem por cima de nada; é a resposta que este modelo '
            'existe para apanhar',
      );
      expect(
        resposta.blockers,
        isEmpty,
        reason:
            'e não é uma recusa tampouco: é uma resposta que este tablet '
            'não conhece, e quem decide o que fazer com ela é a sala',
      );
    });

    test(
      'a corrida de versão desce pela escada comum, como um pedido a repetir',
      () async {
        final repository = umaSala(
          MockClient(
            (request) async =>
                http.Response('a release mudou debaixo do pedido', 409),
          ),
        );

        expect(
          await repository.approveRelease('sessao-1'),
          isA<Refused>(),
          reason:
              'um 409 deixou de ser a recusa e é só a versão que correu: a '
              'escada comum o repete, e a recusa de verdade chega em 200 com os '
              'buracos nomeados — tratá-lo como recusa levava a equipe a um '
              'buraco que ninguém nomeou',
        );
      },
    );

    test('as outras recusas seguem as de sempre', () async {
      for (final caso in [
        (status: 404, erro: isA<SessionGone>()),
        (status: 400, erro: isA<Refused>()),
        (status: 403, erro: isA<Refused>()),
      ]) {
        final repository = umaSala(
          MockClient((request) async => http.Response('', caso.status)),
        );

        expect(
          await repository.approveRelease('sessao-1'),
          caso.erro,
          reason:
              'a release não inventa escada nenhuma para os estados que a '
              'sala inteira já trata',
        );
      }
    });
  });

  group(
    'a status code is a verdict on the passage only at the doors that ask for the session',
    () {
      RoomRepository answering(int status) {
        final repository = RoomRepository(
          client: MockClient((_) async => http.Response('{}', status)),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);
        return repository;
      }

      final sessionDoors = <String, Future<Object?> Function(RoomRepository)>{
        'fetchState': (room) => room.fetchState('sessao-1'),
        'openSession': (room) => room.openSession('sessao-1'),
        'sendTurn': (room) async => room.sendTurn(
          'sessao-1',
          await _tempRecording(),
          turnId: 'turno-1',
        ),
        'takesOf': (room) => room.takesOf('sessao-1'),
        'askForAPerson': (room) => room.askForAPerson('sessao-1'),
        'personArrived': (room) => room.personArrived('sessao-1'),
        'approveRelease': (room) => room.approveRelease('sessao-1'),
        'finishBackTranslation': (room) =>
            room.finishBackTranslation('sessao-1', playedByTake: const []),
        'sendTake': (room) async => room.sendTake(
          'sessao-1',
          await _tempRecording(),
          kind: 'ensaio',
          scope: 'parte-1',
        ),
        'sendChunk': (room) async => room.sendChunk(
          'sessao-1',
          await _tempRecording(),
          takeId: 'gravacao-1',
          from: const Duration(seconds: 4),
          to: const Duration(seconds: 7),
          idempotencyKey: 'chave-1',
        ),
      };

      final stretchCalls = <String, Future<Object?> Function(RoomRepository)>{
        'replaceSegment': (room) async => room.replaceSegment(
          'sessao-1',
          'trecho-1',
          await _tempRecording(),
          takeId: 'gravacao-1',
          from: Duration.zero,
          to: const Duration(seconds: 4),
          idempotencyKey: 'chave-1',
        ),
      };

      final notAboutASession =
          <String, Future<Object?> Function(RoomRepository)>{
            'passagesOf': (room) => room.passagesOf('Ruth', language: 'pt'),
            'collectTheCredential': (room) =>
                room.collectTheCredential('aparelho-1'),
            'askForACode': (room) => room.askForACode('aparelho-1'),
            'readTheLink': (room) => room.readTheLink('aparelho-1'),
            'askForAPersonWithoutASession': (room) =>
                room.askForAPersonWithoutASession('aparelho-1'),
          };

      test(
        'a door that asks for the session reads a 404 as the session gone',
        () async {
          for (final door in sessionDoors.entries) {
            expect(
              await door.value(answering(404)),
              isA<SessionGone>(),
              reason:
                  '${door.key} pergunta pela sessão; o 404 dele é ela sumida',
            );
          }
        },
      );

      test(
        'a call that names a take or a stretch reads a 404 as a refused call',
        () async {
          for (final call in stretchCalls.entries) {
            expect(
              await call.value(answering(404)),
              isA<Refused>(),
              reason:
                  '${call.key}: o 404 é a gravação ou o trecho que não são desta '
                  'sessão, e lido como sessão sumida esquecia a linha de uma '
                  'sessão viva',
            );
          }
        },
      );

      test(
        'ENG-1133: sendChunk reads a take of another session as a refused call, not the session gone',
        () async {
          // The 404 case is already covered above: sendChunk sits in sessionDoors, so
          // "a door that asks for the session reads a 404 as the session gone" already
          // proves it. This is the half that loop cannot: the wire shape UNKNOWN_REFERENCE
          // actually answers with.
          final repository = RoomRepository(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'detail':
                      'Internalization room rehearsal take gravacao-1 not found',
                  'code': 'UNKNOWN_REFERENCE',
                }),
                422,
              ),
            ),
            deviceId: () async => 'aparelho-1',
          );
          addTearDown(repository.dispose);

          expect(
            await sessionDoors['sendChunk']!(repository),
            isA<Refused>(),
            reason:
                'a gravação nomeada é de outra sessão, e não a sessão — o app '
                'risca em vez de deixar a passagem',
          );
        },
      );

      test(
        'a 400 on opening a session is the passage that cannot open',
        () async {
          expect(
            await answering(400).createSession(pericope: 'P01', language: 'pt'),
            _refusedWith(RefusalCode.passageCannotOpen),
            reason:
                'o /sessions responde 400 para uma passagem que não abre, e lido '
                'como chamada recusada chamava uma pessoa na hora',
          );
        },
      );

      test(
        'a 400 is a refused call on every other call, never a verdict on the passage',
        () async {
          for (final call in {
            ...sessionDoors,
            ...stretchCalls,
            ...notAboutASession,
          }.entries) {
            expect(
              await call.value(answering(400)),
              isA<Refused>(),
              reason:
                  '${call.key}: fora da criação da sessão, o 400 não fala da '
                  'passagem; um trecho vazio recusado levava a sessão junto',
            );
          }
        },
      );

      RoomRepository refusingWith(int status, String detail) {
        final repository = RoomRepository(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'detail': detail, 'code': 'BAD_REQUEST'}),
              status,
            ),
          ),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);
        return repository;
      }

      const superseded =
          'This stretch no longer counts: it was already replaced, or the part '
          'of the rehearsal it is a slice of was recorded again';
      const divided =
          'A stretch that was divided is no longer a unit: replace one of the '
          'stretches it was divided into, not the stretch itself';

      test(
        'the words of a refusal never name it: the stretch-no-longer-counts prose under another code is that code',
        () async {
          expect(
            await stretchCalls['replaceSegment']!(
              refusingWith(400, superseded),
            ),
            _refusedWith('BAD_REQUEST'),
          );
        },
      );

      test('every other refusal of a replace stays a refused call', () async {
        expect(
          await stretchCalls['replaceSegment']!(refusingWith(400, divided)),
          _refusedWith('BAD_REQUEST'),
          reason: 'o trecho dividido não foi contado; é recusa de verdade',
        );
        expect(
          await stretchCalls['replaceSegment']!(refusingWith(422, superseded)),
          _refusedWith('BAD_REQUEST'),
          reason: 'a recusa nomeada é o 400 do servidor, e nada mais largo',
        );
      });

      test('sendChunk keeps a 400 or a 422 as a refused call', () async {
        for (final status in [400, 422]) {
          expect(
            await sessionDoors['sendChunk']!(refusingWith(status, superseded)),
            _refusedWith('BAD_REQUEST'),
            reason: 'sendChunk $status: só o replace conta de novo um trecho',
          );
        }
      });

      test(
        'invariant 5: a 404 on a door that names no session is refused as NOT_FOUND',
        () async {
          final sessionless = <String, Future<RoomAnswer<Object?>> Function()>{
            'passagesOf': () =>
                answering(404).passagesOf('Ruth', language: 'pt'),
            'collectTheCredential': () =>
                answering(404).collectTheCredential('aparelho-1'),
            'askForACode': () => answering(404).askForACode('aparelho-1'),
            'readTheLink': () => answering(404).readTheLink('aparelho-1'),
            'createSession': () => answering(404).createSession(language: 'pt'),
          };
          for (final door in sessionless.entries) {
            expect(
              await door.value(),
              _refusedWith(RefusalCode.notFound),
              reason: '${door.key} não nomeia sessão; o 404 dele é uma recusa',
            );
          }
        },
      );

      test('a session creation that names the session before it reads a 404 as '
          'that session gone', () async {
        expect(
          await answering(404).createSession(language: 'pt', afterSession: 's'),
          isA<SessionGone>(),
        );
      });

      test('the device routes keep their own answers', () async {
        expect(
          await answering(409).collectTheCredential('aparelho-1'),
          _refusedWith(RefusalCode.credentialNotYet),
        );
        expect(
          await answering(403).collectTheCredential('aparelho-1'),
          _refusedWith(RefusalCode.credentialTaken),
        );
        expect(_value(await answering(204).readTheLink('aparelho-1')), isNull);
        expect(
          await answering(404).askForAPersonWithoutASession('aparelho-1'),
          _refusedWith(RefusalCode.nobodyToReach),
        );
        expect(
          await answering(409).askForAPersonWithoutASession('aparelho-1'),
          _refusedWith(RefusalCode.nobodyToReach),
        );
      });
    },
  );

  test(
    'a turn gives up at 305 s, the server bound plus a 5 s margin, below the busy watchdog',
    () {
      const serverBound = Duration(seconds: 300);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final watchdog = container.read(busyStateCeilingProvider);

      expect(
        RoomRepository.turnTimeout,
        greaterThan(serverBound),
        reason:
            'a rota aceita até 300 s (ENG-817); um cliente que desiste em 90 s '
            'derrubava um turno que o servidor ainda ia responder',
      );
      expect(watchdog, isNotNull);
      expect(
        watchdog,
        greaterThan(RoomRepository.turnTimeout),
        reason:
            'o watchdog precisa sobrar depois que a chamada HTTP já teria '
            'voltado, senão os dois relógios brigam pelo mesmo turno travado',
      );
      expect(
        RoomRepository.turnTimeout,
        const Duration(seconds: 305),
        reason:
            'a escada da Márcia: 300 s no servidor, 305 s no cliente, 330 s no watchdog',
      );
      expect(
        watchdog,
        const Duration(seconds: 330),
        reason:
            'a escada da Márcia: 300 s no servidor, 305 s no cliente, 330 s no watchdog',
      );
    },
  );

  test(
    'a turn the room holds past 305 seconds is given up by the client at 305 seconds',
    () async {
      final take = await _tempRecording();
      for (final send
          in <Future<RoomAnswer<TurnResult>> Function(RoomRepository)>[
            (room) => room.sendTurn('sessao-1', take, turnId: 'turno-1'),
            (room) => room.openSession('sessao-1', turnId: 'turno-1'),
          ]) {
        var heard = false;
        final repository = RoomRepository(
          client: MockClient((_) {
            heard = true;
            return Completer<http.Response>().future;
          }),
        );
        addTearDown(repository.dispose);
        final clock = FakeAsync();
        RoomAnswer<TurnResult>? answer;
        clock.run(
          (_) => unawaited(send(repository).then((given) => answer = given)),
        );
        while (!heard) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          clock.flushMicrotasks();
        }

        clock.elapse(const Duration(seconds: 304));
        expect(answer, isNull);
        clock.elapse(const Duration(seconds: 2));
        expect(answer, isA<NetworkFailed>());
      }
    },
  );

  group('the audio part of each door', () {
    late http.Request sent;
    RoomRepository listening() {
      final repository = RoomRepository(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);
      return repository;
    }

    test(
      'a rehearsal take recorded as WAV goes up as audio/wav under a .wav name',
      () async {
        final wav = aWavTake();
        final file = await _tempRecording(extension: 'wav', bytes: wav);

        await listening().sendTake(
          'sessao-1',
          file,
          kind: 'ensaio',
          scope: 'parte-1',
        );

        final part = _filePart(sent);
        expect(
          part.head,
          contains('content-type: audio/wav'),
          reason:
              'a sala guarda o tipo que o envio declara, e o Refine lê o '
              'formato da parte por ele',
        );
        expect(part.head, matches(RegExp(r'filename="[^"]+\.wav"')));
        expect(part.content, wav);
      },
    );

    test('a stretch told goes up as it always did', () async {
      await listening().sendChunk(
        'sessao-1',
        await _tempRecording(),
        takeId: 'gravacao-1',
        from: const Duration(seconds: 4),
        to: const Duration(seconds: 7),
        idempotencyKey: 'chave-1',
      );

      expect(
        _filePart(sent).head,
        contains('content-type: application/octet-stream'),
      );
    });

    test('a stretch told again goes up as it always did', () async {
      await listening().replaceSegment(
        'sessao-1',
        'trecho-1',
        await _tempRecording(),
        takeId: 'gravacao-1',
        from: Duration.zero,
        to: const Duration(seconds: 4),
        idempotencyKey: 'chave-1',
      );

      expect(
        _filePart(sent).head,
        contains('content-type: application/octet-stream'),
      );
    });

    test(
      'an older .m4a take still waiting in the Outbox goes up as it always did',
      () async {
        await listening().sendTake(
          'sessao-1',
          await _tempRecording(),
          kind: 'ensaio',
          scope: 'parte-1',
        );

        expect(
          _filePart(sent).head,
          contains('content-type: application/octet-stream'),
          reason:
              'uma parte gravada antes da mudança continua AAC, e declará-la '
              'WAV faria o Refine abrir um arquivo que não é',
        );
      },
    );

    test('a conversation turn goes up as it always did', () async {
      await listening().sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-1',
      );

      expect(
        _filePart(sent).head,
        contains('content-type: application/octet-stream'),
      );
    });
  });
}

Future<File> _tempRecording({
  String extension = 'm4a',
  List<int> bytes = const [0, 1, 2, 3],
}) async {
  final file = File(
    '${Directory.systemTemp.path}/sala-teste-${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(bytes);
  addTearDown(() async {
    if (file.existsSync()) await file.delete();
  });
  return file;
}

({String head, List<int> content}) _filePart(http.Request request) {
  final boundary = request.headers['content-type']!.split('boundary=').last;
  final body = latin1.decode(request.bodyBytes);
  final part = body
      .split('--$boundary')
      .firstWhere((part) => part.contains('name="file"'));
  final headEnd = part.indexOf('\r\n\r\n');
  return (
    head: part.substring(0, headEnd),
    content: latin1.encode(
      part.substring(headEnd + 4, part.length - '\r\n'.length),
    ),
  );
}

T _value<T>(RoomAnswer<T> answer) => (answer as Answered<T>).value;

Matcher _refusedWith(String code) =>
    isA<Refused>().having((refusal) => refusal.code, 'code', code);
