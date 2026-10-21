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
  test('the desk lifting the halt gives the room back without a touch', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _aTurnTheRoomRefuses(harness, notifier, read);
    final asked = stateReads(harness);
    final turns = harness.room.turnsSent;

    // The facilitator marked the session attended on the desk; nobody touched the tablet.
    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

    expect(
      stateReads(harness),
      greaterThan(asked),
      reason:
          'a parada bloqueante é vigiada: sem reler o estado a sala nunca '
          'saberia que a mesa a levantou, e a equipe ficaria parada na frente '
          'de uma sessão que o servidor já deu por atendida',
    );

    await _aTurn(notifier);
    await waitFor(
      'mais um turno chegar à sala',
      () => harness.room.turnsSent > turns,
    );

    expect(
      harness.room.turnsSent,
      turns + 1,
      reason:
          'e a sala solta de verdade: o convite sem turno seria um círculo '
          'respirando sobre uma sala ainda fechada',
    );
  });

  test(
    'the long press on a blocking halt asks the room now and releases nothing',
    () async {
      // A cadence far longer than any answer the fake gives, so that what the touch does
      // is measured by the touch and not by the next beat of the watch arriving under it.
      final harness = SalaHarness(settleDelay: const Duration(seconds: 5));
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await _aTurnTheRoomRefuses(harness, notifier, read);
      final asked = stateReads(harness);

      notifier.resolveWithPerson();
      await waitFor(
        'a sala perguntar ao servidor na hora',
        () => stateReads(harness) > asked,
        limit: const Duration(milliseconds: 2000),
      );

      expect(
        read().needsPerson,
        isTrue,
        reason:
            'o servidor ainda segura a parada; soltar no toque punha a '
            'equipe de volta a falar dentro de uma sala que a mesa não atendeu',
      );

      harness.room.theDeskAttended();

      notifier.resolveWithPerson();
      await waitFor(
        'o toque devolver a sala na hora',
        () => !read().needsPerson,
        limit: const Duration(milliseconds: 3000),
      );

      expect(
        read().needsPerson,
        isFalse,
        reason:
            'quem acabou de atender na mesa não espera a próxima batida da '
            'vigia: o toque longo é o pedido de agora',
      );
    },
  );

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

  test("the room's own halt is lifted by the server too", () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 2))
      ..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar por conta própria', () => read().needsPerson);

    // The desk sees the same halt the tablet raised, and has not attended it yet.
    harness.room.serverStatus = 'needs_person';
    harness.room.serverHalt = HaltKind.blocking;
    final asked = stateReads(harness);
    await waitFor('a vigia reler o estado', () => stateReads(harness) > asked);

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a parada que o tablet levantou também espera a mesa: soltá-la '
          'sozinha devolveria a sala sem que ninguém tivesse olhado',
    );

    harness.voice.succeeds = true;
    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);
    expect(read().needsPerson, isFalse);
  });

  test('the long press on a room that is out is unchanged', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().offline, isTrue);
    final asked = stateReads(harness);
    final opened = _createdSessions(harness);

    notifier.resolveWithPerson();
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
    expect(
      read().offline,
      isTrue,
      reason:
          'e o servidor continua fora; um convite aqui seria o mesmo '
          'círculo respirando sobre nada',
    );
  });

  test('the watch outlives the lift and ends with the room', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _aTurnTheRoomRefuses(harness, notifier, read);
    harness.room.theDeskAttended();
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

  test('leaving the passage takes the watch with it', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor(
      'a sala parar na primeira passagem',
      () => read().needsPerson,
    );
    await waitFor('a sala vigiar a parada', () => stateReads(harness) > 0);

    // The team walks out of the passage they were held in, which is what that gesture is
    // for, and the desk attends the session they left behind.
    notifier.leaveThePassage();
    await settle();
    harness.room.theDeskAttended();

    // In the new passage the call for a person never lands, so nobody was told and there
    // is nothing to watch.
    harness.room.askForAPersonFailsWith = const Refused('UNAUTHORIZED');
    await notifier.goConversa(book: 'Ruth', pericope: 'P02');
    await settle();
    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar na segunda passagem', () => read().needsPerson);

    harness.voice.succeeds = true;
    final asked = stateReads(harness);
    notifier.resolveWithPerson();
    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

    expect(
      stateReads(harness),
      asked,
      reason:
          'a vigia da passagem anterior tinha de sair com ela: mantida, o '
          'toque nesta parada pergunta por uma sessão que não é desta sala — '
          'e a resposta que soltar a equipe será sobre o trabalho de outra',
    );
  });
}
