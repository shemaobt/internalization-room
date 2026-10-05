import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

const _ladder = [Duration(milliseconds: 30)];
const _aLadderThatFallsAsleep = [
  Duration(milliseconds: 20),
  Duration(hours: 1),
];

Future<ProviderContainer> _fallenInConversa(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  await _theRoomFalls(harness, container);
  return container;
}

Future<void> _theRoomFalls(
  SalaHarness harness,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.network.reachable = false;
  harness.room.reachable = false;
  harness.inbox.refuses = true;
  notifier.handTap();
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await waitFor(
    'a sala cair no meio da conversa',
    () => container.read(salaSessionProvider).offline,
  );
}

Future<ProviderContainer> _fallenInEnsaio(SalaHarness harness) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1061').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  harness.room.reachable = false;
  await notifier.goConversa(pericope: 'P01');
  harness.network.reachable = false;
  await waitFor(
    'a sala cair offline no ensaio',
    () => container.read(salaSessionProvider).offline,
  );
  return container;
}

Future<void> _recordATake(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.ensaioTap();
  notifier.ensaioTap();
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

Future<void> _haltOnTheRecorder(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  harness.recorder.startThrows = true;
  notifier.ensaioTap();
  await settle();
  notifier.ensaioTap();
  await waitFor('o tablet parar pedindo uma pessoa', () => read().needsPerson);
}

Future<void> _theLadderClimbs(SalaHarness harness, String when) async {
  final before = harness.network.checks;
  await waitFor(
    'a escada seguir tentando $when',
    () => harness.network.checks > before,
  );
}

void _theServerIsBack(SalaHarness harness) {
  harness.network.reachable = true;
  harness.room.reachable = true;
}

Future<void> _theOutboxEmpties(SalaHarness harness) => waitFor(
  'a Outbox esvaziar',
  () async => (await harness.takes.pending()).isEmpty,
);

int _noticesSpoken(SalaHarness harness) => harness.voice.assets
    .where((asset) => asset == offlineNoticeAsset(testLanguage))
    .length;

void main() {
  test(
    'T1: the way back runs on through the Rehearsal and empties the Outbox',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      await _theLadderClimbs(harness, 'com o ensaio aberto');

      _theServerIsBack(harness);
      await _theOutboxEmpties(harness);
      await waitFor('a sala voltar', () => read().reach == RoomReach.fine);
    },
  );

  test(
    'T2: the Rehearsal is drawn while the room is down and stays after it returns',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      notifier.ensaioTap();
      await settle();
      expect(read().stage, SalaStage.ensaio);
      expect(read().voice, VoiceState.invite);
      expect(read().ensaio, EnsaioStatus.recording);
      expect(read().reach, isNot(RoomReach.fine));

      _theServerIsBack(harness);
      await _theOutboxEmpties(harness);
      await waitFor('a sala voltar', () => read().reach == RoomReach.fine);

      expect(read().stage, SalaStage.ensaio);
      expect(read().voice, VoiceState.invite);
      expect(read().ensaio, EnsaioStatus.recording);
    },
  );

  test(
    'T3: the way back runs on through a halt raised during the fall',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      await _haltOnTheRecorder(harness, notifier, read);
      await _theLadderClimbs(harness, 'com o tablet parado');

      _theServerIsBack(harness);
      await _theOutboxEmpties(harness);
    },
  );

  test(
    'T4: a halt raised during the fall stands after the return, until the Desk lifts it',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      await _haltOnTheRecorder(harness, notifier, read);

      _theServerIsBack(harness);
      await _theOutboxEmpties(harness);
      await waitFor('a sala voltar', () => read().reach == RoomReach.fine);
      await settle();

      expect(read().needsPerson, isTrue);
      expect(read().needsPerson, isTrue);

      harness.room.theDeskAttended();
      await waitFor('a mesa levantar a parada', () => !read().needsPerson);
    },
  );

  test('T5: the circle draws the fall, the Rehearsal and the halt', () async {
    final harness = SalaHarness(retryBackoff: _ladder);
    final container = await _fallenInConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _theLadderClimbs(harness, 'com a sala caída');
    expect(read().voice, VoiceState.offline);

    notifier.goEnsaio();
    await _recordATake(harness, notifier);
    expect(read().voice, VoiceState.offline);

    await _haltOnTheRecorder(harness, notifier, read);
    await _theLadderClimbs(harness, 'com o tablet parado');
    expect(read().needsPerson, isTrue);
  });

  test('T6: the offline notice is spoken once for the whole fall', () async {
    final harness = SalaHarness(retryBackoff: _ladder);
    final container = await _fallenInConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    expect(_noticesSpoken(harness), 1);

    notifier.goEnsaio();
    await notifier.goConversa();
    await waitFor('a chamada falhar de novo', () => read().offline);
    await settle();

    expect(_noticesSpoken(harness), 1);
  });

  test(
    'T7: the long press lets an offline room out, and it can fall again',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      expect(_noticesSpoken(harness), 1);

      notifier.resolveWithPerson();
      expect(read().unreachable, isFalse);
      expect(read().reach, RoomReach.fine);

      await waitFor('a sala cair de novo', () => read().offline);
      expect(_noticesSpoken(harness), 2);
      await _theLadderClimbs(harness, 'na segunda queda');
    },
  );

  test(
    'T8: a warning standing across the fall changes nothing of the way back',
    () async {
      final harness = SalaHarness(retryBackoff: _ladder)
        ..room.serverHalt = HaltKind.warning;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      await waitFor(
        'o aviso chegar',
        () => container.read(salaSessionProvider).warning,
      );
      await _theRoomFalls(harness, container);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      expect(read().warning, isTrue);

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      await _theLadderClimbs(harness, 'com o aviso de pé');

      _theServerIsBack(harness);
      await _theOutboxEmpties(harness);
      await waitFor('a sala voltar', () => read().reach == RoomReach.fine);
      expect(read().voice, VoiceState.invite);
      expect(read().warning, isTrue);

      harness.room.theDeskAttended();
      await waitFor('o aviso sair', () => !read().warning);
    },
  );

  test(
    'T11: the Desk lifting a halt raised during the fall brings the room back',
    () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatFallsAsleep);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await _theLadderClimbs(harness, 'uma vez antes de adormecer');

      notifier.goEnsaio();
      await _recordATake(harness, notifier);
      _theServerIsBack(harness);
      await _haltOnTheRecorder(harness, notifier, read);

      harness.room.theDeskAttended();
      await waitFor('a mesa levantar a parada', () => !read().needsPerson);
      await _theOutboxEmpties(harness);
      expect(read().reach, RoomReach.fine);
    },
  );

  test(
    'T13: a call failing again under a halt raised during the fall leaves the halt',
    () async {
      final harness = SalaHarness(
        retryBackoff: _aLadderThatFallsAsleep,
        settleDelay: const Duration(seconds: 2),
      );
      harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.conversa,
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await notifier.abrirEscolha();
      await settle();
      await notifier.goConversa(pericope: 'P01');
      await settle();
      await _theRoomFalls(harness, container);
      await _theLadderClimbs(harness, 'uma vez antes de adormecer');

      _theServerIsBack(harness);
      notifier.goEnsaio();
      await notifier.goConversa(pericope: 'P01');
      await waitFor(
        'a conversa reabrir com a sala ainda fora do alcance',
        () =>
            read().stage == SalaStage.conversa &&
            read().sessionId != null &&
            !read().awaitingTheGuide,
      );
      expect(read().reach, isNot(RoomReach.fine));

      harness.room.holdNextTurn();
      notifier.conversaTap();
      await waitFor('a sala voltar ao toque', () => !read().unreachable);
      notifier.conversaTap();
      await waitFor('o microfone abrir', () => read().channel is Microphone);
      notifier.conversaTap();
      await waitFor('o turno sair', () => harness.room.turnsSent == 1);
      harness.room.serverStatus = 'needs_person';
      harness.room.serverHalt = HaltKind.blocking;
      await waitFor('a sala parar com o turno no ar', () => read().needsPerson);

      harness.room.failHeldTurnWith = const NetworkFailed('sem rede');
      harness.room.finishHeldTurn();
      await settle();
      expect(read().needsPerson, isTrue);

      harness.network.networkComesBack();
      await waitFor('a sala voltar', () => read().reach == RoomReach.fine);
      expect(read().needsPerson, isTrue);
    },
  );

  test(
    'T14: the long press while a return is being tried leaves the room let out',
    () async {
      final harness = SalaHarness(retryBackoff: const [Duration(hours: 1)]);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.network.holdNextCheck();
      notifier.conversaTap();
      await settle();
      harness.room.reachable = true;
      notifier.resolveWithPerson();
      harness.network.finishHeldCheck();
      await settle();

      expect(read().reach, RoomReach.fine);
      expect(read().voice, VoiceState.invite);
      await _theRoomFalls(harness, container);
      expect(_noticesSpoken(harness), 2);
    },
  );

  test('T9: a plain fall comes back to the invite', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(hours: 1)]);
    final container = await _fallenInEnsaio(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    expect(read().voice, VoiceState.offline);

    await _recordATake(harness, notifier);
    _theServerIsBack(harness);
    harness.network.networkComesBack();

    await waitFor('a sala voltar', () => read().voice == VoiceState.invite);
    expect(read().reach, RoomReach.fine);
    await _theOutboxEmpties(harness);
  });

  group('T10: a call failing again while the room is down', () {
    test('reopening the conversa draws the fall again', () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await notifier.goConversa();
      await settle();

      expect(read().voice, VoiceState.offline);
      expect(_noticesSpoken(harness), 1);
      await _theLadderClimbs(harness, 'depois da nova falha');
    });

    test('reopening the wheel draws the fall again', () async {
      final harness = SalaHarness(retryBackoff: _ladder);
      final container = await _fallenInConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      await notifier.abrirEscolha();
      await settle();

      expect(read().voice, VoiceState.offline);
      expect(_noticesSpoken(harness), 1);
      await _theLadderClimbs(harness, 'depois da nova falha');
    });
  });
}
