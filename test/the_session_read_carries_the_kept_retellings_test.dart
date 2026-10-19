import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

RoomRepository _theRoomSays(Map<String, Object?> extra) => RoomRepository(
  client: MockClient(
    (request) async => http.Response(
      jsonEncode({
        'session_id': 'sessao-1',
        'pericope': 'P01',
        'status': 'in_progress',
        'coverage': {'engaged': 0, 'surfaced': 0, 'total': 29},
        'done': false,
        ...extra,
      }),
      200,
    ),
  ),
);

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test(
    'a session read carries each kept retelling with its scene, its turn and its link',
    () async {
      final repository = _theRoomSays({
        'kept_takes': [
          {
            'scope': 'S2',
            'turn_number': 5,
            'audio_url': 'https://storage.example/kept/aa/conto.m4a?sig=1',
          },
          {
            'scope': 'whole',
            'turn_number': 9,
            'audio_url': 'https://storage.example/kept/bb/conto.m4a?sig=2',
          },
        ],
      });
      addTearDown(repository.dispose);

      final read = await repository.fetchState('sessao-1');

      final kept = (read as Answered<SessionSnapshot>).value.keptRetellings;
      expect(
        kept.map((take) => (take.scope, take.turnNumber, take.audioUrl)),
        [
          ('S2', 5, 'https://storage.example/kept/aa/conto.m4a?sig=1'),
          ('whole', 9, 'https://storage.example/kept/bb/conto.m4a?sig=2'),
        ],
        reason: 'os takes mantidos que a sala mandou não chegaram ao tablet',
      );
    },
  );

  test(
    'a session read from a room that sends none has none, not a crash',
    () async {
      final repository = _theRoomSays({});
      addTearDown(repository.dispose);

      final read = await repository.fetchState('sessao-1');

      expect(
        read,
        isA<Answered<SessionSnapshot>>(),
        reason: 'uma leitura sem o campo novo era recusada como ilegível',
      );
      expect((read as Answered<SessionSnapshot>).value.keptRetellings, isEmpty);
    },
  );
}
