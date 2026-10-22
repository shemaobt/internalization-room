import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

Future<void> _haltWith(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  RoomFailure failure,
) async {
  harness.room.failWith = failure;
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await waitFor('a sala pedir uma pessoa', () => read().needsPerson);
  harness.room.failWith = null;
}

int _sessionsOpened(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'createSession').length;

Future<ProviderContainer> _naPassagem(
  SalaHarness harness,
  String pericope,
) async {
  final container = harness.container();
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(book: 'Ruth', pericope: pericope);
  await settle();
  return container;
}

void main() {
  test('a halt with no session stops the room and calls nobody', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await settle();

    expect(
      container.read(salaSessionProvider).needsPerson,
      isTrue,
      reason:
          'parar é sempre local e não depende de sessão nenhuma: uma '
          'sala que não consegue nem abrir uma sessão é justamente a que '
          'precisa mostrar que parou',
    );
    expect(
      harness.room.personsAsked,
      0,
      reason:
          'mas o chamado só é feito quando há sessão sobre a qual '
          'fazê-lo, e é disto que dependem os pontos onde o pedido de '
          'pessoa é feito depois de um await sem checar se a equipe ainda '
          'está na passagem — sair dela esvazia a sessão, e é isto que '
          'impede um facilitador de ser mandado atrás dela',
    );
  });

  test('a turn spoken after the team taps the sign reaches the room', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const Refused('UNAUTHORIZED'));
    final turns = harness.room.turnsSent;

    notifier.teamTapped();
    await waitFor(
      'o círculo voltar ao convite',
      () => !read().needsPerson && read().voice == VoiceState.invite,
    );
    await settle();

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor(
      'mais um turno chegar à sala',
      () => harness.room.turnsSent > turns,
    );

    expect(
      harness.room.turnsSent,
      turns + 1,
      reason:
          'a equipe tocou o sinal e falou um turno inteiro; '
          'a sessão continua de pé por baixo da parada e o turno chega a ela',
    );
    expect(
      read().needsPerson,
      isFalse,
      reason: 'e a sala não volta a parar em cima do turno que acabou de ouvir',
    );
  });

  test('a tap on the sign does not open a second session', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const Refused('UNAUTHORIZED'));
    final opened = _sessionsOpened(harness);

    notifier.teamTapped();
    await settle(const Duration(milliseconds: 300));

    expect(
      _sessionsOpened(harness),
      opened,
      reason:
          'a parada comum não perdeu a sessão; abrir outra abandonaria a '
          'que a equipe já encheu, e tudo que estava dentro dela',
    );
  });

  test('a tapped sign hands the team the invite to speak', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const Refused('UNAUTHORIZED'));

    notifier.teamTapped();
    await waitFor(
      'o círculo voltar ao convite',
      () => !read().needsPerson && read().voice == VoiceState.invite,
    );
    await settle();

    notifier.conversaTap();
    await settle();

    expect(
      read().voice,
      VoiceState.listening,
      reason:
          'o convite não é enfeite: é ele que deixa a equipe começar a '
          'falar depois que tocou o sinal',
    );
  });

  test(
    'a turn spoken the instant the sign is tapped is not lost to the wait',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await _haltWith(harness, notifier, read, const Refused('UNAUTHORIZED'));
      final turns = harness.room.turnsSent;

      notifier.teamTapped();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'mais um turno chegar à sala',
        () => harness.room.turnsSent > turns,
      );

      expect(
        harness.room.turnsSent,
        turns + 1,
        reason:
            'tocar o círculo no instante em que o sinal sai começa a '
            'gravar em vez de ser engolido pela espera',
      );
      expect(read().needsPerson, isFalse);
    },
  );

  test(
    'a passage entered again after a tapped sign lands where they stopped',
    () async {
      final harness = SalaHarness();
      final container = await _naPassagem(harness, 'P01');
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await _haltWith(harness, notifier, read, const Refused('UNAUTHORIZED'));

      notifier.teamTapped();
      await waitFor(
        'o círculo voltar ao convite',
        () => !read().needsPerson && read().voice == VoiceState.invite,
      );
      await settle();

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await settle();
      notifier.takeKeep();
      await settle();

      notifier.leaveThePassage();
      await settle();
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await settle();

      expect(
        read().stage,
        SalaStage.ensaio,
        reason:
            'o sinal tocado reabria a passagem sem nome, entao nada do '
            'que a equipe gravou depois dela ficou anotado na passagem: voltar '
            'punha a equipe na conversa de novo, com o ensaio perdido',
      );
    },
  );

  test(
    'a tap after the room answers opens the passage the team was already in',
    () async {
      final harness = SalaHarness()..room.reachable = false;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await settle();
      expect(read().sessionId, isNull);
      expect(read().voice, VoiceState.invite);

      notifier.conversaTap();
      await settle();
      expect(
        read().voice,
        isNot(VoiceState.listening),
        reason:
            'o toque sem sessão é uma nova tentativa, não uma gravação contra '
            'nada',
      );

      harness.room.reachable = true;
      notifier.conversaTap();
      await waitFor('a sessão abrir', () => read().sessionId != null);

      expect(
        harness.room.pericopesAsked.last,
        'P01',
        reason:
            'a sala voltou para dentro da mesma passagem; abrir a '
            'sessao sem pericope nenhum e comecar outra passagem no lugar dela',
      );
    },
  );
}
