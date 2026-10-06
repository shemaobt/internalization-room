import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/port_adapters.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

import 'fakes.dart';

class _ASlowLedger extends FakeLinkedTeam {
  final reading = Completer<RememberedLink>();

  @override
  Future<RememberedLink> read() => reading.future;
}

void main() {
  test(
    'a call by the tablet whose ledger answers after the room is gone asks the room nothing',
    () async {
      final room = FakeRoom();
      final ledger = _ASlowLedger();
      final container = ProviderContainer(
        overrides: [
          roomRepositoryProvider.overrideWithValue(room),
          linkedTeamProvider.overrideWithValue(ledger),
        ],
      );
      final call = container
          .read(roomPortProvider)
          .askForAPersonWithoutASession();

      container.dispose();
      ledger.reading.complete(const RememberedLink(deviceId: 'tablet-1'));
      await call;

      expect(room.deviceAsksReceived, isEmpty);
    },
  );
}
