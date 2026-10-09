import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

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
}
