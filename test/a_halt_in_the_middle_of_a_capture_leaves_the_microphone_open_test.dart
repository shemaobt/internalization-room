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
import 'support/temp.dart';

/// A tablet reopening straight into an unchecked telling-back, with one part already
/// named. Copied from `the_desk_lifts_the_halt_test.dart`: fixtures never travel between
/// modules, only the shape does.
Future<ProviderContainer> _reopensIntoRetro(SalaHarness harness) async {
  final gravada = File('${aTempDir('sala-963').path}/p1.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await settle();
  return container;
}

/// A room reopened into the retro, with a warning already standing so the watch beats,
/// and a capture open over the resumed part: the ground the acceptance criteria measure.
Future<(ProviderContainer, SalaSessionNotifier, SalaSessionState Function())>
_capturingWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  final container = await _reopensIntoRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);

  await waitFor('o aviso chegar', () => read().warning);
  harness.playback.at = const Duration(seconds: 2);
  notifier.retroTap();
  notifier.retroTap();
  await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);

  return (container, notifier, read);
}

Future<void> _aHaltIsRaised(SalaSessionNotifier notifier) async {
  notifier.haltForABrokenBuild();
  await settle();
}

/// Record one part and wait for the room to have named it, the way `retro_segments_test`
/// does — for the tests that need the ordinary ensaio-to-retro door instead of a reopen.
Future<void> _gravaParte(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  final partesAntes = container.read(salaSessionProvider).partes.length;
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  await waitFor('a sala nomear a parte', () {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length > partesAntes && partes.last.takeId != null;
  });
}

Future<ProviderContainer> _inRetro(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await settle();
  notifier.goEnsaio();
  await _gravaParte(container, notifier);
  notifier.startRetro();
  await settle();
  return container;
}

void main() {
  test(
    'a halt raised while capturing on the back-translation leaves the '
    'microphone open, and the circle\'s tap sends the take, as hers',
    () async {
      final harness = SalaHarness();
      final (container, notifier, read) = await _capturingWithAWarningArmed(
        harness,
      );
      final captureIndex = harness.sounds.lastIndexOf('recorder:start');

      await _aHaltIsRaised(notifier);

      expect(read().needsPerson, isFalse);
      expect(
        read().btPhase,
        BtPhase.capturing,
        reason: 'a parada fechava a captura, e o Drafting dela nunca a toca',
      );
      expect(
        harness.sounds.sublist(captureIndex + 1),
        isNot(contains('recorder:discard')),
        reason: 'o gravador era descartado no meio da frase da equipe',
      );

      notifier.retroTap();
      await waitFor(
        'o trecho seguir para a sala',
        () => harness.room.calls.contains('sendChunk'),
      );

      expect(harness.room.calls, contains('sendChunk'));
    },
  );

  test('a warning changes nothing', () async {
    final harness = SalaHarness();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );
    final asked = stateReads(harness);
    await waitFor(
      'mais uma batida da vigia',
      () => stateReads(harness) > asked,
    );

    expect(
      read().btPhase,
      BtPhase.capturing,
      reason: 'a captura segue aberta depois da vigia ler o aviso de novo',
    );
    expect(read().warning, isTrue);
    final captureIndex = harness.sounds.lastIndexOf('recorder:start');
    expect(
      harness.sounds.sublist(captureIndex + 1),
      isNot(contains('recorder:discard')),
      reason: 'um aviso não refusa nada à equipe',
    );
    expect(read().needsPerson, isFalse);
  });

  test('an empty translation take closes the capture with no person sign, and '
      'nothing discards the recorder twice', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.recorder.returnsEmpty = true;
    final discardsBefore = harness.sounds
        .where((s) => s == 'recorder:discard')
        .length;
    harness.playback.at = const Duration(seconds: 2);
    notifier.retroTap();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
    notifier.retroTap();
    await waitFor('a captura fechar', () => read().btPhase == BtPhase.playing);
    await settle();

    expect(read().needsPerson, isFalse);
    expect(
      harness.sounds.where((s) => s == 'recorder:discard').length,
      discardsBefore,
      reason:
          'o gravador já tinha sido parado por _finishChunkCapture; nada '
          'mais tem o que descartar',
    );
    expect(read().btPhase, BtPhase.playing);
  });

  test('a halt raised while the microphone is still starting lets the capture '
      'open once it lands', () async {
    final harness = SalaHarness();
    harness.recorder.holdNextStart();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );

    await _aHaltIsRaised(notifier);
    final discardsBeforeStart = harness.sounds
        .where((s) => s == 'recorder:discard')
        .length;

    harness.recorder.finishStart();
    await settle();

    expect(read().needsPerson, isFalse);
    expect(
      read().btPhase,
      BtPhase.capturing,
      reason: 'a parada desistia do microfone que ainda estava abrindo',
    );
    expect(
      harness.sounds.where((s) => s == 'recorder:discard').length,
      discardsBeforeStart,
    );
  });
}
