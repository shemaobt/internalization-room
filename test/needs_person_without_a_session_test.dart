import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle;

/// A real ledger on a temp dir, the way `device_credential_test.dart` builds one — not
/// the in-memory `FakeLinkedTeam` the harness wires by default, since the notifier reads
/// the ledger itself now and a fake that answers from memory would prove nothing about
/// the read.
LinkedTeam _ledgerOnDisk() {
  final home = Directory.systemTemp.createTempSync('sala-sem-sessao');
  addTearDown(() => home.deleteSync(recursive: true));
  return LinkedTeam(home: () async => home);
}

ProviderContainer _tablet(SalaHarness harness, LinkedTeam ledger) =>
    ProviderContainer(
      overrides: [
        ...harness.overrides,
        linkedTeamProvider.overrideWithValue(ledger),
      ],
    );

Future<ProviderContainer> _inConversa(SalaHarness harness, LinkedTeam ledger) async {
  final container = _tablet(harness, ledger);
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}

void main() {
  test('case 1: a sessão some e a sala ainda pede uma pessoa, pelo aparelho', () async {
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness();
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);

    harness.room.failWith = const SessionGone();
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.sessionId, isNull,
        reason: 'a arquitetura conta com a sessão já limpa antes do pedido');
    expect(state.needsPerson, isTrue);
    expect(harness.room.deviceAsksReceived, ['aparelho-D']);
    expect(harness.room.calls, isNot(contains('askForAPerson')),
        reason: 'a sessão sumiu; pedir pela sessão de novo é pedir por um id que a '
            'sala já disse não ter mais');
  });

  test(
      'case 2 (Emenda 1, trava de regressão): um build quebrado para na tela '
      'e não pede a ninguém', () async {
    // Emenda 1: o "Question" do plano supunha uma falha comum; Env.roomKey /
    // Env.backendUrl lançam StateError, um Error que nenhum catch entre o
    // repositório e a tela pega — ler build quebrado como se tivesse uma
    // sessão nula era o que mantinha esse caminho fora da rede, sem ninguém
    // ter documentado assim. haltForABrokenBuild() passa a ser o próprio
    // sinal de que não há servidor a alcançar: ele para sem perguntar.
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness();
    final container = _tablet(harness, ledger);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue,
        reason: 'a parada fica na tela mesmo sem nenhum pedido sair');
    expect(harness.room.deviceAsksReceived, isEmpty,
        reason: 'o aparelho tem id no vínculo; se a lista não está vazia, o '
            'pedido saiu de verdade — e um build quebrado não tem para onde '
            'esse pedido ir');
    expect(harness.room.calls, isEmpty,
        reason: 'nem a rota por sessão nem qualquer outra chamada devem sair '
            'daqui — a única coisa que este builder sabe é que está quebrado');
  });

  test(
      'case 3 (trava de regressão): uma sessão viva pede pela sessão, nunca pelo '
      'aparelho', () async {
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(harness.room.personsAsked, 1);
    expect(harness.room.deviceAsksReceived, isEmpty,
        reason: 'sessão viva nunca é motivo para perguntar pelo aparelho');
  });

  test(
      'case 4a: falhas de rede insistem com o backoff, e param assim que uma chega',
      () async {
    // Emenda 1 tirou haltForABrokenBuild() como gatilho do pedido por aparelho;
    // a sessão perdida (SessionGone) é quem aciona esse caminho agora.
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness(retryBackoff: const [Duration(milliseconds: 20)]);
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);

    harness.room.deviceAskFailures.addAll([
      const RoomUnavailable('sem rede'),
      const RoomUnavailable('sem rede'),
    ]);
    harness.room.failWith = const SessionGone();
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    notifier.conversaTap();
    await waitFor(
      'as três tentativas do pedido pelo aparelho',
      () => harness.room.deviceAsksReceived.length == 3,
    );
    await settle(const Duration(milliseconds: 200));

    expect(harness.room.deviceAsksReceived, [
      'aparelho-D',
      'aparelho-D',
      'aparelho-D',
    ], reason: 'duas falhas e um sucesso são três tentativas, e nem uma a mais depois');
  });

  test('case 4b: um 409 (ninguém a quem chegar) é final, sem novas tentativas',
      () async {
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness(retryBackoff: const [Duration(milliseconds: 20)]);
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);

    harness.room.deviceAskFailures.add(const NobodyToReach());
    harness.room.failWith = const SessionGone();
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();
    await settle(const Duration(milliseconds: 200));

    expect(harness.room.deviceAsksReceived, ['aparelho-D'],
        reason: 'perguntar de novo não muda que não há equipe para o aparelho');
  });

  test('case 5: sem id de aparelho no vínculo, nenhum pedido sai', () async {
    // haltForABrokenBuild() nunca pede ninguém desde a Emenda 1 (caso 2); o
    // caminho que ainda cai no aparelho sem id é a sessão que se perde.
    final ledger = _ledgerOnDisk();
    final harness = SalaHarness();
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);

    harness.room.failWith = const SessionGone();
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue,
        reason: 'a parada fica na tela mesmo sem ninguém para avisar');
    expect(state.sessionId, isNull);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personsAsked, 0);
  });

  test(
      'case 7 (Emenda 2): um 404 no pedido pela sessão limpa a sessão e vira '
      'um pedido pelo aparelho', () async {
    // Emenda 2: SessionGone é uma Exception como outra qualquer para o catch
    // genérico de _askForAPerson, então o backoff insistia pela mesma sessão
    // que a sala já disse não ter mais — nada limpava state.sessionId, e o
    // pedido pelo aparelho nunca tinha vez.
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness(retryBackoff: const [Duration(milliseconds: 20)])
      ..voice.succeeds = false;
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);

    harness.room.askForAPersonFailsWith = const SessionGone();
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue);
    expect(state.sessionId, isNull,
        reason: 'a sala respondeu que não tem mais essa sessão');
    expect(harness.room.deviceAsksReceived, ['aparelho-D']);
    expect(harness.room.calls.where((call) => call == 'askForAPerson').length, 1,
        reason: 'reinsistir pela mesma sessão é pedir por um id que a sala já '
            'disse não ter mais');

    await settle(const Duration(milliseconds: 200));
    expect(harness.room.calls.where((call) => call == 'askForAPerson').length, 1,
        reason: 'nenhuma nova tentativa pela sessão depois do backoff');
  });

  test(
      'case 8 (Emenda 3): um 404 tardio na sessão não repara a sala depois '
      'que a pessoa já chegou', () async {
    // Emenda 3: o ramo SessionGone do caso 7 re-parava a sala mesmo quando
    // resolveWithPerson() já tinha voltado o estado para invite — o pedido
    // pela sessão seguia em voo, sem como ser cancelado, e a resposta tardia
    // reabria a parada e replicava a linha de precisa-de-pessoa.
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness(retryBackoff: const [Duration(milliseconds: 20)])
      ..voice.succeeds = false;
    final container = await _inConversa(harness, ledger);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);

    harness.room.holdNextAskForAPerson();
    notifier.conversaTap();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a parada chegou; o pedido pela sessão está em voo, seguro');
    final playedBeforeResolve = harness.voice.assets.length;

    notifier.resolveWithPerson();
    await settle();
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'a pessoa chegou e apertou — a sala volta para invite');

    harness.room.askForAPersonFailsWith = const SessionGone();
    harness.room.finishHeldAskForAPerson();
    await settle();
    await settle(const Duration(milliseconds: 200));

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isFalse,
        reason: 'a resposta tardia não pode reabrir uma parada que já foi resolvida');
    expect(state.sessionId, isNotNull,
        reason: 'nada limpa uma sessão depois que a pessoa já chegou por ela');
    expect(harness.room.deviceAsksReceived, isEmpty,
        reason: 'sem parada, não há por que pedir a ninguém');
    expect(harness.voice.assets.length, playedBeforeResolve,
        reason: 'a linha de precisa-de-pessoa não pode tocar uma segunda vez para '
            'uma parada que a equipe já resolveu');
  });

  group('askForAPersonWithoutASession (repositório)', () {
    setUpAll(() {
      dotenv.testLoad(
        fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
      );
    });

    test('case 6: o pedido que sai, com a credencial e a chave da sala', () async {
      late http.BaseRequest seen;
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen = request;
          return http.Response('{}', 200);
        }),
      )..presents('credencial-1');
      addTearDown(repository.dispose);

      await repository.askForAPersonWithoutASession('aparelho-D');

      expect(seen.method, 'POST');
      expect(
        seen.url.path,
        '/api/internalization-room/devices/aparelho-D/needs-person',
      );
      expect(seen.headers['X-Room-Key'], 'k');
      expect(seen.headers['X-Device-Credential'], 'credencial-1');
    });

    test('404 e 409 são o mesmo final: não há equipe para este aparelho', () async {
      Future<void> expectStatus(int status) async {
        final repository = RoomRepository(
          client: MockClient((_) async => http.Response('{}', status)),
        );
        addTearDown(repository.dispose);
        await expectLater(
          () => repository.askForAPersonWithoutASession('aparelho-D'),
          throwsA(isA<NobodyToReach>()),
        );
      }

      await expectStatus(404);
      await expectStatus(409);
    });

    test('um 500 é a falha comum, que insiste — não a falta de equipe', () async {
      final repository = RoomRepository(
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      addTearDown(repository.dispose);

      await expectLater(
        () => repository.askForAPersonWithoutASession('aparelho-D'),
        throwsA(isA<RoomBroke>()),
      );
    });
  });
}
