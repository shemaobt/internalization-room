import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

const _ladder = [Duration(milliseconds: 30)];

/// A passage opened with the server away: the way in rests at the invite.
Future<ProviderContainer> _aWayInThatFailed(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  harness.room.reachable = false;
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await waitFor(
    'a passagem descansar no convite',
    () => !container.read(salaSessionProvider).awaitingTheGuide,
  );
  return container;
}

Future<void> _recordATake(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  await waitFor(
    'a gravação ser enfileirada',
    () async => (await harness.takes.entries()).isNotEmpty,
  );
  expect(
    await harness.takes.pending(),
    isNotEmpty,
    reason: 'a gravação feita com a sala fora do ar espera na Outbox',
  );
}

Future<void> _theServerIsBackAndTheTeamTaps(
  SalaHarness harness,
  ProviderContainer container,
) async {
  SalaSessionState read() => container.read(salaSessionProvider);
  await waitFor(
    'a gravação dizer que falhou',
    () => read().unsentParts.values.any((part) => part.failure != null),
  );
  harness.room.reachable = true;
  container
      .read(salaSessionProvider.notifier)
      .enviarACena(read().unsentParts.keys.single);
}

Future<void> _theOutboxEmpties(SalaHarness harness) => waitFor(
  'a Outbox esvaziar',
  () async => (await harness.takes.pending()).isEmpty,
);

void main() {
  test(
    'T1: after a failed way in, the Rehearsal records and the Outbox empties by '
    'its own retry once the server is back',
    () async {
      final harness = SalaHarness(
        watchesWithoutAHalt: true,
        retryBackoff: _ladder,
      );
      final container = await _aWayInThatFailed(harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);

      harness.room.reachable = true;
      await _theOutboxEmpties(harness);
    },
  );

  test("T11: after the team's tap on a sign raised while a way in failed, the "
      "room rests and the Outbox empties on the team's tap once the server is "
      'back', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      retryBackoff: _ladder,
    );
    final container = await _aWayInThatFailed(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    await _recordATake(harness, notifier);
    notifier.haltForABrokenBuild();
    await waitFor('o sinal subir', () => read().needsPerson);

    notifier.teamTapped();
    await settle();
    expect(read().needsPerson, isFalse);
    expect(read().voice, VoiceState.invite);

    await _theServerIsBackAndTheTeamTaps(harness, container);
    await _theOutboxEmpties(harness);
  });
}
