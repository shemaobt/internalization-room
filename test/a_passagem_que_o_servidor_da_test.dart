import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

Future<void> waitFor(
  String what,
  FutureOr<bool> Function() ready, {
  Duration limit = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('esperei ${limit.inSeconds}s e $what não aconteceu');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The app on its first breath: it asks the room for the panorama, as every launch does.
Future<ProviderContainer> _opensAsking(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).openConvite();
  await settle();
  return container;
}

void main() {
  test('a panorama asked for and answered with a passage lands on that passage',
      () async {
    final harness = SalaHarness()..room.panoramaAnsweredWith = 'P02';

    final container = await _opensAsking(harness);

    await waitFor(
      'a equipe chegar à conversa da passagem que a sala devolveu',
      () => container.read(salaSessionProvider).stage == SalaStage.conversa,
    );
    expect(
      harness.room.pericopesAsked,
      contains('P02'),
      reason: 'pedir o panorama é um pedido, não uma ordem: se a sala devolve '
          'uma passagem, é nela que a equipe entra',
    );
    expect(
      container.read(salaSessionProvider).sessionId,
      isNotNull,
      reason: 'e entra com uma sessão, não numa conversa sem sala',
    );
  });

  test('a panorama asked for and answered with a panorama still plays it',
      () async {
    final harness = SalaHarness();

    final container = await _opensAsking(harness);

    // O passo do convite só avança depois de o panorama ter sido dito: é o
    // pouso que diz que ele tocou, e é o que a equipe percebe.
    await waitFor(
      'o panorama ser dito e o convite abrir a entrada',
      () => container.read(salaSessionProvider).conviteStep ==
          ConviteStep.entrada,
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.convite,
        reason: 'todo lançamento de hoje passa por aqui e não pode mudar');
  });

  test('asking for a passage outright still lands on that passage', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await waitFor('a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null);
    await notifier.goConversa(pericope: 'P03');

    await waitFor('a passagem pedida abrir',
        () => container.read(salaSessionProvider).stage == SalaStage.conversa);
    expect(harness.room.pericopesAsked, contains('P03'));
  });
}
