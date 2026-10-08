import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

const _sceneTwoOpen = {'at': 'internalization', 'part': 2, 'parts': 4};

RoomRepository _theRoomSays(Map<String, Object?> moment) => RoomRepository(
  client: MockClient(
    (request) async => http.Response(
      jsonEncode({
        'session_id': 'sessao-1',
        'pericope': 'P01',
        'status': 'in_progress',
        'audio_url': '/voice/turno',
        'coverage': {'engaged': 0, 'surfaced': 0, 'total': 29},
        'done': false,
        'moment': moment,
      }),
      200,
    ),
  ),
);

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test(
    'the moment the room sends with an answer and with a session read reaches the tablet',
    () async {
      final repository = _theRoomSays(_sceneTwoOpen);
      addTearDown(repository.dispose);

      final answer = await repository.openSession('sessao-1');
      final read = await repository.fetchState('sessao-1');

      final heard = (answer as Answered<TurnResult>).value.moment;
      final kept = (read as Answered<SessionSnapshot>).value.moment;
      for (final moment in [heard, kept]) {
        expect(
          moment?.at,
          MomentAt.internalization,
          reason: 'o momento que a sala mandou não chegou ao tablet',
        );
        expect(moment?.part, 2);
        expect(moment?.parts, 4);
      }
    },
  );

  test(
    'a moment missing the numbers its words need is no moment, not scene 0 of 0',
    () {
      const incomplete = [
        {'at': 'internalization', 'parts': 4},
        {'at': 'articulation', 'part': 2},
        {'at': 'familiarization'},
        {'at': 'ensaio_final', 'part': null},
      ];
      for (final json in incomplete) {
        expect(
          Moment.fromJson(json),
          isNull,
          reason:
              'um momento sem os números chegava à tela como cena 0 de 0: $json',
        );
      }
      expect(
        Moment.fromJson({
          'at': 'familiarization',
          'part': null,
          'parts': 4,
        })?.at,
        MomentAt.familiarization,
        reason: 'a Familiarização não tem cena, e só precisa das partes',
      );
    },
  );
}
