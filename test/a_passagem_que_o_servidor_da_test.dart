import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

/// The app on its first breath: it asks the room for the panorama, as every launch does.
Future<ProviderContainer> _opensAsking(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).openConvite();
  await settle();
  return container;
}

/// The room has said its opening line and the circle is waiting for the team.
bool _readyToTalk(ProviderContainer container) {
  final state = container.read(salaSessionProvider);
  return state.stage == SalaStage.conversa && state.voice == VoiceState.invite;
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
    await waitFor(
      'o lugar da equipe ser anotado',
      () => harness.emAberto.rows.containsKey('Ruth/P02'),
    );
    expect(
      harness.emAberto.rows['Ruth/P02']!.sessionId,
      harness.room.sessionIds.single,
      reason: 'pedir o panorama é um pedido, não uma ordem: se a sala devolve '
          'uma passagem, é nela que a equipe entra, na sessão que a sala abriu',
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
    expect(harness.room.sessionIds, hasLength(1),
        reason: 'um lançamento pede um panorama e recebe uma sessão');
    expect(
      harness.room.sessionsSpokenTo,
      [harness.room.sessionIds.single],
      reason: 'e o panorama é dito na única sessão que a sala abriu',
    );
  });

  test('a launch answered with a passage is one session, and the team talks in it',
      () async {
    final harness = SalaHarness()..room.panoramaAnsweredWith = 'P02';

    final container = await _opensAsking(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await waitFor(
      'a sala abrir a conversa da passagem que devolveu',
      () => _readyToTalk(container),
    );
    notifier.conversaTap();
    notifier.conversaTap();
    await waitFor(
      'a fala da equipe chegar à sala',
      () => harness.room.turnsSent == 1,
    );

    expect(
      harness.room.sessionIds,
      hasLength(1),
      reason: 'a sala já abriu uma sessão para a passagem que devolveu: abrir '
          'outra deixa a primeira abandonada, uma linha fantasma por lançamento',
    );
    final given = harness.room.sessionIds.single;
    expect(
      harness.room.sessionsSpokenTo,
      [given, given],
      reason: 'a abertura e a fala da equipe vão para a sessão que a sala deu',
    );
  });

  test('a launch answered with a passage marks the book as opened', () async {
    final harness = SalaHarness()..room.panoramaAnsweredWith = 'P02';
    final first = harness.container();
    addTearDown(first.dispose);
    await first.read(salaSessionProvider.notifier).openTheRoom();
    await first.read(salaSessionProvider.notifier).openConvite();
    await waitFor(
      'a sala abrir a conversa da passagem que devolveu',
      () => _readyToTalk(first),
    );
    await waitFor(
      'o lugar da equipe ser anotado',
      () => harness.emAberto.rows.containsKey('Ruth/P02'),
    );
    final given = harness.room.sessionIds.single;

    // The team's first gesture on every launch is the tap on the circle. On a tablet
    // that has heard the panorama it lands on the wheel, where it asks for nothing.
    final second = harness.container();
    addTearDown(second.dispose);
    final again = second.read(salaSessionProvider.notifier);
    await again.openTheRoom();
    await settle();
    await again.openConvite();
    await settle();

    expect(
      harness.room.pericopesAsked,
      [panoramaPericope],
      reason: 'a sala responder uma passagem é a prova de que o panorama foi '
          'ouvido: pedi-lo de novo a cada lançamento cunha uma sessão nova a '
          'cada vez e recomeça a cobertura do zero',
    );
    expect(second.read(salaSessionProvider).stage, SalaStage.escolha,
        reason: 'o segundo lançamento vai direto às passagens');

    await again.goConversa(pericope: 'P02');
    await waitFor('a passagem retomada abrir', () => _readyToTalk(second));
    again.conversaTap();
    again.conversaTap();
    await waitFor(
      'a fala da equipe chegar à sala',
      () => harness.room.turnsSent == 1,
    );

    expect(harness.room.sessionIds, [given],
        reason: 'o segundo lançamento retoma a sessão que a sala deu no primeiro');
    expect(
      harness.room.sessionsSpokenTo,
      [given, given, given],
      reason: 'a abertura do primeiro lançamento, a abertura do segundo e a '
          'fala da equipe vão todas para essa sessão',
    );
  });

  test('a remembered place is resumed into the remembered session', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
      sessionId: 'sessao-lembrada',
      stage: SalaStage.conversa,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await waitFor('a roda abrir',
        () => container.read(salaSessionProvider).naRoda != null);
    await notifier.goConversa(pericope: 'P01');
    await waitFor('a passagem lembrada abrir', () => _readyToTalk(container));
    notifier.conversaTap();
    notifier.conversaTap();
    await waitFor(
      'a fala da equipe chegar à sala',
      () => harness.room.turnsSent == 1,
    );

    expect(
      harness.room.sessionIds,
      isEmpty,
      reason: 'a sessão desta passagem já existe; a sala não abre outra',
    );
    expect(
      harness.room.sessionsSpokenTo,
      ['sessao-lembrada', 'sessao-lembrada'],
      reason: 'a abertura e a fala da equipe voltam para a sessão lembrada',
    );
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
