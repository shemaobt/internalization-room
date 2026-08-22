import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

String _turnBody() => jsonEncode({
      'session_id': 'sessao-1',
      'audio_base64': base64Encode([1, 2, 3]),
      'mime_type': 'audio/mpeg',
      'transcript': '',
      'peer_cue': false,
      'used_fail_safe': false,
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
