import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'esperas.dart' show settle, until;
import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;

Future<void> _haltWith(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  Exception failure,
) async {
  harness.room.failWith = failure;
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await until(() => read().needsPerson);
  harness.room.failWith = null;
}

int _sessionsOpened(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'createSession').length;

Future<ProviderContainer> _naPassagem(SalaHarness harness, String pericope) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa(pericope: pericope);
  await settle();
  return container;
}

void main() {
  test('a turn spoken after a person resolves a forgotten session reaches the room',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const SessionGone());
    final turns = harness.room.turnsSent;

    notifier.resolveWithPerson();
    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await until(() => harness.room.turnsSent > turns);

    expect(harness.room.turnsSent, turns + 1,
        reason: 'a pessoa resolveu a parada e a equipe falou um turno inteiro; '
            'sem sessão nenhuma por baixo, o turno era descartado no caminho');
    expect(read().needsPerson, isFalse,
        reason: 'e a sala não volta a parar em cima do turno que acabou de ouvir');
  });

  test('resolving an ordinary halt does not open a second session', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const RoomRefused());
    final opened = _sessionsOpened(harness);

    notifier.resolveWithPerson();
    await settle(const Duration(milliseconds: 300));

    expect(_sessionsOpened(harness), opened,
        reason: 'a parada comum não perdeu a sessão; abrir outra abandonaria a '
            'que a equipe já encheu, e tudo que estava dentro dela');
  });

  test('a resolved halt hands the team the invite to speak', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const SessionGone());

    notifier.resolveWithPerson();
    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.conversaTap();
    await settle();

    expect(read().voice, VoiceState.listening,
        reason: 'o convite não é enfeite: é ele que deixa a equipe começar a '
            'falar depois que a pessoa resolveu a parada');
  });

  test('resolving while the room is still out says so instead of inviting',
      () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().offline, isTrue);
    final turns = harness.room.turnsSent;

    notifier.resolveWithPerson();
    await settle(const Duration(milliseconds: 300));

    expect(read().offline, isTrue,
        reason: 'resolver não põe o servidor de pé; um convite aqui seria o '
            'mesmo círculo respirando sobre nada, com outra causa');

    notifier.conversaTap();
    await settle();

    expect(read().voice, isNot(VoiceState.listening),
        reason: 'e a sala não leva a equipe a falar contra nada: o toque na '
            'tela de queda é uma nova tentativa, não uma gravação');

    harness.room.reachable = true;
    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await until(() => harness.room.turnsSent > turns);

    expect(harness.room.turnsSent, turns + 1,
        reason: 'e quando o servidor volta, a sala volta com sessão e o '
            'primeiro turno da equipe chega');
  });

  test('a turn spoken the instant a halt is resolved is not lost to the wait',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const SessionGone());
    final turns = harness.room.turnsSent;

    notifier.resolveWithPerson();
    notifier.conversaTap();

    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await until(() => harness.room.turnsSent > turns);

    expect(harness.room.turnsSent, turns + 1,
        reason: 'tocar o círculo antes de a sala estar de pé não pode consumir '
            'o turno: a equipe fala uma vez e a sala ouve uma vez');
    expect(read().needsPerson, isFalse);
  });

  test('a passage entered again after a resolved halt lands where they stopped',
      () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness, 'P01');
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const SessionGone());

    notifier.resolveWithPerson();
    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();

    notifier.leaveThePassage();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(read().stage, SalaStage.ensaio,
        reason: 'a parada resolvida reabriu a passagem sem nome, entao nada do '
            'que a equipe gravou depois dela ficou anotado na passagem: voltar '
            'punha a equipe na conversa de novo, com o ensaio perdido');
  });

  test('a passage finished after a resolved halt leaves the wheel', () async {
    final harness = SalaHarness();
    final container = await _naPassagem(harness, 'P01');
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _haltWith(harness, notifier, read, const SessionGone());

    notifier.resolveWithPerson();
    await until(() => read().voice == VoiceState.invite);
    await settle();

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.finished.done, contains('Ruth/P01'),
        reason: 'a equipe terminou a passagem inteira; sem o nome dela por '
            'baixo, a roda continua oferecendo a passagem que acabou de ser '
            'conferida');
  });

  test('the room coming back opens the passage the team was already in',
      () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    expect(read().offline, isTrue);

    harness.network.reachable = true;
    await until(() => read().voice == VoiceState.invite);
    await settle();

    expect(harness.room.pericopesAsked.last, 'P01',
        reason: 'a sala voltou sozinha para dentro da mesma passagem; abrir a '
            'sessao sem pericope nenhum e comecar outra passagem no lugar dela');
  });
}
