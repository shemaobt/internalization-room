import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _thePassageClosed = Refused('PASSAGE_CLOSED');
const _oneStepOfTheLadder = Duration(milliseconds: 20);
const _severalStepsOfTheLadder = Duration(milliseconds: 300);

Future<ProviderContainer> _naPassagem(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  sala.entrarNaOferecida();
  await waitFor(
    'a passagem abrir',
    () => container.read(salaSessionProvider).sessionId != null,
  );
  await settle();
  return container;
}

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

SalaSessionNotifier _sala(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

Future<void> _naEscolha(ProviderContainer container) => waitFor(
  'a sala abrir a Escolha',
  () =>
      _estado(container).stage == SalaStage.escolha &&
      _estado(container).naRoda != null,
);

Future<void> _aPassagemFechaNoPedidoDePessoa(
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room
    ..failTurnsWith = const Refused('PIPELINE_REFUSED')
    ..askForAPersonFailsWith = _thePassageClosed;
  _sala(container).conversaTap();
  await settle();
  _sala(container).conversaTap();
  await waitFor(
    'o pedido de pessoa sair',
    () => harness.room.calls.contains('askForAPerson'),
  );
}

Future<List<PendingTake>> _daSessao(
  SalaHarness harness,
  String sessionId,
) async => [
  for (final row in await harness.takes.entries())
    if (row.sessionId == sessionId) row,
];

void main() {
  test(
    'a passage closed on the call for a person is asked once and never again',
    () async {
      final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
      final container = await _naPassagem(harness);

      await _aPassagemFechaNoPedidoDePessoa(harness, container);
      await settle(_severalStepsOfTheLadder);

      final calls = harness.room.calls;
      expect(calls.where((call) => call == 'askForAPerson'), hasLength(1));
      expect(
        calls
            .skip(calls.indexOf('askForAPerson') + 1)
            .where((call) => call != 'passagesOf'),
        isEmpty,
        reason:
            'o servidor disse que a passagem fechou; nenhum pedido volta a '
            'nomear a sessão, nem a Watch nem a escada',
      );
    },
  );

  test('a passage closed on the call for a person leaves the room at the '
      'Choice with nothing of the session on the tablet', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await _naPassagem(harness);
    final sessao = _estado(container).sessionId!;
    final linha = await harness.takes.enqueue(
      harness.recorder.aFile('parte-guardada'),
      sessionId: sessao,
      kind: 'ensaio',
      scope: 'parte-1',
      passNumber: 1,
      chunkIndex: 1,
    );
    expect(await harness.emAberto.of('Ruth', 'P01'), isNotNull);

    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    await _naEscolha(container);
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).stage, SalaStage.escolha);
    expect(_estado(container).sessionId, isNull);
    expect(_estado(container).voice, isNot(VoiceState.listening));
    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(await _daSessao(harness, sessao), isEmpty);
    expect(File(linha.path).existsSync(), isFalse);
    expect(
      harness.room.calls,
      isNot(contains('sendTake')),
      reason: 'a linha sai da Outbox descartada, não enviada',
    );
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, isEmpty);
  });

  test('a passage closed shows closed on the Wheel', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);

    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    await _naEscolha(container);

    expect(_estado(container).feitas, contains('P01'));
  });

  test('a halt standing when the passage closes is cleared with no call and '
      'no stop-call', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await _naPassagem(harness);

    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    await waitFor('a parada chegar', () => _estado(container).needsPerson);
    harness.room.finishHeldAskForAPerson();
    await _naEscolha(container);
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, isEmpty);
  });

  test('a passage closed is asked once even when the room comes back while '
      'it is being marked closed', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    int pedidos() =>
        harness.room.calls.where((call) => call == 'askForAPerson').length;
    void aRedeCai() {
      harness.network.reachable = false;
      harness.room.reachable = false;
    }

    void aRedeVolta() {
      harness.network.reachable = true;
      harness.room.reachable = true;
      harness.network.networkComesBack();
    }

    _sala(container).haltForABrokenBuild();
    aRedeCai();
    await waitFor(
      'a sala ficar fora de alcance',
      () => _estado(container).unreachable,
    );
    harness.room.askForAPersonFailsWith = _thePassageClosed;
    harness.finished.holdNextAdd();
    aRedeVolta();
    await waitFor('o pedido de pessoa sair', () => pedidos() == 1);
    await waitFor('a sala voltar', () => !_estado(container).unreachable);

    aRedeCai();
    await waitFor('a sala cair de novo', () => _estado(container).unreachable);
    aRedeVolta();
    await waitFor(
      'a sala voltar de novo',
      () => !_estado(container).unreachable,
    );
    await settle(_severalStepsOfTheLadder);
    harness.finished.finishHeldAdd();
    await _naEscolha(container);

    expect(pedidos(), 1);
  });
}
