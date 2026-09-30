import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _beat = Duration(milliseconds: 150);

SalaHarness _beating() =>
    SalaHarness(settleDelay: _beat, watchesWithoutAHalt: true);

Future<List<bool>> _haltsAfterTheOldReadLands(
  SalaHarness harness,
  ProviderContainer container,
) async {
  final seen = <bool>[];
  final listening = container.listen(
    salaSessionProvider,
    (_, next) => seen.add(next.needsPerson),
  );
  harness.room.answerHeldRead(harness.room.heldReads.length - 1);
  await settle(const Duration(milliseconds: 60));
  listening.close();
  return seen;
}

Future<void> _aReadIsHeld(SalaHarness harness) async {
  final held = harness.room.heldReads.length;
  harness.room.holdTheNextRead();
  await waitFor(
    'uma leitura sair e ficar presa',
    () => harness.room.heldReads.length > held,
  );
}

Future<ProviderContainer> _reopensIntoRetro(SalaHarness harness) async {
  final pasta = Directory.systemTemp.createTempSync('sala-1168-velha');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final gravada = File('${pasta.path}/p1.m4a')..writeAsBytesSync([1, 2, 3]);
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
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
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

Future<void> _tellsAStretchUpTo(
  SalaSessionNotifier notifier,
  SalaHarness harness,
  SalaSessionState Function() read,
  Duration ate,
) async {
  final antes = read().btTrechos.length;
  harness.playback.at = ate;
  notifier.cortarTrecho();
  notifier.retroTap();
  await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
  notifier.retroTap();
  await waitFor(
    'a tradução ficar pendente',
    () => read().btTraducaoPendente != null,
  );
  await notifier.confirmarTraducao();
  await waitFor('o trecho pousar', () => read().btTrechos.length == antes + 1);
}

void main() {
  test('a read that went out before a stretch was told never takes it back '
      'off the row', () async {
    final harness = _beating();
    final container = await _reopensIntoRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _tellsAStretchUpTo(
      notifier,
      harness,
      read,
      const Duration(seconds: 2),
    );
    await _aReadIsHeld(harness);
    await _tellsAStretchUpTo(
      notifier,
      harness,
      read,
      const Duration(seconds: 4),
    );

    harness.room.answerHeldRead(harness.room.heldReads.length - 1);
    await settle();
    await settle(_beat * 2);

    expect(
      read().btTrechos,
      hasLength(2),
      reason: 'a leitura saiu antes do segundo trecho e não fala por ele',
    );
    expect(
      read().btTrechos.last.retroPath,
      isNotNull,
      reason: 'o trecho contado aqui guarda a sua fala',
    );
  });

  test('an older read that says blocking never halts again a room a newer '
      'read lifted', () async {
    final harness = _beating()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await waitFor('a sala parar', () => read().needsPerson);

    await _aReadIsHeld(harness);
    harness.room.theDeskAttended();
    notifier.resolveWithPerson();
    await waitFor('a sala soltar', () => !read().needsPerson);

    final halts = await _haltsAfterTheOldReadLands(harness, container);

    expect(
      halts,
      everyElement(isFalse),
      reason: 'a leitura velha diz o que a mesa já desfez',
    );
  });

  test('an older read that says nothing never lifts a halt a newer read '
      'found', () async {
    final harness = _beating();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _aReadIsHeld(harness);
    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    await waitFor('a sala parar', () => read().needsPerson);

    final halts = await _haltsAfterTheOldReadLands(harness, container);

    expect(
      halts,
      everyElement(isTrue),
      reason: 'o servidor ainda segura a parada que a leitura nova achou',
    );
  });

  test('a read sent before the call for a person landed never lifts the '
      'halt it called for', () async {
    final harness = _beating();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await settle(_beat * 3);

    await _aReadIsHeld(harness);
    harness.room.failTurnsWith = const Refused('BAD_REQUEST');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor('a sala parar', () => read().needsPerson);
    await waitFor('o pedido chegar', () => harness.room.personsAsked == 1);

    final halts = await _haltsAfterTheOldReadLands(harness, container);

    expect(
      halts,
      everyElement(isTrue),
      reason: 'a leitura saiu antes de o servidor ouvir o pedido',
    );
  });

  test('a pull older than a read already applied still brings the passage\'s '
      'end and its coverage', () async {
    final harness = _beating();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.turnIdInResponse = 'turno-2';
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room
      ..done = true
      ..settledCoverage = coverage(engaged: 5, surfaced: 5);
    final held = harness.room.heldReads.length;
    harness.room.holdTheNextRead();
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-2', status: CoverageStatus.settled),
    );
    await waitFor(
      'a leitura do fim do turno ficar presa',
      () => harness.room.heldReads.length > held,
    );
    final reads = stateReads(harness);
    await waitFor(
      'uma batida mais nova ser aplicada',
      () => stateReads(harness) > reads + 1,
    );

    harness.room.answerHeldRead(harness.room.heldReads.length - 1);
    await waitFor(
      'o círculo dizer que a passagem acabou',
      () => read().voice == VoiceState.done,
    );
    expect(read().coverage.engaged, 5);
  });
}
