import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/hand_inbox_repository.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test('the heard mark names the clip that played', () async {
    late http.Request seen;
    final inbox = HandInboxRepository(
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"status":"heard"}', 200);
      }),
      deviceId: () async => 'aparelho-1',
    );

    final agreed = await inbox.markHeard(
      'resposta-1',
      audioUrl: '/voz/resposta-1',
    );

    expect(agreed, isA<Answered<void>>());
    expect(seen.url.path, endsWith('/questions/resposta-1/heard'));
    expect(
      jsonDecode(seen.body),
      {'audio_url': '/voz/resposta-1'},
      reason:
          'a mesa só carimba a resposta que ainda é a atual; sem saber qual '
          'clipe tocou, uma regravação feita durante a escuta era dada como '
          'ouvida sem ninguém ter ouvido',
    );
    expect(seen.headers['content-type'], contains('application/json'));
  });

  test('a reply served with no address is marked bare, as before', () async {
    late http.Request seen;
    final inbox = HandInboxRepository(
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"status":"heard"}', 200);
      }),
      deviceId: () async => 'aparelho-1',
    );

    await inbox.markHeard('resposta-1', audioUrl: '');

    expect(seen.body, isEmpty);
    expect(seen.headers['content-type'] ?? '', isNot(contains('json')));
  });

  test('a desk that says the reply moved on is not agreement', () async {
    final inbox = HandInboxRepository(
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"code":"REPLY_MOVED_ON"}}',
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
      deviceId: () async => 'aparelho-1',
    );

    expect(
      await inbox.markHeard('resposta-1', audioUrl: '/voz/resposta-1'),
      isA<Refused>(),
    );
  });

  HandInboxRepository answering(int status) => HandInboxRepository(
    client: MockClient((_) async => http.Response('{}', status)),
    deviceId: () async => 'aparelho-1',
  );

  test(
    'a 404 at the heard mark is a refusal, never the session gone',
    () async {
      expect(
        await answering(
          404,
        ).markHeard('resposta-1', audioUrl: '/voz/resposta-1'),
        isA<Refused>().having((refusal) => refusal.code, 'code', 'NOT_FOUND'),
      );
    },
  );

  test('a 404 at a question names the session gone', () async {
    final casa = Directory.systemTemp.createTempSync('sala-pergunta');
    addTearDown(() => casa.deleteSync(recursive: true));
    final audio = File('${casa.path}/p.m4a')..writeAsBytesSync([0, 1, 2]);

    expect(
      await answering(404).sendQuestion('sessao-1', audio),
      isA<SessionGone>(),
    );
  });
}
