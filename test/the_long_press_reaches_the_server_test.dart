import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

int _calls(SalaHarness harness, String name) =>
    harness.room.calls.where((call) => call == name).length;

/// A whole turn, from the team touching the circle to the room hearing it.
Future<void> _aTurn(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await settle();
}

void main() {
  test('the long press on a confirmed blocking halt tells the room a person '
      'arrived, once per press', () async {
    // A cadence far longer than any answer the fake gives, so that what the touch does
    // is measured by the touch and not by the next beat of the watch arriving under it.
    final harness = SalaHarness(settleDelay: const Duration(seconds: 5))
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    final sessionId = read().sessionId!;
    final asked = _calls(harness, 'fetchState');

    notifier.resolveWithPerson();
    await waitFor(
      'o servidor saber que alguém chegou',
      () => harness.room.personArrivedSessions.isNotEmpty,
    );

    expect(
      harness.room.personArrivedSessions,
      [sessionId],
      reason: 'o toque avisa o servidor pela sessão que a mesa vigia',
    );
    await waitFor(
      'a sala reler o estado na hora',
      () => _calls(harness, 'fetchState') > asked,
    );
    expect(
      read().needsPerson,
      isTrue,
      reason: 'o servidor ainda segura a parada; o aviso não a solta sozinho',
    );

    notifier.resolveWithPerson();
    await waitFor(
      'um segundo aviso chegar ao servidor',
      () => harness.room.personArrivedSessions.length == 2,
    );

    expect(
      harness.room.personArrivedSessions,
      [sessionId, sessionId],
      reason:
          'a mesa guarda o primeiro aviso; um segundo toque manda outro, '
          'não o mesmo de novo',
    );
  });

  test('a failed person-arrived changes nothing: the re-read still happens '
      'and nothing is retried', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 5))
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking
      ..room.personArrivedFailsWith = const RoomRefused();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    final asked = _calls(harness, 'fetchState');

    notifier.resolveWithPerson();
    await waitFor(
      'a tentativa de avisar o servidor',
      () => _calls(harness, 'personArrived') == 1,
    );
    await waitFor(
      'a sala reler o estado mesmo com o aviso recusado',
      () => _calls(harness, 'fetchState') > asked,
    );

    expect(
      read().needsPerson,
      isTrue,
      reason: 'a sala continua parada; o servidor é quem solta, não o aviso',
    );

    await settle(const Duration(milliseconds: 300));
    expect(
      _calls(harness, 'personArrived'),
      1,
      reason:
          'uma tentativa só por toque; uma recusa não vira reforço atrás '
          'da mesma parada',
    );
  });

  test(
    'a halt with no session never tells the server a person arrived',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.room.failWith = const SessionGone();
      await _aTurn(notifier);
      await waitFor('a sala parar sem sessão', () => read().needsPerson);
      harness.room.failWith = null;
      expect(read().sessionId, isNull);

      notifier.resolveWithPerson();
      await waitFor(
        'o círculo voltar ao convite',
        () => read().voice == VoiceState.invite,
      );

      expect(
        harness.room.personArrivedSessions,
        isEmpty,
        reason:
            'sem sessão não há id para o servidor guardar contra o próximo '
            'toque',
      );
    },
  );

  test('a long press on a room that is out never tells the server a person '
      'arrived', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().offline, isTrue);
    final opened = _calls(harness, 'createSession');

    notifier.resolveWithPerson();
    await waitFor(
      'a sala tentar de novo',
      () => _calls(harness, 'createSession') > opened,
    );

    expect(
      harness.room.personArrivedSessions,
      isEmpty,
      reason:
          'a queda não é uma parada confirmada; o toque tenta abrir de '
          'novo, não avisar uma mesa que nunca soube da sessão',
    );
  });

  test('a long press on an unconfirmed halt never tells the server a person '
      'arrived', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 5))
      ..voice.succeeds = false
      ..room.holdNextAskForAPerson();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor(
      'a sala parar com o pedido pela sessão em voo',
      () => read().needsPerson,
    );

    notifier.resolveWithPerson();
    await waitFor(
      'o círculo voltar ao convite',
      () => read().voice == VoiceState.invite,
    );

    expect(
      harness.room.personArrivedSessions,
      isEmpty,
      reason:
          'a sala decidiu esta parada sozinha (três turnos sem áudio '
          'próprio), então o pedido ainda existe para ser seguro em voo — '
          'uma parada apenas lida (ENG-962) é vigiada na hora e não tem '
          'mais essa janela sem confirmação; sem vigia, o toque solta '
          'localmente e não há pedido a fazer',
    );

    harness.room.finishHeldAskForAPerson();
  });
}
