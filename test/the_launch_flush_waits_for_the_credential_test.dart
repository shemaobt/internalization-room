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

  testWidgets(
    'a relaunch with a queued take sends it with the credential after the link '
    'is read',
    (tester) async {
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

      final sent = harness.room.calls.indexOf('sendTake');
      expect(sent, isNonNegative, reason: 'a parte guardada tem de sair');
      expect(
        harness.room.presentedOnEachCall[sent],
        'credencial-1',
        reason:
            'sem a chave compartilhada, uma parte mandada antes de o vínculo ser '
            'lido é recusada e dada por perdida',
      );
    },
  );

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

  test('a credential presented after launch sends the waiting takes', () async {
    final harness = SalaHarness(
      linkedAs: const RememberedLink(
        deviceId: 'aparelho-1',
        team: TeamLink(projectId: 'equipe-1'),
      ),
      linkPoll: const Duration(milliseconds: 20),
      filaEmMemoria: true,
    );
    harness.room
      ..linkedTo = const TeamLink(projectId: 'equipe-1')
      ..refuseCredentialWith = const Refused(RefusalCode.credentialNotYet);
    await _aTakeIsQueued(harness);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await settle();
    expect(harness.room.calls, isNot(contains('sendTake')));

    harness.room.refuseCredentialWith = null;
    await waitFor(
      'a parte guardada sair',
      () => harness.room.calls.contains('sendTake'),
    );

    expect(
      harness.room.presentedOnEachCall[harness.room.calls.indexOf('sendTake')],
      'credencial-1',
      reason:
          'a credencial que chegou depois da abertura é a que abre a porta '
          'para as partes que esperavam',
    );
  });

  test('a relink sends the takes that were turned away', () async {
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

    room
      ..failWith = null
      ..credential = 'credencial-2'
      ..linkedTo = const TeamLink(projectId: 'equipe-1');
    await waitFor(
      'a parte recusada sair com a credencial nova',
      () => [
        for (var at = 0; at < room.calls.length; at++)
          if (room.calls[at] == 'sendTake') room.presentedOnEachCall[at],
      ].contains('credencial-2'),
    );
  });

  testWidgets('the launch tally counts the takes the launch flush already sent', (
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
    harness.room.takeLandsAfter = const Duration(milliseconds: 50);
    await _aTakeIsQueued(harness);

    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      (harness.takes as FakeTakeQueue).unsentAtEachTally.first,
      0,
      reason:
          'contada antes de a descarga voltar, a parte que já saiu aparece como '
          'pendente até a próxima contagem',
    );
  });
}
