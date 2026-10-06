import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
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
    final harness = SalaHarness(
      retryBackoff: const [_oneStepOfTheLadder],
      watchesWithoutAHalt: true,
    );
    final container = await _naPassagem(harness);
    final sessao = _estado(container).sessionId!;
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).resolveWithPerson();
    await waitFor('a parada sair', () => !_estado(container).needsPerson);
    _sala(container).conversaTap();
    await waitFor(
      'o microfone abrir na conversa',
      () => _estado(container).voice == VoiceState.listening,
    );
    final apagadasAntes = harness.recorder.deleted.length;
    final linha = await harness.takes.enqueue(
      harness.recorder.aFile('parte-guardada'),
      sessionId: sessao,
      kind: 'ensaio',
      scope: 'parte-1',
      passNumber: 1,
      chunkIndex: 1,
    );
    expect(await harness.emAberto.of('Ruth', 'P01'), isNotNull);
    expect(harness.room.calls, contains('fetchState'));
    final chegadas = harness.room.personArrivedSessions.length;

    final antes = harness.room.calls.length;
    harness.room.finishHeldAskForAPerson();
    await _naEscolha(container);
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).stage, SalaStage.escolha);
    expect(_estado(container).voice, isNot(VoiceState.listening));
    expect(
      harness.recorder.deleted.skip(apagadasAntes),
      [harness.recorder.lastPath],
      reason: 'a gravação aberta é descartada',
    );
    expect(
      harness.room.calls.skip(antes),
      isNot(contains('fetchState')),
      reason: 'a Watch termina com a sessão',
    );
    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(await _daSessao(harness, sessao), isEmpty);
    expect(File(linha.path).existsSync(), isFalse);
    expect(
      harness.room.calls,
      isNot(contains('sendTake')),
      reason: 'a linha sai da Outbox descartada, não enviada',
    );
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, hasLength(chegadas));
  });

  test('a passage closed after the team left it is closed on the tablet, '
      'and the room stays at the Choice', () async {
    final harness = SalaHarness(retryBackoff: const [_oneStepOfTheLadder]);
    final container = await _naPassagem(harness);
    final sessao = _estado(container).sessionId!;
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await settle();
    expect(_estado(container).feitas, isNot(contains('P01')));
    expect(await harness.emAberto.of('Ruth', 'P01'), isNotNull);
    final linha = await harness.takes.enqueue(
      harness.recorder.aFile('parte-guardada'),
      sessionId: sessao,
      kind: 'ensaio',
      scope: 'parte-1',
      passNumber: 1,
      chunkIndex: 1,
    );

    harness.room.finishHeldAskForAPerson();
    await waitFor(
      'a Roda mostrar a passagem fechada',
      () => _estado(container).feitas.contains('P01'),
    );
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).stage, SalaStage.escolha);
    expect(_estado(container).naRoda, isNotNull);
    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(await _daSessao(harness, sessao), isEmpty);
    expect(File(linha.path).existsSync(), isFalse);
    expect(harness.room.calls, isNot(contains('sendTake')));
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

  test('a passage closed after the team moved on to another passage still '
      'calls a person for the halt of the passage they are in', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    final primeira = _estado(container).sessionId!;
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await _sala(container).goConversa(pericope: 'P02');
    await waitFor(
      'a outra passagem abrir',
      () =>
          _estado(container).sessionId != null &&
          _estado(container).sessionId != primeira,
    );
    final segunda = _estado(container).sessionId!;
    _sala(container).conversaTap();
    await settle();
    _sala(container).conversaTap();
    await waitFor('a parada chegar', () => _estado(container).needsPerson);
    harness.finished.holdNextAdd();

    harness.room.finishHeldAskForAPerson();
    await settle();
    harness.room.askForAPersonFailsWith = null;
    harness.finished.finishHeldAdd();
    await waitFor(
      'a sala chamar alguém para a outra passagem',
      () => harness.room.personsAsked == 1,
    );

    expect(harness.room.personAsksFor, [primeira, segunda]);
    expect(_estado(container).needsPerson, isTrue);
  });

  test('an earlier session\'s answer that lands once no halt stands calls '
      'nobody for the passage the team is in', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    final primeira = _estado(container).sessionId!;
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    harness.room.failTurnsWith = null;
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await _sala(container).goConversa(pericope: 'P02');
    await waitFor(
      'a outra passagem abrir',
      () =>
          _estado(container).sessionId != null &&
          _estado(container).sessionId != primeira,
    );
    expect(_estado(container).needsPerson, isFalse);

    harness.room.askForAPersonFailsWith = null;
    harness.room.finishHeldAskForAPerson();
    await settle(_severalStepsOfTheLadder);

    expect(harness.room.personAsksFor, [primeira]);
  });

  test('a call for an earlier session that fell on the network leaves the call '
      'for the current session to the return of the room', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    final primeira = _estado(container).sessionId!;
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    harness.room.askForAPersonFailsWith = const NetworkFailed('sem rede');
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await _sala(container).goConversa(pericope: 'P02');
    await waitFor(
      'a outra passagem abrir',
      () =>
          _estado(container).sessionId != null &&
          _estado(container).sessionId != primeira,
    );
    final segunda = _estado(container).sessionId!;
    _sala(container).conversaTap();
    await settle();
    _sala(container).conversaTap();
    await waitFor('a parada chegar', () => _estado(container).needsPerson);
    harness.network.reachable = false;

    harness.room.finishHeldAskForAPerson();
    await waitFor(
      'a sala ficar fora de alcance',
      () => _estado(container).unreachable,
    );
    await settle(_severalStepsOfTheLadder);
    expect(harness.room.personAsksFor, [primeira]);

    harness.room.askForAPersonFailsWith = null;
    harness.network.reachable = true;
    harness.network.networkComesBack();
    await waitFor(
      'a sala chamar alguém na volta',
      () => harness.room.personsAsked == 1,
    );
    await settle(_severalStepsOfTheLadder);

    expect(harness.room.personAsksFor, [primeira, segunda]);
  });

  test('a passage closed after the team left it never erases the Resume point '
      'of a session opened afresh in that passage', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await settle();
    harness.room.finishHeldAskForAPerson();
    await waitFor(
      'a passagem ser marcada fechada',
      () => harness.finished.done.contains('Ruth/P01'),
    );
    harness.room
      ..failTurnsWith = null
      ..askForAPersonFailsWith = null;
    await _sala(container).goConversa(pericope: 'P01', fresh: true);
    await waitFor(
      'a passagem reaberta guardar o seu lugar',
      () => harness.emAberto.written.length > 1,
    );
    final nova = _estado(container).sessionId!;
    await settle(_severalStepsOfTheLadder);

    expect((await harness.emAberto.of('Ruth', 'P01'))?.sessionId, nova);
  });

  test('a passage closed while the team resumes it opens the Choice, never '
      'the closed session', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await settle();
    harness.emAberto.holdNextRead();
    unawaited(_sala(container).goConversa(pericope: 'P01'));
    await settle();

    harness.room.finishHeldAskForAPerson();
    await waitFor(
      'o lugar da sessão fechada sair do tablet',
      () => harness.emAberto.rows['Ruth/P01'] == null,
    );
    harness.room
      ..failTurnsWith = null
      ..askForAPersonFailsWith = null;
    harness.emAberto.finishHeldRead();
    await settle();
    await _naEscolha(container);
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).stage, SalaStage.escolha);
    expect(_estado(container).sessionId, isNull);
    expect(_estado(container).feitas, contains('P01'));
  });

  test('a passage closed while the Choice is reading the finished passages '
      'shows closed on the Wheel', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness);
    harness.room.holdNextAskForAPerson();
    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    _sala(container).leaveThePassage();
    await _naEscolha(container);
    await settle();
    harness.finished.holdNextAll();
    final escolha = _sala(container).abrirEscolha();
    await settle();
    harness.finished.holdNextAdd();

    harness.room.finishHeldAskForAPerson();
    await settle();
    harness.finished.finishHeldAdd();
    await settle();
    harness.finished.finishHeldAll();
    await escolha;
    await settle(_severalStepsOfTheLadder);

    expect(_estado(container).feitas, contains('P01'));
  });

  group('a session the server no longer accepts leaves nothing on the tablet, '
      'and its passage opens afresh from the Wheel', () {
    Future<(ProviderContainer, String)> doisPassos(SalaHarness harness) async {
      final container = await _naPassagem(harness);
      final primeira = _estado(container).sessionId!;
      _sala(container).leaveThePassage();
      await _naEscolha(container);
      await _sala(container).goConversa(pericope: 'P02');
      await waitFor(
        'a outra passagem abrir',
        () =>
            _estado(container).sessionId != null &&
            _estado(container).sessionId != primeira,
      );
      return (container, primeira);
    }

    Future<void> voltaParaAPrimeira(
      SalaHarness harness,
      ProviderContainer container,
      String primeira,
    ) async {
      expect(
        (await harness.emAberto.of('Ruth', 'P01'))?.sessionId,
        isNot(primeira),
      );
      _sala(container).leaveThePassage();
      await _naEscolha(container);
      await settle();
      final criadas = harness.room.calls
          .where((call) => call == 'createSession')
          .length;
      unawaited(_sala(container).goConversa(pericope: 'P01'));
      await waitFor(
        'a primeira passagem abrir de novo',
        () =>
            _estado(container).stage == SalaStage.conversa &&
            _estado(container).sessionId != null,
      );

      expect(_estado(container).sessionId, isNot(primeira));
      expect(
        harness.room.calls.where((call) => call == 'createSession').length,
        criadas + 1,
      );
    }

    test(
      'gone through the Outbox while the room is in another passage',
      () async {
        final harness = SalaHarness();
        final (container, primeira) = await doisPassos(harness);
        final linha = await harness.takes.enqueue(
          harness.recorder.aFile('parte-da-primeira'),
          sessionId: primeira,
          kind: 'ensaio',
          scope: 'parte-1',
          passNumber: 1,
          chunkIndex: 1,
        );
        harness.room.forgetTheSession(primeira);

        await _sala(container).refreshUnsent();
        await waitFor(
          'a linha da primeira sair da Outbox',
          () => !File(linha.path).existsSync(),
        );
        await settle();

        await voltaParaAPrimeira(harness, container, primeira);
      },
    );

    test('gone through the late answer to the call for a person', () async {
      final harness = SalaHarness();
      final container = await _naPassagem(harness);
      final primeira = _estado(container).sessionId!;
      harness.room.holdNextAskForAPerson();
      await _aPassagemFechaNoPedidoDePessoa(harness, container);
      harness.room
        ..failTurnsWith = null
        ..askForAPersonFailsWith = const SessionGone();
      _sala(container).leaveThePassage();
      await _naEscolha(container);
      await _sala(container).goConversa(pericope: 'P02');
      await waitFor(
        'a outra passagem abrir',
        () =>
            _estado(container).sessionId != null &&
            _estado(container).sessionId != primeira,
      );

      harness.room.finishHeldAskForAPerson();
      await settle(_severalStepsOfTheLadder);

      await voltaParaAPrimeira(harness, container, primeira);
    });
  });

  test('a passage closed leaves no Outbox row or file of the session even when '
      'the Resume points cannot be read', () async {
    final casa = Directory.systemTemp.createTempSync('sala-lugar-ilegivel');
    addTearDown(() => casa.deleteSync(recursive: true));
    Directory('${casa.path}/guardadas').createSync(recursive: true);
    File(
      '${casa.path}/guardadas/em_curso.json',
    ).writeAsStringSync('{"Ruth/P01": isto nao e json');
    final harness = SalaHarness(
      emAbertoNoDisco: WorkInProgress(
        home: () async => casa,
        recordings: () async =>
            Directory('${casa.path}/recordings')..createSync(recursive: true),
      ),
    );
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

    await _aPassagemFechaNoPedidoDePessoa(harness, container);
    await _naEscolha(container);
    await settle(_severalStepsOfTheLadder);

    expect(await _daSessao(harness, sessao), isEmpty);
    expect(File(linha.path).existsSync(), isFalse);
    expect(harness.room.calls, isNot(contains('sendTake')));
  });
}
