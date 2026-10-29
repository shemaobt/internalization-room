import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

Future<void> _aTakeIsQueued(SalaHarness harness) async {
  await harness.takes.enqueue(
    File('${harness.takesHome.path}/parte.m4a'),
    sessionId: 'sessao-1',
    kind: 'ensaio',
    scope: 'passagem',
  );
}

void main() {
  setUp(() => dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local'));

  testWidgets('a relaunch with a queued take sends nothing of it', (
    tester,
  ) async {
    final harness = SalaHarness(
      linkedAs: const RememberedLink(
        deviceId: 'aparelho-1',
        team: TeamLink(projectId: 'equipe-1'),
        credential: 'credencial-1',
      ),
      filaEmMemoria: true,
    );
    await _aTakeIsQueued(harness);

    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.room.calls, isNot(contains('sendTake')));
  });

  testWidgets('a relaunch with no link sends no queued take', (tester) async {
    final harness = SalaHarness(
      linkedAs: const RememberedLink(),
      filaEmMemoria: true,
    );
    await _aTakeIsQueued(harness);

    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      harness.room.calls,
      isNot(contains('sendTake')),
      reason:
          'sem vínculo não há credencial a apresentar, e a parte recusada é '
          'uma parte perdida',
    );
    expect(find.byType(CodigoView), findsOneWidget);
  });
  test('a relink sends nothing of the revoked life', () async {
    final harness = SalaHarness(
      linkedAs: const RememberedLink(
        deviceId: 'aparelho-1',
        team: TeamLink(projectId: 'equipe-1'),
        credential: 'credencial-1',
      ),
      linkPoll: const Duration(milliseconds: 20),
      filaEmMemoria: true,
    );
    final room = harness.room;
    final container = harness.container();
    addTearDown(container.dispose);
    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await _aTakeIsQueued(harness);

    room.failWith = const Refused(RefusalCode.deviceRevoked);
    await harness.takes.flush();
    await waitFor(
      'um código novo aparecer',
      () => container.read(deviceLinkProvider).code != null,
    );
    final sentBefore = room.calls.where((call) => call == 'sendTake').length;

    room
      ..failWith = null
      ..credential = 'credencial-2'
      ..linkedTo = const TeamLink(projectId: 'equipe-1');
    await waitFor(
      'o vínculo novo abrir a sala',
      () => container.read(deviceLinkProvider).linked,
    );
    await settle();

    expect(
      room.calls.where((call) => call == 'sendTake'),
      hasLength(sentBefore),
      reason:
          'a parte da vida revogada subiria com a credencial de uma equipe '
          'que talvez não seja a dela',
    );
  });
}
