import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _gravacao = 'gravacao-1';

SegmentView _trecho(String id, int startsMs, int endsMs) => SegmentView(
  segmentId: id,
  takeId: _gravacao,
  startsMs: startsMs,
  endsMs: endsMs,
);

Future<ProviderContainer> _reopensIntoRetro(SalaHarness harness) async {
  final pasta = Directory.systemTemp.createTempSync('sala-1168-leitura');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final gravada = File('${pasta.path}/p1.m4a');
  gravada.writeAsBytesSync([1, 2, 3]);
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: _gravacao,
      ),
    ],
  );
  await holdTheSession(harness, row);
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.openTheRoom();
  await intoTheBackTranslation(
    notifier,
    () => container.read(salaSessionProvider),
  );
  await settle();
  return container;
}

void main() {
  test('the Watch\'s read brings the stretches with the halt and the '
      'warning', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning
      ..room.retroSoFar = BackTranslationProgress(
        segments: [_trecho('trecho-1', 0, 12000)],
      );
    final container = await _reopensIntoRetro(harness);
    SalaSessionState read() => container.read(salaSessionProvider);
    await waitFor('o aviso chegar', () => read().warning);
    expect(read().btTrechos, hasLength(1));

    harness.room.retroSoFar = BackTranslationProgress(
      segments: [
        _trecho('trecho-1', 0, 12000),
        _trecho('trecho-2', 12000, 30000),
      ],
    );
    await waitFor(
      'a leitura da vigia trazer o trecho novo',
      () => read().btTrechos.length == 2,
    );

    expect(read().warning, isTrue);
  });

  test('the read after a turn that says a person is needed keeps the warning '
      'and raises no sign', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await waitFor('o aviso chegar', () => read().warning);

    harness.room.serverHalt = HaltKind.blocking;
    final turns = harness.room.turnsSent;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor('o turno chegar', () => harness.room.turnsSent > turns);
    final reads = stateReads(harness);
    await waitFor(
      'a leitura depois do turno',
      () => stateReads(harness) > reads,
    );
    await settle();

    expect(
      read().needsPerson,
      isFalse,
      reason: 'uma leitura nunca levanta o sinal da pessoa',
    );
    expect(read().warning, isTrue);
    expect(harness.room.personsAsked, 0);
  });
}
