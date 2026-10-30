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
import 'scenario_helpers.dart'
    show holdTheSession, intoTheBackTranslation, settle;

/// A tablet reopening straight into a kept part, with one take already on disk.
/// Copied from `a_halt_in_the_middle_of_a_capture_leaves_the_microphone_open_test.dart`:
/// fixtures never travel between modules, only the shape does. Landing in
/// [SalaStage.retro] picks the telling-back up; any other stage stays in the
/// rehearsal the resume itself lands in.
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage stage, {
  bool pelaEscolha = true,
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-982').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: stage,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  if (pelaEscolha) {
    harness.emAberto.rows['Ruth/P01/pt'] = row;
  } else {
    await holdTheSession(harness, row);
  }
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  if (!pelaEscolha) {
    await notifier.openTheRoom();
    await intoTheBackTranslation(
      notifier,
      () => container.read(salaSessionProvider),
    );
    return container;
  }
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await settle();
  return container;
}

/// A room reopened into the retro, with a warning already standing so the watch beats,
/// and a capture open over the resumed part: the ground for a denied answer landing
/// over nothing standing at all.
Future<(ProviderContainer, SalaSessionNotifier, SalaSessionState Function())>
_capturingWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  final container = await _reopensInto(
    harness,
    SalaStage.retro,
    pelaEscolha: false,
  );
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);

  await waitFor('o aviso chegar', () => read().warning);
  harness.playback.at = const Duration(seconds: 2);
  notifier.retroTap();
  notifier.retroTap();
  await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);

  return (container, notifier, read);
}

/// The person sign lands while the recorder's answer is still in the air: the build
/// guard's, which calls nobody.
Future<void> _haltLandsBlocking(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  notifier.haltForABrokenBuild();
  await waitFor('a sala parar', () => read().needsPerson);
}

/// A room reopened straight into the rehearsal over the resumed part, with a warning
/// already standing so the watch beats — the ground for a halt landing on a door the
/// halt entry's own capturing guard never touches (`state.ensaio` is not `state.btPhase`),
/// so the only place left to restore what the recorder's answer undoes is the answer
/// itself.
Future<(ProviderContainer, SalaSessionNotifier, SalaSessionState Function())>
_ensaioWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  final container = await _reopensInto(harness, SalaStage.ensaio);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);

  await waitFor('o aviso chegar', () => read().warning);
  notifier.gravarACena(2);
  await waitFor(
    'o ensaio começar a gravar',
    () => read().ensaio == EnsaioStatus.recording,
  );

  return (container, notifier, read);
}

void main() {
  test(
    'the rehearsal is still restored after a denied answer lands late, '
    'off a door the halt entry never touches (criterion 4, rehearsal)',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
      harness.recorder.permitted = false;
      harness.recorder.holdNextStart();
      final (_, notifier, read) = await _ensaioWithAWarningArmed(harness);
      await _haltLandsBlocking(notifier, read);

      harness.recorder.finishStart();
      await settle();

      expect(read().needsPerson, isTrue);
      expect(
        read().ensaio,
        EnsaioStatus.idle,
        reason:
            'a única _undoTheListening() deste caminho é a da resposta '
            'negada; nada mais tira o ensaio de "recording"',
      );
    },
  );

  test('a warning changes nothing when a denied answer lands late '
      '(criterion 5)', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 30));
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    final (_, _, read) = await _capturingWithAWarningArmed(harness);

    harness.recorder.finishStart();
    await settle();

    expect(read().voice, VoiceState.invite);
    expect(read().warning, isTrue);
    expect(read().needsPerson, isFalse);
  });

  test('the invite is still shown when nothing stands and a denied answer '
      'lands late', () async {
    final harness = SalaHarness();
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.conversaTap();
    await settle();
    harness.recorder.finishStart();
    await settle();

    expect(read().voice, VoiceState.invite);
  });
}
