import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

int _createdSessions(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'createSession').length;

/// A whole turn, from the team touching the circle to the room hearing it.
Future<void> _aTurn(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await settle();
}

/// A spoken turn the room refuses: the person sign, and the call that tells the server.
Future<void> _aTurnTheRoomRefuses(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  harness.room.failTurnsWith = const Refused('BAD_REQUEST');
  await _aTurn(notifier);
  await waitFor('a sala parar', () => read().needsPerson);
  await waitFor('o pedido chegar à mesa', () => harness.room.personsAsked > 0);
  harness.room.failTurnsWith = null;
}

void main() {
  test('a warning from the server never stops the room', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala reler o estado', () => stateReads(harness) > 0);
    await settle(const Duration(milliseconds: 300));
    final turns = harness.room.turnsSent;

    expect(read().needsPerson, isFalse);
    expect(
      read().voice,
      VoiceState.invite,
      reason: 'o aviso chama uma pessoa para olhar; nada é recusado à equipe',
    );

    await _aTurn(notifier);
    await waitFor(
      'o turno chegar à sala',
      () => harness.room.turnsSent > turns,
    );
  });

  test(
    'a tap on a room that never opened asks again and reads no state',
    () async {
      final harness = SalaHarness()..room.reachable = false;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      expect(read().voice, VoiceState.invite);
      final asked = stateReads(harness);
      final opened = _createdSessions(harness);

      notifier.conversaTap();
      await waitFor(
        'a sala tentar de novo',
        () => _createdSessions(harness) > opened,
      );

      expect(
        stateReads(harness),
        asked,
        reason:
            'a queda não é uma parada: perguntar o estado de uma sessão que '
            'não existe gastaria o toque na rota errada',
      );
    },
  );

  test('the watch outlives the tap and ends with the room', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _aTurnTheRoomRefuses(harness, notifier, read);
    notifier.teamTapped();
    await waitFor('a sala soltar', () => !read().needsPerson);

    final afterRelease = stateReads(harness);
    await waitFor(
      'a vigia seguir lendo a sessão solta',
      () => stateReads(harness) > afterRelease + 1,
    );

    final beforeDispose = stateReads(harness);
    container.dispose();
    await settle(const Duration(milliseconds: 400));

    expect(
      stateReads(harness),
      beforeDispose,
      reason:
          'a sala fechada não vigia nada: o tablet guardado seguiria '
          'perguntando por uma sessão que ninguém está olhando',
    );
  });
}
