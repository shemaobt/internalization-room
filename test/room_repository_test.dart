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
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/escuta_das_partes.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
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
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test(
    'a fixed line is asked of the room by its name and language, and comes back as an address',
    () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            '{"audio_url": "/api/internalization-room/voice/abc"}',
            200,
          );
        }),
      );
      addTearDown(repository.dispose);

      final address = await repository.fixedLineAddress('D1', language: 'pt');

      expect(
        address,
        isA<Answered<String>>().having(
          (answer) => answer.value,
          'value',
          '/api/internalization-room/voice/abc',
        ),
        reason:
            'a linha vinha gravada no app e tocava a letra velha depois de ela mudar',
      );
      expect(seen.url.path, '/api/internalization-room/fixed-lines/D1');
      expect(seen.url.queryParameters, {'language': 'pt'});
    },
  );

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
    'a canned turn still says, turn by turn, whether the room was in trouble',
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
      expect(
        ensaiando.degraded,
        isFalse,
        reason:
            'a sala responde da lata tanto quando falha quanto quando a equipe ensaia '
            'na língua dela, e só o degraded de cada turno diz qual dos dois aconteceu',
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
    'a look reads 200 as landed, 202 as still answering, 404 as nothing landed and any other failure as a failed look',
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

      expect(
        await room.lookAt(turn),
        isA<TheReplyLanded>().having(
          (landed) => landed.reply.turnId,
          'turn id',
          'turno-9',
        ),
      );
      expect(looked, [
        'GET /api/internalization-room/sessions/sessao-1/turns/turno-9',
      ]);
      status = 202;
      expect(await room.lookAt(turn), isA<StillAnswering>());
      status = 404;
      expect(await room.lookAt(turn), isA<NothingLanded>());
      status = 500;
      expect(await room.lookAt(turn), isA<TheLookFailed>());
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

  test(
    'a session read asks the room for the stretches a part recorded again left stale',
    () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'pericope': 'P01',
              'status': 'in_progress',
              'done': false,
            }),
            200,
          );
        }),
      );
      addTearDown(repository.dispose);

      await repository.fetchState('sessao-1');

      expect(seen.url.path, '/api/internalization-room/sessions/sessao-1');
      expect(
        seen.url.queryParameters,
        {'include_stale': 'true'},
        reason:
            'sem pedir, a sala nunca servia os trechos de uma parte gravada de '
            'novo, e a lista os perdia',
      );
    },
  );

  test(
    'a stale stretch in the session read is handed over apart, never as a stretch that counts',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'pericope': 'P01',
              'status': 'in_progress',
              'done': false,
              'back_translation': {
                'segments': [
                  {
                    'segment_id': 'trecho-1',
                    'take_id': 'gravacao-1',
                    'starts_ms': 0,
                    'ends_ms': 4000,
                    'frase': 1,
                    'stale': false,
                  },
                  {
                    'segment_id': 'trecho-2',
                    'take_id': 'gravacao-2',
                    'starts_ms': 0,
                    'ends_ms': 3000,
                    'frase': null,
                    'stale': true,
                  },
                ],
              },
            }),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final told = _value(
        await repository.fetchState('sessao-1'),
      ).backTranslation;

      expect(
        [for (final segment in told.segments) segment.segmentId],
        ['trecho-1'],
        reason:
            'um trecho regravado contava como trecho traduzido: entrava na '
            'conferência e movia o cursor',
      );
      expect(
        [for (final segment in told.stale) segment.segmentId],
        ['trecho-2'],
      );
    },
  );

  test('the session read carries the approved draft, and none when the room '
      'says none', () async {
    Map<String, Object?> state(String id) => {
      'session_id': id,
      'pericope': 'P01',
      'status': 'in_progress',
      'done': false,
      if (id == 'aprovada')
        'approved': {
          'version': 2,
          'release_id': 'internalize-x-p01-v2',
          'approved_at': '2026-10-19T14:03:00+00:00',
          'forced': true,
        },
      if (id == 'so-a-versao') 'approved': {'version': 3},
      if (id == 'nula') 'approved': null,
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

    int? version(RoomAnswer<SessionSnapshot> read) =>
        (read as Answered<SessionSnapshot>).value.approved?.version;
    expect(version(await repository.fetchState('aprovada')), 2);
    expect(version(await repository.fetchState('so-a-versao')), 3);
    bool? forced(RoomAnswer<SessionSnapshot> read) =>
        (read as Answered<SessionSnapshot>).value.approved?.forced;
    expect(
      forced(await repository.fetchState('aprovada')),
      isTrue,
      reason: 'a sala dizia que a versão foi forçada e o tablet não lia',
    );
    expect(forced(await repository.fetchState('so-a-versao')), isFalse);
    for (final none in ['nula', 'ausente']) {
      expect(
        await repository.fetchState(none),
        isA<Answered<SessionSnapshot>>().having(
          (read) => read.value.approved,
          'approved',
          isNull,
        ),
      );
    }
  });

  test(
    'the room\'s books are read from GET /books and answered in its order',
    () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response('{"books": ["Ruth", "Esther", "Jonah"]}', 200);
        }),
      );
      addTearDown(repository.dispose);
      final refusing = RoomRepository(
        client: MockClient((_) async => http.Response('{}', 404)),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(refusing.dispose);

      final answer = await repository.servedBooks();

      expect(seen.method, 'GET');
      expect(
        seen.url.toString(),
        'http://sala.local/api/internalization-room/books',
      );
      expect(
        answer,
        isA<Answered<List<String>>>().having((read) => read.value, 'books', [
          'Ruth',
          'Esther',
          'Jonah',
        ]),
      );
      expect(
        await refusing.servedBooks(),
        _refusedWith(RefusalCode.notFound),
        reason: 'like the passages door, the books door names no session',
      );
    },
  );

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

    await repository.createSession(pericope: 'OV-Jonah', language: 'pt');
    await repository.createSession(afterSession: 'panorama-1', language: 'pt');
    await repository.createSession(language: 'en');

    expect(
      asked,
      [
        '{"pericope":"OV-Jonah","language":"pt"}',
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

  test(
    'a stretch told back comes back with the name the room gave it',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async =>
              http.Response('{"frase":3,"segment_id":"trecho-9"}', 200),
        ),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.sendChunk(
        'sessao-1',
        await _tempRecording(),
        takeId: 'gravacao-1',
        from: Duration.zero,
        to: const Duration(seconds: 3),
        idempotencyKey: 'chave-1',
      );

      expect(
        answer,
        isA<Answered<BackTranslationChunk>>().having(
          (answered) => answered.value.segmentId,
          'segmentId',
          'trecho-9',
        ),
        reason:
            'a resposta do trecho trazia o nome e o tablet o jogava fora, e a '
            'frase contada nesta sessão não podia ser traduzida de novo',
      );
    },
  );

  test('a stretch answer kept from before the room named it still lands, '
      'with no name, not as a broken room', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response('{"frase":3}', 200)),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(repository.dispose);

    final answer = await repository.sendChunk(
      'sessao-1',
      await _tempRecording(),
      takeId: 'gravacao-1',
      from: Duration.zero,
      to: const Duration(seconds: 3),
      idempotencyKey: 'chave-1',
    );

    expect(
      answer,
      isA<Answered<BackTranslationChunk>>()
          .having((answered) => answered.value.frase, 'frase', 3)
          .having((answered) => answered.value.segmentId, 'segmentId', null),
      reason:
          'uma resposta guardada antes do nome voltava como sala quebrada, e '
          'o trecho já contado parava a tradução',
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

  test('a session read whose canon is gone is refused by its name, not taken '
      'for a lost session', () async {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': 'no kept canon for pin 2026-10-01',
            'code': 'CANON_NOT_KEPT',
          }),
          409,
        ),
      ),
    );
    addTearDown(repository.dispose);

    expect(
      await repository.fetchState('sessao-1'),
      _refusedWith(RefusalCode.canonNotKept),
      reason:
          'a leitura de uma sessão sem cânone chegava como um código que o '
          'tablet não conhecia',
    );
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
    'the room\'s books are a read, given up on the read\'s budget',
    () async {
      final repository = RoomRepository(
        client: MockClient((_) => Completer<http.Response>().future),
        stateTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(repository.dispose);

      expect(await repository.servedBooks(), isA<NetworkFailed>());
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

  test(
    'a escuta vai à sala pela porta da escuta com o mesmo corpo da conferência',
    () async {
      http.BaseRequest? seen;
      late String seenBody;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          seenBody = request.body;
          return http.Response(
            jsonEncode({
              'session_id': 's1',
              'automatic_check': false,
              'fixed_line': '',
              'refusal': null,
              'untranslated': [],
              'unheard_take_ids': ['t2'],
            }),
            200,
          );
        }),
      );
      addTearDown(repository.dispose);

      final naoOuvidas = _value(
        await repository.reportTheListening(
          's1',
          playedByTake: const [
            PlayedTake(
              takeId: 't1',
              playedRanges: [
                [0, 10000],
              ],
              clipDurationMs: 10000,
            ),
          ],
        ),
      );

      expect(seen!.method, 'POST');
      expect(
        seen!.url.path,
        endsWith('/sessions/s1/back-translation/listened-whole'),
      );
      expect(jsonDecode(seenBody), {
        'played_by_take': [
          {
            'take_id': 't1',
            'played_ranges': [
              [0, 10000],
            ],
            'clip_duration_ms': 10000,
          },
        ],
      });
      expect(naoOuvidas.unheardTakeIds, ['t2']);
    },
  );

  test(
    'uma resposta sem as partes não ouvidas se lê como não sabida, não como nenhuma',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'session_id': 's1'}), 200),
        ),
      );
      addTearDown(repository.dispose);

      final naoOuvidas = _value(
        await repository.reportTheListening(
          's1',
          playedByTake: const [
            PlayedTake(
              takeId: 't1',
              playedRanges: [
                [0, 10000],
              ],
              clipDurationMs: 10000,
            ),
          ],
        ),
      );

      expect(naoOuvidas.unheardTakeIds, isNull);
    },
  );

  test('the listen door\'s whole answer is read', () async {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'session_id': 's1',
            'unheard_take_ids': <String>[],
            'automatic_check': true,
            'fixed_line': 'N2',
            'refusal': 'STRETCH_UNTRANSLATED',
            'untranslated': [
              {'take_id': 't2', 'scene': 2, 'from_ms': 4000},
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(repository.dispose);

    final ouvida = _value(
      await repository.reportTheListening('s1', playedByTake: const []),
    );

    expect(ouvida.unheardTakeIds, isEmpty);
    expect(ouvida.automaticCheck, isTrue);
    expect(ouvida.fixedLine, 'N2');
    expect(ouvida.stretchUntranslated, isTrue);
    expect(
      [
        for (final parte in ouvida.untranslated)
          (parte.takeId, parte.scene, parte.from),
      ],
      [('t2', 2, const Duration(milliseconds: 4000))],
    );
  });

  test(
    'a terminei refused over an untranslated stretch is read with its parts, '
    'not as no refusal',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'session_id': 's1',
              'checked': false,
              'fixed_line': 'N2',
              'refusal': 'STRETCH_UNTRANSLATED',
              'untranslated': [
                {'take_id': 't2', 'scene': 2, 'from_ms': 0},
                {'take_id': 't3', 'scene': 3, 'from_ms': 7500},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final veredito = _value(
        await repository.finishBackTranslation('s1', playedByTake: const []),
      );

      expect(
        veredito.refusal,
        CheckRefusal.stretchUntranslated,
        reason: 'a recusa virava nenhuma, e o terminei caía em achados vazios',
      );
      expect(veredito.fixedLine, 'N2');
      expect(
        [
          for (final parte in veredito.untranslated)
            (parte.takeId, parte.scene, parte.from),
        ],
        [
          ('t2', 2, Duration.zero),
          ('t3', 3, const Duration(milliseconds: 7500)),
        ],
      );
    },
  );

  test(
    'a verdict heard to its end is reported with the round\'s stamp exactly as the room gave it',
    () async {
      http.BaseRequest? seen;
      String? seenBody;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          seenBody = request.body;
          return http.Response(jsonEncode({'marked': true}), 200);
        }),
      );
      addTearDown(repository.dispose);

      await repository.reportTheVerdictHeard(
        'sessao-1',
        '2026-10-19T19:58:13.123456Z',
      );

      expect(
        seen?.url.path,
        '/api/internalization-room/sessions/sessao-1/back-translation/heard',
      );
      expect(seen?.method, 'POST');
      expect(
        seenBody == null ? null : jsonDecode(seenBody!),
        {'at': '2026-10-19T19:58:13.123456Z'},
        reason:
            'a sala casa a rodada pelo carimbo até o milissegundo e com o fuso; '
            'um carimbo refeito no aparelho perdia o fuso e caía num 404',
      );
    },
  );

  test(
    'starting the translation over is one post to the room, and its answer is the frases left standing',
    () async {
      http.BaseRequest? seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'segments': [
                {
                  'segment_id': 'trecho-9',
                  'take_id': 'gravacao-1',
                  'starts_ms': 0,
                  'ends_ms': 4000,
                  'told': false,
                  'frase': null,
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(repository.dispose);

      final answer = await repository.startTheTranslationOver('sessao-1');

      expect(
        seen?.url.path,
        '/api/internalization-room/sessions/sessao-1/back-translation/restart',
      );
      expect(seen?.method, 'POST');
      expect(
        [for (final view in _value(answer)) view.segmentId],
        ['trecho-9'],
        reason:
            'a tela recomeçada lê as frases que a sala deixou de pé, nunca '
            'apaga por conta própria',
      );
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
    });

    test('the approval answer reads the row, the version and the blockers off '
        'the wire, not the lists a refusal used to lead to', () {
      final source = File(
        'lib/features/sala/domain/approval_answer.dart',
      ).readAsStringSync();
      final keys = {
        for (final key in RegExp(r"json\['(\w+)'\]").allMatches(source))
          key[1]!,
      };

      expect(
        keys,
        {'release_id', 'version', 'blockers'},
        reason:
            'a recusa trazia untold_take_ids, unheard_take_ids e '
            'untold_segment_id, que nada lia desde que ela só escreve o '
            'motivo; a dela lê só se saiu a versão, e por que não',
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

    test('an approval on a session whose canon is gone is refused by its name, '
        'not as the version race', () async {
      final repository = umaSala(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'detail': 'no kept canon for pin 2026-10-01',
              'code': 'CANON_NOT_KEPT',
            }),
            409,
          ),
        ),
      );

      expect(
        await repository.approveRelease('sessao-1'),
        _refusedWith(RefusalCode.canonNotKept),
        reason:
            'o 409 do cânone perdido chegava como um código que o tablet não '
            'conhecia, igual à corrida de versão',
      );
    });

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
        'takesListingOf': (room) => room.takesListingOf('sessao-1'),
        'sceneRehearsalsOf': (room) => room.sceneRehearsalsOf('sessao-1'),
        'keepSceneRehearsal': (room) async =>
            room.keepSceneRehearsal('sessao-1', await _tempRecording()),
        'askForAPerson': (room) => room.askForAPerson('sessao-1'),
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
        'restartTheSceneTranslation': (room) => room.restartTheSceneTranslation(
          'sessao-1',
          'ensaio-da-cena-1',
          attempt: '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
        ),
        'labelTheSceneRehearsal': (room) => room.labelTheSceneRehearsal(
          'sessao-1',
          'ensaio-da-cena-1',
          scene: 'S2',
        ),
        'keepTheSceneFrase': (room) async => room.keepTheSceneFrase(
          'sessao-1',
          'ensaio-da-cena-1',
          await _tempRecording(),
          startsMs: 0,
          endsMs: 3100,
        ),
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
            'servedBooks': (room) => room.servedBooks(),
            'collectTheCredential': (room) =>
                room.collectTheCredential('aparelho-1'),
            'askForACode': (room) => room.askForACode('aparelho-1'),
            'readTheLink': (room) => room.readTheLink('aparelho-1'),
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
            'servedBooks': () => answering(404).servedBooks(),
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

  group('the scene rehearsal doors', () {
    Map<String, Object?> record({
      String? sentAt,
      String? afterRestart,
      List<Map<String, Object?>> frases = const [],
    }) => {
      'rehearsal_id': 'ensaio-da-cena-1',
      'session_id': 'sessao-1',
      'pericope': 'P01',
      'n': 1,
      'scene': null,
      'scene_said': null,
      'duration_ms': 20000,
      'content_type': 'audio/mp4',
      'verified': true,
      'recorded_at': '2026-10-14T09:00:00+00:00',
      'sent_at': sentAt,
      'after_restart': afterRestart,
      'frases': frases,
    };

    test('the list parses after_restart, sent_at and the frases', () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'pericope': 'P01',
              'scene_rehearsals': [
                record(
                  sentAt: '2026-10-14T10:00:00+00:00',
                  afterRestart: '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
                  frases: [
                    {
                      'frase_id': 'f1',
                      'starts_ms': 0,
                      'ends_ms': 4000,
                      'replaces': null,
                      'replaced_by': 'f2',
                    },
                    {
                      'frase_id': 'f2',
                      'starts_ms': 0,
                      'ends_ms': 4600,
                      'replaces': 'f1',
                      'replaced_by': null,
                    },
                  ],
                ),
              ],
            }),
            200,
          );
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.sceneRehearsalsOf('sessao-1');

      expect(seen.method, 'GET');
      expect(
        seen.url.path,
        '/api/internalization-room/sessions/sessao-1/scene-rehearsals',
      );
      final listed = (answer as Answered<List<SceneRehearsalRecord>>).value;
      expect(listed, hasLength(1));
      final kept = listed.single;
      expect(kept.rehearsalId, 'ensaio-da-cena-1');
      expect(kept.sessionId, 'sessao-1');
      expect(kept.n, 1);
      expect(kept.sentAt, '2026-10-14T10:00:00+00:00');
      expect(kept.afterRestart, '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b');
      expect(kept.unsent, isFalse);
      expect(
        [
          for (final frase in kept.frases)
            (frase.fraseId, frase.startsMs, frase.endsMs, frase.replacedBy),
        ],
        [('f1', 0, 4000, 'f2'), ('f2', 0, 4600, null)],
      );
    });

    test('a frase with no place is read without one', () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'pericope': 'P01',
              'scene_rehearsals': [
                record(
                  frases: [
                    {'frase_id': 'f1', 'replaces': null, 'replaced_by': null},
                  ],
                ),
              ],
            }),
            200,
          ),
        ),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.sceneRehearsalsOf('sessao-1');

      final frase = (answer as Answered<List<SceneRehearsalRecord>>)
          .value
          .single
          .frases
          .single;
      expect((frase.startsMs, frase.endsMs), (null, null));
    });

    test(
      'the keep sends the take as this tablet and reads the record back',
      () async {
        late http.BaseRequest seen;
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen = request;
            return http.Response(jsonEncode(record()), 200);
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.keepSceneRehearsal(
          'sessao-1',
          await _tempRecording(),
        );

        expect(seen.method, 'POST');
        expect(
          seen.url.path,
          '/api/internalization-room/sessions/sessao-1/scene-rehearsals',
        );
        expect(seen.headers['X-Room-Device'], 'aparelho-1');
        expect(
          (answer as Answered<SceneRehearsalRecord>).value.rehearsalId,
          'ensaio-da-cena-1',
        );
      },
    );

    test('the label posts the scene to the rehearsal\'s scene door with the '
        'tablet\'s headers and reads the record back', () async {
      late http.Request seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({...record(), 'scene': 'S2'}), 200);
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);
      repository.presents('credencial-1');

      final answer = await repository.labelTheSceneRehearsal(
        'sessao-1',
        'r',
        scene: 'S2',
      );

      expect(seen.method, 'POST');
      expect(
        seen.url.path,
        '/api/internalization-room/sessions/sessao-1/scene-rehearsals/r/scene',
      );
      expect(seen.bodyFields, {'scene': 'S2'});
      expect(seen.headers['X-Device-Credential'], 'credencial-1');
      expect((answer as Answered<SceneRehearsalRecord>).value.scene, 'S2');
    });

    test('the restart posts attempt and closes as form fields', () async {
      late http.Request seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(
              record(afterRestart: 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11'),
            ),
            200,
          );
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.restartTheSceneTranslation(
        'sessao-1',
        'ensaio-da-cena-1',
        attempt: 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11',
        closes: '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
      );

      expect(seen.method, 'POST');
      expect(
        seen.url.path,
        '/api/internalization-room/sessions/sessao-1/scene-rehearsals/'
        'ensaio-da-cena-1/restart',
      );
      expect(seen.bodyFields, {
        'attempt': 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11',
        'closes': '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
      });
      expect(
        (answer as Answered<SceneRehearsalRecord>).value.afterRestart,
        'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11',
      );
    });

    test(
      'a frase posts its span, the attempt and its audio as this tablet, and the record carries the take\'s measured length',
      () async {
        late http.BaseRequest seen;
        late String body;
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen = request;
            body = request.body;
            return http.Response(
              jsonEncode(record(afterRestart: 'tentativa-1')),
              200,
            );
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.keepTheSceneFrase(
          'sessao-1',
          'ensaio-da-cena-1',
          await _tempRecording(),
          startsMs: 3100,
          endsMs: 7400,
          afterRestart: 'tentativa-1',
        );

        expect(seen.method, 'POST');
        expect(
          seen.url.path,
          '/api/internalization-room/sessions/sessao-1/scene-rehearsals/'
          'ensaio-da-cena-1/frases',
        );
        expect(seen.headers['X-Room-Device'], 'aparelho-1');
        expect(seen.headers['content-type'], contains('multipart/form-data'));
        for (final (field, value) in [
          ('starts_ms', '3100'),
          ('ends_ms', '7400'),
          ('after_restart', 'tentativa-1'),
        ]) {
          expect(body, contains('name="$field"\r\n\r\n$value\r\n'));
        }
        expect(body, contains('name="file"'));
        expect(
          (answer as Answered<SceneRehearsalRecord>).value.durationMs,
          20000,
        );
      },
    );

    test('a frase with no restart names no attempt', () async {
      late String body;
      final repository = RoomRepository(
        client: MockClient((request) async {
          body = request.body;
          return http.Response(jsonEncode(record()), 200);
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      await repository.keepTheSceneFrase(
        'sessao-1',
        'ensaio-da-cena-1',
        await _tempRecording(),
        startsMs: 0,
        endsMs: 3100,
      );

      expect(body, isNot(contains('name="after_restart"')));
    });

    for (final (named, replaces) in [
      ('a frase translated again names the frase it replaces', 'frase-3'),
      ('a new frase names nothing it replaces', null),
    ]) {
      test(named, () async {
        late String body;
        final repository = RoomRepository(
          client: MockClient((request) async {
            body = request.body;
            return http.Response(jsonEncode(record()), 200);
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        await repository.keepTheSceneFrase(
          'sessao-1',
          'ensaio-da-cena-1',
          await _tempRecording(),
          startsMs: 9000,
          endsMs: 13000,
          replaces: replaces,
        );

        if (replaces == null) {
          expect(body, isNot(contains('name="replaces"')));
        } else {
          expect(body, contains('name="replaces"\r\n\r\n$replaces\r\n'));
        }
      });
    }

    test('the two 409 codes come back as refusals naming them', () async {
      for (final code in [
        RefusalCode.sceneRehearsalSent,
        RefusalCode.restartOutOfOrder,
      ]) {
        final repository = RoomRepository(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'code': code, 'detail': 'recusado'}),
              409,
            ),
          ),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.restartTheSceneTranslation(
          'sessao-1',
          'ensaio-da-cena-1',
          attempt: 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11',
        );

        expect(answer, isA<Refused>().having((r) => r.code, 'code', code));
      }
    });

    test('the list reads each rehearsal\'s scene and recording time', () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'pericope': 'P01',
              'scene_rehearsals': [
                {...record(), 'scene': 'S2'},
                {...record(), 'recorded_at': ''},
                {...record(), 'scene': 'cena-dois', 'recorded_at': 'ontem'},
              ],
            }),
            200,
          ),
        ),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.sceneRehearsalsOf('sessao-1');

      final [labelled, untimed, unreadable] =
          (answer as Answered<List<SceneRehearsalRecord>>).value;
      expect(labelled.sceneNumber, 2);
      expect(labelled.recordedAt, DateTime.utc(2026, 10, 14, 9));
      expect(untimed.sceneNumber, isNull);
      expect(untimed.recordedAt, isNull);
      expect(unreadable.sceneNumber, isNull);
      expect(unreadable.recordedAt, isNull);
    });

    test(
      'the list reads whether each sent rehearsal is a confirmed WAV',
      () async {
        final sent = record(sentAt: '2026-10-14T09:05:00+00:00');
        final repository = RoomRepository(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'pericope': 'P01',
                'scene_rehearsals': [
                  {...sent, 'content_type': 'audio/wav', 'verified': true},
                  {...sent, 'content_type': 'audio/x-wav', 'verified': true},
                  {...sent, 'content_type': 'audio/mp4', 'verified': true},
                  {...sent, 'content_type': 'audio/wav', 'verified': false},
                  {...sent, 'verified': true}..remove('content_type'),
                  {...sent, 'content_type': 'audio/wav'}..remove('verified'),
                ],
              }),
              200,
            ),
          ),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.sceneRehearsalsOf('sessao-1');

        expect(
          (answer as Answered<List<SceneRehearsalRecord>>).value.map(
            (rehearsal) => rehearsal.joinable,
          ),
          [true, true, false, false, true, false],
        );
      },
    );

    test('the list reads each rehearsal\'s fingerprint, and none from an '
        'older room', () async {
      final sent = record(sentAt: '2026-10-14T09:05:00+00:00');
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'pericope': 'P01',
              'scene_rehearsals': [
                {...sent, 'sha256': 'ab12'},
                {...sent}..remove('sha256'),
              ],
            }),
            200,
          ),
        ),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.sceneRehearsalsOf('sessao-1');

      expect(
        (answer as Answered<List<SceneRehearsalRecord>>).value.map(
          (rehearsal) => rehearsal.sha256,
        ),
        ['ab12', null],
      );
    });

    test(
      'the scene send posts its turn id and the attempt it closes',
      () async {
        final seen = <http.Request>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen.add(request);
            return http.Response(_turnBody(), 200);
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final closing = await repository.sendTheSceneRehearsal(
          's',
          'r',
          turnId: '7f0c1f9e-2b9a-4c47-9d0e-5f3b8a1c2d4e',
          closes: '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
        );
        await repository.sendTheSceneRehearsal(
          's',
          'r',
          turnId: '7f0c1f9e-2b9a-4c47-9d0e-5f3b8a1c2d4e',
        );

        expect(seen.first.method, 'POST');
        expect(
          seen.first.url.path,
          '/api/internalization-room/sessions/s/scene-rehearsals/r/send',
        );
        expect(seen.first.bodyFields, {
          'turn_id': '7f0c1f9e-2b9a-4c47-9d0e-5f3b8a1c2d4e',
          'closes': '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b',
        });
        expect(seen.last.bodyFields, {
          'turn_id': '7f0c1f9e-2b9a-4c47-9d0e-5f3b8a1c2d4e',
        });
        expect((closing as Answered<TurnResult>).value.sessionId, 'sessao-1');
      },
    );

    test('the scene send\'s refusals come back by code', () async {
      for (final (status, code) in [
        (409, RefusalCode.sceneRehearsalSending),
        (409, RefusalCode.sceneRehearsalSent),
        (409, RefusalCode.restartOutOfOrder),
        (404, RefusalCode.notFound),
      ]) {
        final repository = RoomRepository(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'code': code, 'detail': 'recusado'}),
              status,
            ),
          ),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.sendTheSceneRehearsal(
          'sessao-1',
          'ensaio-da-cena-1',
          turnId: '7f0c1f9e-2b9a-4c47-9d0e-5f3b8a1c2d4e',
        );

        expect(answer, isA<Refused>().having((r) => r.code, 'code', code));
      }
    });

    test('a frase\'s audio is asked at its own door', () {
      expect(
        RoomRepository.sceneFraseAudioUrl('s', 'r', 'f2'),
        '/api/internalization-room/sessions/s/scene-rehearsals/r/frases/f2/audio',
      );
    });
  });

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

    test('a joined part goes up naming its rehearsal, the take it replaces, '
        'and the reopening only when the team armed it', () async {
      final file = await _tempRecording(extension: 'wav', bytes: aWavTake());

      await listening().sendTake(
        'sessao-1',
        file,
        kind: 'ensaio',
        scope: 'parte-2',
        origin: 'ensaio-2',
        reopensTheApprovedDraft: true,
        overTake: 'gravacao-7',
      );
      final armed = latin1.decode(sent.bodyBytes);
      await listening().sendTake(
        'sessao-1',
        file,
        kind: 'ensaio',
        scope: 'parte-2',
      );
      final plain = latin1.decode(sent.bodyBytes);

      expect(armed, contains('name="origin"\r\n\r\nensaio-2\r\n'));
      expect(
        armed,
        contains('name="reopens_the_approved_draft"\r\n\r\ntrue\r\n'),
      );
      expect(armed, contains('name="over_take"\r\n\r\ngravacao-7\r\n'));
      expect(plain, isNot(contains('name="origin"')));
      expect(plain, isNot(contains('name="over_take"')));
      expect(plain, isNot(contains('reopens_the_approved_draft')));
    });

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

    group('a scene take goes up to the room as audio/wav, with the scene label '
        'when the record tap gave one', () {
      test('labelled', () async {
        final wav = aWavTake();
        final file = await _tempRecording(extension: 'wav', bytes: wav);

        await listening().keepSceneRehearsal('sessao-1', file, scene: 'S2');

        final part = _filePart(sent);
        expect(
          part.head,
          contains('content-type: audio/wav'),
          reason:
              'a sala chama de WAV só o que o envio declara WAV, e '
              'guardava a cena como cena.m4a',
        );
        expect(part.head, matches(RegExp(r'filename="[^"]+\.wav"')));
        expect(part.content, wav);
        expect(
          latin1.decode(sent.bodyBytes),
          contains('name="scene"\r\n\r\nS2\r\n'),
        );
      });

      test('unlabelled', () async {
        final file = await _tempRecording(extension: 'wav', bytes: aWavTake());

        await listening().keepSceneRehearsal('sessao-1', file);

        expect(latin1.decode(sent.bodyBytes), isNot(contains('name="scene"')));
      });
    });

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

    test('a sentence recorded again goes up whole as audio/wav, under the id '
        'the tablet minted for it', () async {
      final wav = aWavTake();
      late http.Request pedido;
      final repository = RoomRepository(
        client: MockClient((request) async {
          pedido = request;
          return http.Response(
            jsonEncode({
              'session_id': 'sessao-1',
              'segments': [
                {
                  'segment_id': 'trecho-3',
                  'take_id': 'gravacao-3',
                  'starts_ms': 0,
                  'ends_ms': 3200,
                  'frase': 3,
                },
              ],
            }),
            200,
          );
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      final answer = await repository.reRecordTheSentence(
        'sessao-1',
        'trecho-3',
        await _tempRecording(extension: 'wav', bytes: wav),
        sentenceId: '1792447878466000-0',
      );

      expect(
        pedido.url.path,
        '/api/internalization-room/sessions/sessao-1/segments/trecho-3/sentence',
      );
      expect(pedido.headers['X-Room-Device'], 'aparelho-1');
      final body = latin1.decode(pedido.bodyBytes);
      expect(
        RegExp(
          'name="sentence_id"\r\n\r\n([^\r]*)\r\n',
        ).firstMatch(body)?.group(1),
        '1792447878466000-0',
        reason: 'sem o id da gravação um reenvio cortaria a frase duas vezes',
      );
      expect(_filePart(pedido).head, contains('content-type: audio/wav'));
      expect(_filePart(pedido).content, wav);
      final segment = _value(answer).segments.single;
      expect((segment.takeId, segment.endsMs), ('gravacao-3', 3200));
    });

    test(
      'the replace and sentence doors ask for the stale stretches too',
      () async {
        final seen = <http.BaseRequest>[];
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen.add(request);
            return http.Response(
              jsonEncode({'session_id': 'sessao-1', 'segments': []}),
              200,
            );
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        await repository.replaceSegment(
          'sessao-1',
          'trecho-1',
          await _tempRecording(),
          takeId: 'gravacao-1',
          from: Duration.zero,
          to: const Duration(seconds: 4),
          idempotencyKey: 'chave-1',
        );
        await repository.reRecordTheSentence(
          'sessao-1',
          'trecho-3',
          await _tempRecording(extension: 'wav', bytes: aWavTake()),
          sentenceId: '1792447878466000-0',
        );

        expect(
          [for (final request in seen) request.url.queryParameters],
          [
            {'include_stale': 'true'},
            {'include_stale': 'true'},
          ],
          reason:
              'as respostas trazem a lista da passagem, e sem pedir ela vinha '
              'sem os trechos regravados',
        );
      },
    );

    test(
      'a stale stretch in the answer of a stretch told again never comes back as one that counts',
      () async {
        final repository = RoomRepository(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'session_id': 'sessao-1',
                'segments': [
                  {
                    'segment_id': 'trecho-1',
                    'take_id': 'gravacao-1',
                    'starts_ms': 0,
                    'ends_ms': 4000,
                    'frase': 1,
                    'stale': false,
                  },
                  {
                    'segment_id': 'trecho-2',
                    'take_id': 'gravacao-2',
                    'starts_ms': 0,
                    'ends_ms': 3000,
                    'frase': null,
                    'stale': true,
                  },
                ],
              }),
              200,
            ),
          ),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);

        final answer = await repository.replaceSegment(
          'sessao-1',
          'trecho-1',
          await _tempRecording(),
          takeId: 'gravacao-1',
          from: Duration.zero,
          to: const Duration(seconds: 4),
          idempotencyKey: 'chave-1',
        );

        expect(
          [for (final segment in _value(answer).segments) segment.segmentId],
          ['trecho-1'],
          reason:
              'a resposta sobrescreve a lista do tablet, e o trecho regravado '
              'voltava como trecho traduzido',
        );
      },
    );

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
  group('the session\'s scenes door', () {
    test(
      'case 1 (a): the scene list is read from the session\'s scenes door in '
      'passage order',
      () async {
        late http.Request seen;
        final repository = RoomRepository(
          client: MockClient((request) async {
            seen = request;
            return http.Response(
              jsonEncode({
                'scenes': [
                  {'scene_id': 'S1', 'title': 'Ouvir a notícia e partir'},
                  {'scene_id': 'S2', 'title': 'Primeiro apelo e recusa'},
                  {'scene_id': 'S3', 'title': 'Segundo apelo e a separação'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          deviceId: () async => 'aparelho-1',
        );
        addTearDown(repository.dispose);
        repository.presents('credencial-1');

        final answer = await repository.scenesOf('s');

        expect(seen.method, 'GET');
        expect(seen.url.path, '/api/internalization-room/sessions/s/scenes');
        expect(seen.headers['X-Device-Credential'], 'credencial-1');
        expect(
          [
            for (final scene in (answer as Answered<List<Scene>>).value)
              (scene.sceneId, scene.title),
          ],
          [
            ('S1', 'Ouvir a notícia e partir'),
            ('S2', 'Primeiro apelo e recusa'),
            ('S3', 'Segundo apelo e a separação'),
          ],
        );
      },
    );

    test('case 1 (b): the scenes door gives up after 4 seconds', () async {
      var heard = false;
      final repository = RoomRepository(
        client: MockClient((_) {
          heard = true;
          return Completer<http.Response>().future;
        }),
      );
      addTearDown(repository.dispose);
      final clock = FakeAsync();
      RoomAnswer<List<Scene>>? answer;
      clock.run(
        (_) =>
            unawaited(repository.scenesOf('s').then((given) => answer = given)),
      );
      while (!heard) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        clock.flushMicrotasks();
      }

      clock.elapse(const Duration(milliseconds: 3900));
      expect(answer, isNull);
      clock.elapse(const Duration(milliseconds: 200));
      expect(
        answer,
        isA<NetworkFailed>().having((f) => f.reason, 'reason', 'timeout'),
      );
    });

    test('case 1 (c): a 404 at the scenes door is the session gone', () async {
      final repository = RoomRepository(
        client: MockClient((_) async => http.Response('{}', 404)),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(repository.dispose);

      expect(await repository.scenesOf('s'), isA<SessionGone>());
    });
  });
  group('a turn', () {
    Future<String> bodyOf(CutPoint? cut) async {
      late String body;
      final repository = RoomRepository(
        client: MockClient((request) async {
          body = request.body;
          return http.Response(_turnBody(), 200);
        }),
      );
      addTearDown(repository.dispose);
      await repository.sendTurn(
        'sessao-1',
        await _tempRecording(),
        turnId: 'turno-1',
        cut: cut,
      );
      return body;
    }

    String? field(String body, String name) =>
        RegExp('name="$name"\r\n\r\n([^\r]*)\r\n').firstMatch(body)?.group(1);

    test(
      'after an interruption carries the three fields the room reads',
      () async {
        final body = await bodyOf(
          const CutPoint(
            Duration(milliseconds: 2400),
            of: Duration(milliseconds: 9000),
          ),
        );

        expect(field(body, 'interrupted'), 'true');
        expect(field(body, 'interrupted_at_ms'), '2400');
        expect(field(body, 'interrupted_of_ms'), '9000');
      },
    );

    test(
      'after an interruption of unknown length leaves its length out',
      () async {
        final body = await bodyOf(const CutPoint(Duration(milliseconds: 3000)));

        expect(field(body, 'interrupted'), 'true');
        expect(field(body, 'interrupted_at_ms'), '3000');
        expect(body, isNot(contains('name="interrupted_of_ms"')));
      },
    );

    test('and a turn with no interruption carries none of the three', () async {
      final body = await bodyOf(null);

      expect(body, isNot(contains('name="interrupted')));
    });
  });

  group('the grain door', () {
    late List<http.Request> seen;
    late RoomRepository repository;

    setUp(() {
      seen = [];
      repository = RoomRepository(
        client: MockClient((request) async {
          seen.add(request);
          return http.Response(
            jsonEncode({
              'grain': 'whole',
              'takes': [
                {
                  'take_id': 'gravacao-1',
                  'kind': 'ensaio',
                  'scope': 'parte-1',
                  'ordinal': 1,
                  'set_aside_at': '2026-10-23T10:00:00+00:00',
                },
                {
                  'take_id': 'gravacao-2',
                  'kind': 'ensaio',
                  'scope': 'passagem-inteira',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(repository.dispose);
    });

    test(
      'a switch posts the grain as JSON to the session\'s grain door',
      () async {
        await repository.switchTheGrain('S', Grain.whole);

        expect(seen.single.method, 'POST');
        expect(
          seen.single.url.path,
          '/api/internalization-room/sessions/S/grain',
        );
        expect(
          seen.single.headers['content-type'],
          contains('application/json'),
        );
        expect(jsonDecode(seen.single.body), {'grain': 'whole'});
      },
    );

    test('a switch that re-opens the approved draft says so', () async {
      await repository.switchTheGrain(
        'S',
        Grain.scene,
        reopensTheApprovedDraft: true,
      );

      expect(jsonDecode(seen.single.body), {
        'grain': 'scene',
        'reopens_the_approved_draft': true,
      });
    });

    test(
      'the door answers the listing with the grain in force and what was set '
      'aside',
      () async {
        final listing = _value(
          await repository.switchTheGrain('S', Grain.whole),
        );

        expect(listing.grain, Grain.whole);
        expect(
          [for (final take in listing.takes) take.setAside],
          [true, false],
        );
      },
    );

    test(
      'the takes listing reads the grain in force and what was set aside',
      () async {
        final listing = _value(await repository.takesListingOf('S'));

        expect(
          seen.single.url.path,
          '/api/internalization-room/sessions/S/takes',
        );
        expect(listing.grain, Grain.whole);
        expect(
          [for (final take in listing.takes) take.setAside],
          [true, false],
        );
      },
    );
  });

  test('a room without the grain door answers its 404 as a refusal, never as a '
      'session gone', () async {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response('{"detail": "Not Found"}', 404),
      ),
    );
    addTearDown(repository.dispose);

    final answer = await repository.switchTheGrain('S', Grain.whole);

    expect(answer, _refusedWith('NOT_FOUND'));
  });

  test(
    'a listing from a room that never sets aside reads no grain and nothing set '
    'aside',
    () async {
      final repository = RoomRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'takes': [
                {'take_id': 'gravacao-1', 'kind': 'ensaio', 'scope': 'parte-1'},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(repository.dispose);

      final listing = _value(await repository.takesListingOf('S'));

      expect(listing.grain, isNull);
      expect(listing.takes.single.setAside, isFalse);
    },
  );
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
