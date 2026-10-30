import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'support/temp.dart';

/// A real ledger on a temp dir, the way `device_credential_test.dart` builds one — not
/// the in-memory `FakeLinkedTeam` the harness wires by default, since the notifier reads
/// the ledger itself now and a fake that answers from memory would prove nothing about
/// the read.
LinkedTeam _ledgerOnDisk() {
  final home = aTempDir('sala-sem-sessao');
  return LinkedTeam(home: () async => home);
}

ProviderContainer _tablet(SalaHarness harness, LinkedTeam ledger) =>
    ProviderContainer(
      overrides: [
        ...harness.overrides,
        linkedTeamProvider.overrideWithValue(ledger),
      ],
    );

Future<ProviderContainer> _inConversa(
  SalaHarness harness,
  LinkedTeam ledger,
) async {
  final container = _tablet(harness, ledger);
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await settle();
  return container;
}

void main() {
  test('case 2 (Emenda 1, trava de regressão): um build quebrado para na tela '
      'e não pede a ninguém', () async {
    // Emenda 1: o "Question" do plano supunha uma falha comum;
    // Env.backendUrl lança StateError, um Error que nenhum catch entre o
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
    expect(
      state.needsPerson,
      isTrue,
      reason: 'a parada fica na tela mesmo sem nenhum pedido sair',
    );
    expect(
      harness.room.calls,
      isEmpty,
      reason:
          'nem a rota por sessão nem qualquer outra chamada devem sair '
          'daqui — a única coisa que este builder sabe é que está quebrado',
    );
  });

  test(
    'case 3 (trava de regressão): uma sessão viva pede pela sessão, nunca pelo '
    'aparelho',
    () async {
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
    },
  );

  test('case 8 (Emenda 3): um 404 tardio na sessão não repara a sala depois '
      'que a pessoa já chegou, e leva à Escolha', () async {
    final ledger = _ledgerOnDisk();
    await ledger.rememberDevice('aparelho-D');
    final harness = SalaHarness(
      retryBackoff: const [Duration(milliseconds: 20)],
    )..voice.succeeds = false;
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
    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason: 'a parada chegou; o pedido pela sessão está em voo, seguro',
    );
    final playedBeforeResolve = harness.voice.assets.length;
    final fixedBeforeResolve = harness.voice.fixedLines.length;

    notifier.teamTapped();
    await settle();
    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'a pessoa chegou e apertou — a sala volta para invite',
    );

    harness.room.askForAPersonFailsWith = const SessionGone();
    harness.room.finishHeldAskForAPerson();
    await settle();
    await settle(const Duration(milliseconds: 200));

    final state = container.read(salaSessionProvider);
    expect(
      state.needsPerson,
      isFalse,
      reason:
          'a resposta tardia não pode reabrir uma parada que já foi resolvida',
    );
    expect(
      state.stage,
      SalaStage.escolha,
      reason: 'a sessão sumiu; o destino é um só, a Escolha',
    );
    expect(
      harness.voice.assets.length,
      playedBeforeResolve,
      reason:
          'a linha de precisa-de-pessoa não pode tocar uma segunda vez para '
          'uma parada que a equipe já resolveu',
    );
    expect(harness.voice.fixedLines.length, fixedBeforeResolve);
  });
}
