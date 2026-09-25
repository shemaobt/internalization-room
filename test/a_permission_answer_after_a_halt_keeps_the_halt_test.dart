import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

/// A tablet reopening straight into a kept part, with one take already on disk.
/// Copied from `a_halt_in_the_middle_of_a_capture_closes_the_microphone_test.dart`:
/// fixtures never travel between modules, only the shape does. Landing in
/// [SalaStage.retro] picks the telling-back up; any other stage stays in the
/// rehearsal the resume itself lands in.
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage stage,
) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-982').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
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
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

/// A room reopened into the retro, with a warning already standing so the watch beats,
/// and a capture open over the resumed part: the ground for a denied or failed answer
/// landing over a read halt, or over nothing standing at all.
Future<(ProviderContainer, SalaSessionNotifier, SalaSessionState Function())>
_capturingWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  final container = await _reopensInto(harness, SalaStage.retro);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);

  await waitFor('o aviso chegar', () => read().warning);
  harness.playback.at = const Duration(seconds: 2);
  notifier.cortarTrecho();
  notifier.retroTap();
  await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);

  return (container, notifier, read);
}

/// The same ground, but the capture is opened by `traduzirDeNovo` over a stretch already
/// told, arming a mend in the same gesture.
Future<(ProviderContainer, SalaSessionNotifier, SalaSessionState Function())>
_mendCapturingWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  harness.room.retroSoFar = const BackTranslationProgress(
    segments: [
      SegmentView(
        segmentId: 'trecho-1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 12000,
      ),
    ],
  );
  final container = await _reopensInto(harness, SalaStage.retro);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);

  await waitFor('o aviso chegar', () => read().warning);
  final trecho = read().btTrechos.first;
  notifier.traduzirDeNovo(trecho);
  await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);

  return (container, notifier, read);
}

/// Turn the standing warning blocking, and wait for the watch's next beat to find it.
Future<void> _haltLandsBlocking(
  SalaHarness harness,
  SalaSessionState Function() read,
) async {
  harness.room.serverHalt = HaltKind.blocking;
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
  notifier.ensaioTap();
  await waitFor(
    'o ensaio começar a gravar',
    () => read().ensaio == EnsaioStatus.recording,
  );

  return (container, notifier, read);
}

/// Record one part and wait for the room to have named it.
Future<void> _gravaParte(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  final partesAntes = container.read(salaSessionProvider).partes.length;
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  await waitFor('a sala nomear a parte', () {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length > partesAntes && partes.last.takeId != null;
  });
}

/// The ordinary door into the retro, with no halt or warning standing — the ground for a
/// halt the room decides on its own, whose ask for a person is still in flight when the
/// answer lands, with no other watch already running.
Future<ProviderContainer> _inRetro(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  notifier.goEnsaio();
  await _gravaParte(container, notifier);
  notifier.startRetro();
  await settle();
  return container;
}

