import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

/// The room has said its opening line and the circle is waiting for the team.
bool _readyToTalk(ProviderContainer container) {
  final state = container.read(salaSessionProvider);
  return state.stage == SalaStage.conversa && state.voice == VoiceState.invite;
}

void main() {
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
    await waitFor(
      'a roda abrir',
      () => container.read(salaSessionProvider).naRoda != null,
    );
    await notifier.goConversa(pericope: 'P01');
    await waitFor('a passagem lembrada abrir', () => _readyToTalk(container));
    notifier.conversaTap();
    await settle();
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
    await waitFor(
      'a roda abrir',
      () => container.read(salaSessionProvider).naRoda != null,
    );
    await notifier.goConversa(pericope: 'P03');

    await waitFor(
      'a passagem pedida abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.conversa,
    );
    expect(harness.room.pericopesAsked, contains('P03'));
  });
}
