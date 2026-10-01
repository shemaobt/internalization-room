import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test('a blocking halt over a standing warning, lifted, leaves the warning '
      'standing', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 400))
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await waitFor('o aviso chegar', () => read().warning);

    harness.room.holdNextTurn();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.room.serverHalt = HaltKind.blocking;
    await waitFor('a parada vencer o aviso', () => read().needsPerson);

    harness.network.reachable = false;
    harness.room.reachable = false;
    harness.room.failHeldTurnWith = const NetworkFailed('sem rede');
    harness.room.finishHeldTurn();
    await waitFor('a sala ficar sem alcance', () => read().unreachable);

    notifier.resolveWithPerson();
    await settle();

    expect(
      read().needsPerson,
      isFalse,
      reason: 'soltou sem ninguém a quem perguntar',
    );
    expect(
      read().warning,
      isTrue,
      reason:
          'o aviso só acaba quando uma leitura da sessão diz que acabou; a '
          'parada que passou por cima dele não o levou embora',
    );
  });
}
