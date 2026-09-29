import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

Future<({ProviderContainer container, FakeTakeQueue fila})> _inASession(
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(pericope: 'P01');
  await waitFor(
    'a sala abrir uma sessão',
    () => container.read(salaSessionProvider).sessionId != null,
  );
  return (container: container, fila: harness.takes as FakeTakeQueue);
}

Future<void> _waiting(FakeTakeQueue fila, String sessionId, int howMany) async {
  for (var n = 0; n < howMany; n++) {
    await fila.enqueue(
      File('/tmp/tomada-$n.m4a'),
      sessionId: sessionId,
      kind: 'ensaio',
      scope: 'parte-${n + 1}',
    );
  }
}

void main() {
  test('an older reading never wins', () async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (:container, :fila) = await _inASession(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await _waiting(fila, read().sessionId!, 2);

    // A lê o disco com as duas gravações ainda lá e fica presa antes de publicar.
    // A espera é sobre A estar provadamente parada na retenção, com os números
    // já tomados — esperar uma duração deixaria a fila esvaziar primeiro, e A
    // leria o disco novo junto com B: verde, e sem corrida nenhuma.
    fila.holdTheNextReading();
    unawaited(notifier.refreshUnsent());
    await waitFor(
      'a leitura mais velha ficar presa com os números na mão',
      () => fila.readingHeld,
    );

    // As gravações vão embora e B lê o disco já vazio, e publica.
    fila.rows.clear();
    await notifier.refreshUnsent();
    expect(read().unsentTakes, 0, reason: 'B leu o disco novo e publicou');

    // Só agora a leitura velha de A chega.
    fila.releaseTheHeldReading();
    await settle();

    expect(
      read().unsentTakes,
      0,
      reason:
          'a leitura mais velha terminou por último, e o número que a '
          'equipe vê não pode ser decidido por quem chegou depois',
    );
  });

  test('the count is still right after ordinary work', () async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (:container, :fila) = await _inASession(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _waiting(fila, read().sessionId!, 1);
    await notifier.refreshUnsent();
    expect(read().unsentTakes, 1);

    await fila.flush();
    await notifier.refreshUnsent();
    expect(read().unsentTakes, 0);
  });

  test('the count still updates when the room comes back', () async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (:container, :fila) = await _inASession(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _waiting(fila, read().sessionId!, 2);
    await notifier.refreshUnsent();
    expect(read().unsentTakes, 2);

    harness.network.reachable = false;
    await notifier.goConversa(pericope: 'P01');
    await waitFor('a sala perceber que está sem sala', () => read().offline);

    harness.network.reachable = true;
    notifier.retryNow();

    await waitFor(
      'a contagem seguir a fila que esvaziou quando a sala voltou',
      () => read().unsentTakes == 0,
    );
  });
}
