import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

class _TurnsOverTheWire extends FakeRoom {
  int? turnStatus;
  int turnsOverTheWire = 0;

  @override
  Future<RoomAnswer<TurnResult>> sendTurn(
    String sessionId,
    File audio, {
    required String turnId,
    String? clientTiming,
    Duration? timeout,
  }) async {
    final status = turnStatus;
    if (status == null) {
      return super.sendTurn(
        sessionId,
        audio,
        turnId: turnId,
        clientTiming: clientTiming,
        timeout: timeout,
      );
    }
    final take = File(
      '${Directory.systemTemp.path}/sala-turno-${DateTime.now().microsecondsSinceEpoch}.m4a',
    )..writeAsBytesSync([0, 1, 2, 3]);
    addTearDown(() {
      if (take.existsSync()) take.deleteSync();
    });
    final real = RoomRepository(
      client: MockClient((_) async {
        turnsOverTheWire++;
        return http.Response(
          jsonEncode({'detail': 'upstream failed', 'code': 'UPSTREAM_ERROR'}),
          status,
        );
      }),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(real.dispose);
    return real.sendTurn(sessionId, take, turnId: turnId);
  }
}

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test('a turn the server fails with a 5xx takes the room out of reach, '
      'never a strike or a halt', () async {
    final room = _TurnsOverTheWire();
    final harness = SalaHarness(room: room);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa();
    await settle();

    var outOfReach = false;
    container.listen(salaSessionProvider, (_, next) {
      if (next.offline) outOfReach = true;
    });
    room.turnStatus = 503;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle(const Duration(milliseconds: 300));

    expect(room.turnsOverTheWire, 1);
    expect(outOfReach, isTrue);
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });

  test('an opening that outlives the wait takes the room out of reach at '
      'once, with no thinking loop', () async {
    final harness = SalaHarness()
      ..room.failHeldTurnWith = const NetworkFailed('timeout');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final voices = <VoiceState>[];
    container.listen(salaSessionProvider, (_, next) => voices.add(next.voice));

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(1));
    expect(voices, contains(VoiceState.offline));
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });
}
