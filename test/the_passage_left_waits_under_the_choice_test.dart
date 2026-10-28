import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

typedef _Tablet = ({
  SalaHarness harness,
  ProviderContainer container,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  String p01,
});

Future<_Tablet> _onTheChoiceFromP01([SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  harness.room.nextCoverage = coverage(engaged: 2, surfaced: 3);
  harness.room.nextMoment = const Moment(
    at: MomentAt.internalization,
    part: 1,
    parts: 3,
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await enterThePassage(notifier, read, 'P01');
  await waitFor(
    'P01 to open',
    () => read().sessionId != null && read().voice == VoiceState.invite,
  );
  final p01 = read().sessionId!;
  notifier.leaveThePassage();
  await waitFor(
    'the way back to P01 to be live',
    () => read().entriesOpen && read().theWayBackIsLive,
  );
  return (
    harness: harness,
    container: container,
    notifier: notifier,
    read: read,
    p01: p01,
  );
}

void main() {
  test('the way back with no network lands on the passage left as it was, '
      'asking the room for nothing', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    final asked = harness.room.calls.length;
    final checks = harness.inbox.checks;
    harness.room.reachable = false;

    await tablet.notifier.returnToTheLeftEntry();
    await settle();
    await settle();

    expect(
      read().station,
      isA<Canvas>(),
      reason: 'sem rede, a volta relia a sala e caía na Escolha sem roda',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage?.engaged, 2);
    expect(read().coverage?.surfaced, 3);
    expect(read().moment?.at, MomentAt.internalization);
    expect(read().moment?.part, 1);
    expect(read().moment?.parts, 3);
    expect(read().voice, VoiceState.invite);
    expect(
      harness.room.calls.skip(asked),
      isEmpty,
      reason: 'a volta lia as cenas, o estado da sessão e a roda',
    );
    expect(harness.inbox.checks, checks);
  });
}
