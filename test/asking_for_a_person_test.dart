import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

const _oneStepOfTheLadder = Duration(milliseconds: 20);
const _severalStepsOfTheLadder = Duration(milliseconds: 300);

int _callsForAPerson(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'askForAPerson').length;

Future<void> _stopForAPerson(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await waitFor('a sala pedir uma pessoa', () => read().needsPerson);
}

Future<void> _haltWithTheNetworkUp(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  notifier.conversaTap();
  await settle();
  for (var attempt = 0; attempt < 3; attempt++) {
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
  }
  await waitFor('a sala pedir uma pessoa', () => read().needsPerson);
}

void main() {
  test('the call flag is released when the call throws', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    final surfaced = <Object>[];
    final done = Completer<void>();

    runZonedGuarded(() async {
      try {
        harness.room
          ..failTurnsWith = const Refused('PIPELINE_REFUSED')
          ..askForAPersonThrowsOnce = StateError('o Env sem endereço');
        await _stopForAPerson(notifier, read);
        await settle();

        notifier.teamTapped();
        await waitFor('a sala descansar', () => !read().needsPerson);
        await _stopForAPerson(notifier, read);
        await waitFor(
          'o segundo pedido chegar',
          () => harness.room.personsAsked > 0,
        );
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }, (error, _) => surfaced.add(error));
    await done.future;

    expect(surfaced, [isA<StateError>()]);
    expect(harness.room.personsAsked, 1);
  });

  test('a call the server refused is made again', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const Refused('UNAUTHORIZED');
    await _stopForAPerson(notifier, read);
    await settle(_severalStepsOfTheLadder);

    expect(read().needsPerson, isTrue);
    expect(
      _callsForAPerson(harness),
      greaterThan(1),
      reason:
          'o pedido que nunca chegou ao servidor era dado por feito na '
          'hora de disparar: a sessão não entrava na fila da mesa, nenhum '
          'facilitador era avisado, e a equipe ficava parada esperando '
          'alguém que nunca foi chamado',
    );
  });

  test('a call refused with another code is made again', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room
      ..failTurnsWith = const Refused('PIPELINE_REFUSED')
      ..askForAPersonFailsWith = const Refused('HTTP_409');
    await _stopForAPerson(notifier, read);
    await settle(_severalStepsOfTheLadder);

    expect(read().needsPerson, isTrue);
    expect(_callsForAPerson(harness), greaterThan(1));
  });

  test('a call that fell on the network is asked again', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room
      ..failTurnsWith = const Refused('PIPELINE_REFUSED')
      ..askForAPersonFailsWith = const NetworkFailed('sem rede');
    await _stopForAPerson(notifier, read);
    await waitFor(
      'o pedido de pessoa sair',
      () => _callsForAPerson(harness) == 1,
    );
    await settle(_severalStepsOfTheLadder);
    expect(read().needsPerson, isTrue);
    harness.room.askForAPersonFailsWith = null;

    await waitFor(
      'o pedido de pessoa pousar na volta',
      () => harness.room.personsAsked == 1,
    );
    expect(_callsForAPerson(harness), greaterThan(1));
  });

  test('a call the server confirmed is not repeated', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder])
      ..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWithTheNetworkUp(notifier, read);
    await settle(_severalStepsOfTheLadder);

    expect(read().needsPerson, isTrue);
    expect(
      harness.room.personsAsked,
      1,
      reason:
          'o servidor confirmou o chamado na primeira vez; uma '
          'insistência que não sabe parar martela a rota a cada passo da '
          'escada, para sempre, em toda sala que parou',
    );
    expect(_callsForAPerson(harness), 1);
  });

  test('the person who arrives and resolves ends the insistence', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const Refused('UNAUTHORIZED');
    await _stopForAPerson(notifier, read);
    await waitFor(
      'a sala chamar uma pessoa',
      () => _callsForAPerson(harness) >= 1,
    );

    final pedidos = _callsForAPerson(harness);
    notifier.teamTapped();
    await settle(_severalStepsOfTheLadder);

    expect(
      _callsForAPerson(harness),
      pedidos,
      reason:
          'a pessoa chegou e tocou a tela; uma sala já atendida que '
          'continua chamando põe a mesma sessão de volta na fila da mesa. '
          'O pedido segue falhando depois do toque de propósito: com o '
          'servidor de pé, um passo da escada que sobrou vivo sucederia e '
          'encerraria a insistência por conta própria, e o teste passaria a '
          'medir a confirmação em vez do toque',
    );
  });
}
