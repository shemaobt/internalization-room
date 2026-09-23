import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

/// A tablet reopening straight into a kept part of the Rehearsal, with one take already
/// on disk — the shape `a_permission_answer_after_a_halt_keeps_the_halt_test.dart` already
/// uses for the same resume.
Future<ProviderContainer> _reopensIntoEnsaio(SalaHarness harness) async {
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
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

/// The room offline in the Rehearsal: the same reopening above, but the room refuses the
/// state fetch the resume makes right after it lands in `ensaio` — the door the plan
/// names, since neither `conversaTap` nor `retroTap` will start a recorder while offline.
Future<ProviderContainer> _reopensOfflineIntoEnsaio(SalaHarness harness) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1057-offline').path}/p1.m4a',
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

  // The network stays reachable through the call: `goConversa` checks it before the
  // resume, and dropping it here would fall the room offline from `conversa`, never
  // reaching `ensaio`. The room refuses the state fetch the resume makes right after
  // landing in `ensaio`, which is what falls it offline. `network.reachable` is dropped
  // right after, synchronously, before the fall's own retry can find the network fine
  // and bring the room straight back before a test ever sees it offline.
  harness.room.reachable = false;
  await notifier.goConversa(pericope: 'P01');
  harness.network.reachable = false;
  await waitFor(
    'a sala cair offline no ensaio',
    () => container.read(salaSessionProvider).offline,
  );
  expect(
    container.read(salaSessionProvider).stage,
    SalaStage.ensaio,
    reason: 'a queda tem que pousar no ensaio, não em outro estágio',
  );
  return container;
}

/// The same reopening, with a warning already standing so criterion 5 can be checked
/// without ever going offline.
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

      // A take made while offline: the room refuses the flush, and it waits in the
      // Outbox.
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
      notifier.retryNow();
      await settle();
      expect(
        harness.network.checks,
        greaterThan(checksBefore),
        reason: 'retryNow() precisa tentar alcançar a sala, não ser um no-op',
      );

      harness.network.reachable = true;
      harness.room.reachable = true;
      notifier.retryNow();
      await waitFor(
        'a sala voltar ao ar',
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
      // Neither `conversaTap` nor `retroTap` starts a recorder while offline (both
      // return through `retryNow()` first), so the Rehearsal is the only capture this
      // ticket's door reaches; pinned here instead of a second capture kind.
      final harness = SalaHarness();
      final container = await _reopensOfflineIntoEnsaio(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      harness.recorder.permitted = false;

      notifier.ensaioTap();
      await settle();

      expect(read().ensaio, EnsaioStatus.idle);
      expect(read().noteMode, isFalse);
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
