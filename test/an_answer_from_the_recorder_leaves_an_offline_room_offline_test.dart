import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

Future<ProviderContainer> _resumingIntoEnsaio(SalaHarness harness) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1057').path}/p1.m4a',
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
  await container.read(salaSessionProvider.notifier).abrirEscolha();
  await settle();
  return container;
}

Future<ProviderContainer> _reopensIntoEnsaio(SalaHarness harness) async {
  final container = await _resumingIntoEnsaio(harness);
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(pericope: 'P01');
  await settle();
  return container;
}

Future<ProviderContainer> _reopensOfflineIntoEnsaio(SalaHarness harness) async {
  final container = await _resumingIntoEnsaio(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  harness.room.reachable = false;
  await notifier.goConversa(pericope: 'P01');
  harness.network.reachable = false;
  await waitFor(
    'a sala cair offline no ensaio',
    () => container.read(salaSessionProvider).offline,
  );
  expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  return container;
}

Future<ProviderContainer> _reopensIntoEnsaioWithAWarning(
  SalaHarness harness,
) async {
  harness.room.serverHalt = HaltKind.warning;
  final container = await _reopensIntoEnsaio(harness);
  await waitFor(
    'o aviso chegar',
    () => container.read(salaSessionProvider).warning,
  );
  return container;
}

void main() {
  test('T1: a denied answer leaves an offline room offline', () async {
    final harness = SalaHarness();
    final container = await _reopensOfflineIntoEnsaio(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    harness.recorder.permitted = false;

    notifier.ensaioTap();
    await settle();

    expect(read().voice, VoiceState.offline);
    expect(read().ensaio, EnsaioStatus.idle);
  });

  test('T2: the first failed start leaves an offline room offline', () async {
    final harness = SalaHarness();
    final container = await _reopensOfflineIntoEnsaio(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    harness.recorder.startThrows = true;

    notifier.ensaioTap();
    await settle();

    expect(read().voice, VoiceState.offline);
    expect(read().ensaio, EnsaioStatus.idle);
  });

  test(
    'T3: the way back survives a denied answer and flushes the outbox',
    () async {
      final harness = SalaHarness(
        retryBackoff: const [Duration(milliseconds: 30)],
      );
      final container = await _reopensOfflineIntoEnsaio(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

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
        reason: 'a gravação feita offline espera na Outbox',
      );

      harness.recorder.permitted = false;
      notifier.ensaioTap();
      await settle();
      expect(read().offline, isTrue);

      final checksBefore = harness.network.checks;
      await waitFor(
        'a escada de retentativas insistir sozinha, sem retryNow()',
        () => harness.network.checks > checksBefore,
        limit: const Duration(seconds: 2),
      );

      harness.network.reachable = true;
      harness.room.reachable = true;
      await waitFor(
        'a sala voltar ao ar sozinha',
        () => read().voice == VoiceState.invite,
      );
      await waitFor(
        'a gravação represada chegar à sala',
        () async => (await harness.takes.pending()).isEmpty,
      );
    },
  );

  test(
    'T4: offline, a denied answer leaves the rest of the unwinding in place',
    () async {
      final harness = SalaHarness();
      final container = await _reopensOfflineIntoEnsaio(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      harness.recorder.permitted = false;

      notifier.ensaioTap();
      await settle();

      expect(read().ensaio, EnsaioStatus.idle);
    },
  );

  test('T5: a warning changes nothing for a denied answer', () async {
    final harness = SalaHarness();
    final container = await _reopensIntoEnsaioWithAWarning(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    harness.recorder.permitted = false;

    notifier.ensaioTap();
    await settle();

    expect(read().voice, VoiceState.invite);
    expect(read().warning, isTrue);
  });

  test('T6: the invite is still shown when nothing stands', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.goEnsaio();
    harness.recorder.permitted = false;

    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });
}