void main() {
  test('a blocking halt still stands after a denied answer lands late '
      '(criterion 1)', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    final (_, _, read) = await _capturingWithAWarningArmed(harness);
    await _haltLandsBlocking(harness, read);
    final soundsBefore = harness.sounds.length;

    harness.recorder.finishStart();
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'uma parada de pé não pode ser apagada por uma resposta do '
          'gravador que chega depois dela',
    );
    expect(read().btPhase, BtPhase.playing);
    expect(read().btClipRodando, isFalse);
    expect(
      harness.sounds.sublist(soundsBefore),
      isNot(contains('recorder:discard')),
      reason:
          'a entrada da parada já descartou o gravador; a resposta '
          'atrasada não tem mais nada para fechar',
    );
  });

  test('a blocking halt still stands after the first failed start '
      '(criterion 2)', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
    harness.recorder.permitted = true;
    harness.recorder.startThrows = true;
    harness.recorder.holdNextStart();
    final (_, _, read) = await _capturingWithAWarningArmed(harness);
    await _haltLandsBlocking(harness, read);
    final personsAskedBefore = harness.room.personsAsked;

    harness.recorder.finishStart();
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a primeira falha do gravador não pode apagar uma parada de '
          'pé — ela ainda é só a primeira tentativa da escada de três',
    );
    expect(
      harness.room.personsAsked,
      personsAskedBefore,
      reason: 'uma parada que a sala só leu não chama ninguém',
    );
  });

  test('a self-decided halt whose ask is still in flight survives a late '
      'denied answer (criterion 3, no watch yet)', () async {
    final harness = SalaHarness();
    harness.room.holdNextAskForAPerson();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.recorder.returnsEmpty = true;
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    harness.playback.at = const Duration(seconds: 2);
    notifier.cortarTrecho();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
    await confirmarATraducao(container);
    await waitFor('a sala decidir sozinha', () => read().needsPerson);
    expect(
      harness.room.calls.where((call) => call == 'askForAPerson').length,
      1,
      reason: 'o pedido já foi disparado e está em voo, sem resposta ainda',
    );

    harness.recorder.finishStart();
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a resposta atrasada não pode apagar a parada que a própria '
          'sala decidiu, enquanto o pedido por uma pessoa ainda está em '
          'voo e nenhuma vigia corre ainda',
    );

    harness.room.finishHeldAskForAPerson();
    await settle();
    harness.room.theDeskAttended();
    await waitFor(
      'o círculo voltar ao convite',
      () => read().voice == VoiceState.invite,
    );

    expect(
      harness.room.personsAsked,
      1,
      reason: 'nenhum segundo pedido foi disparado',
    );
  });

  test('the retry ladder still insists after a late denied answer erases '
      'the call that was in flight (criterion 3, the retry ladder)', () async {
    final harness = SalaHarness();
    harness.room.askForAPersonFailsWith = const RoomUnavailable('sem rede');
    harness.room.holdNextAskForAPerson();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.recorder.returnsEmpty = true;
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    harness.playback.at = const Duration(seconds: 2);
    notifier.cortarTrecho();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
    await confirmarATraducao(container);
    await waitFor('a sala decidir sozinha', () => read().needsPerson);

    // A resposta negada pousa enquanto o primeiro pedido ainda está preso no
    // hold, antes de a falha correr e a escada decidir se insiste.
    harness.recorder.finishStart();
    await settle();

    harness.room.finishHeldAskForAPerson();
    await settle(Duration.zero);
    harness.room.askForAPersonFailsWith = null;

    await waitFor(
      'a retentativa ser enviada e confirmada',
      () =>
          harness.room.calls.where((call) => call == 'askForAPerson').length ==
          2,
    );
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a escada tem de continuar insistindo depois da 1ª falha, '
          'mesmo com a resposta negada tendo apagado a parada no meio do '
          'caminho',
    );
    expect(
      harness.room.personsAsked,
      1,
      reason: 'só a retentativa foi confirmada pelo servidor; a 1ª falhou',
    );

    harness.room.theDeskAttended();
    await waitFor(
      'o círculo voltar ao convite',
      () => read().voice == VoiceState.invite,
    );
  });

  test('the phase, the mend and the halo are still restored after a denied '
      'answer lands late (criterion 4, mend capture)', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
    harness.recorder.permitted = false;
    harness.recorder.holdNextStart();
    final (_, _, read) = await _mendCapturingWithAWarningArmed(harness);
    await _haltLandsBlocking(harness, read);

    harness.recorder.finishStart();
    await settle();

    expect(read().needsPerson, isTrue);
    expect(read().btPhase, BtPhase.playing);
    expect(read().btClipRodando, isFalse);
    expect(read().btConsertando, isFalse);
    expect(read().ensaio, EnsaioStatus.idle);
  });

  test(
    'the rehearsal is still restored after a denied answer lands late, '
    'off a door the halt entry never touches (criterion 4, rehearsal)',
    () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
      harness.recorder.permitted = false;
      harness.recorder.holdNextStart();
      final (_, _, read) = await _ensaioWithAWarningArmed(harness);
      await _haltLandsBlocking(harness, read);

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
