import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

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

    await repository.createSession(pericope: 'OV');
    await repository.createSession(afterSession: 'panorama-1');
    await repository.createSession();

    expect(asked, [
      '{"pericope":"OV"}',
      '{"after_session":"panorama-1"}',
      '{}',
    ]);
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

  test('a malformed answer is a room failure, never a crash', () async {
    final repository = RoomRepository(
      client: MockClient((_) async => http.Response('{"nada":1}', 200)),
    );
    addTearDown(repository.dispose);

    expect(
      () => repository.createSession(),
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
