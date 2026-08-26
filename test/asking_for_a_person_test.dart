import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle, until;

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
  await until(() => read().needsPerson);
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
  await until(() => read().needsPerson);
}

void main() {
  test('a call the server refused is made again', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const RoomRefused();
    await _stopForAPerson(notifier, read);
    await settle(_severalStepsOfTheLadder);

    expect(read().needsPerson, isTrue);
    expect(_callsForAPerson(harness), greaterThan(1),
        reason: 'o pedido que nunca chegou ao servidor era dado por feito na '
            'hora de disparar: a sessão não entrava na fila da mesa, nenhum '
            'facilitador era avisado, e a equipe ficava parada esperando '
            'alguém que nunca foi chamado');
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
    expect(harness.room.personsAsked, 1,
        reason: 'o servidor confirmou o chamado na primeira vez; uma '
            'insistência que não sabe parar martela a rota a cada passo da '
            'escada, para sempre, em toda sala que parou');
    expect(_callsForAPerson(harness), 1);
  });

  test('the person who arrives and resolves ends the insistence', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const RoomRefused();
    await _stopForAPerson(notifier, read);
    await until(() => _callsForAPerson(harness) >= 1);

    final pedidos = _callsForAPerson(harness);
    notifier.resolveWithPerson();
    await settle(_severalStepsOfTheLadder);

    expect(_callsForAPerson(harness), pedidos,
        reason: 'a pessoa chegou e tocou a tela; uma sala já atendida que '
            'continua chamando põe a mesma sessão de volta na fila da mesa. '
            'O pedido segue falhando depois do toque de propósito: com o '
            'servidor de pé, um passo da escada que sobrou vivo sucederia e '
            'encerraria a insistência por conta própria, e o teste passaria a '
            'medir a confirmação em vez do toque');
  });

  test('the room says it needs a person even with no confirmation', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder])
      ..room.failWith = const RoomRefused();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _stopForAPerson(notifier, read);

    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)),
        reason: 'a equipe está numa sala física e precisa saber que deve ir '
            'buscar alguém; calar a linha até o servidor confirmar deixaria a '
            'sala muda justamente quando a rede está ruim');
  });
}
