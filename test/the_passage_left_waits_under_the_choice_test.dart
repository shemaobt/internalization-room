import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
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

  test('a pill whose resume cannot be read with no network lays the passage '
      'left back on its canvas', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final tablet = await _onTheChoiceFromP01(harness);
    final read = tablet.read;
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    tablet.notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked for P02',
      () => harness.room.calls.skip(asked).contains('fetchState'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Canvas>(),
      reason:
          'a retomada da P02 sem rede refazia a Escolha sem roda e sem a P01',
    );
    expect(read().sessionId, tablet.p01);
    expect(read().pericope, 'P01');
    expect(read().coverage?.engaged, 2);
  });

  test('a passage left whose session the room lets go is not laid back by a '
      'pill that cannot open', () async {
    final tablet = await _onTheChoiceFromP01();
    final harness = tablet.harness;
    final read = tablet.read;
    await harness.takes.enqueue(
      harness.recorder.aFile('parte-da-p01'),
      sessionId: tablet.p01,
      kind: 'ensaio',
      scope: 'parte-1',
      passNumber: 1,
      chunkIndex: 1,
    );
    harness.room.forgetTheSession(tablet.p01);
    await tablet.notifier.refreshUnsent();
    await waitFor('the room to let P01 go', () => read().leftEntry == null);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    tablet.notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked for P02',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a sessão que a sala largou voltava como a passagem deixada',
    );
    expect(read().sessionId, isNull);
  });
}
