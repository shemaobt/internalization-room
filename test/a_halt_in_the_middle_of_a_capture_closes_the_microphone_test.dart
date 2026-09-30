import 'dart:async';
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

/// A tablet reopening straight into an unchecked telling-back, with one part already
/// named. Copied from `the_desk_lifts_the_halt_test.dart`: fixtures never travel between
/// modules, only the shape does.
Future<ProviderContainer> _reopensIntoRetro(SalaHarness harness) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-963').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
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
  notifier.cortarTrecho();
  notifier.retroTap();
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

/// Record one part and wait for the room to have named it, the way `retro_segments_test`
/// does — for the tests that need the ordinary ensaio-to-retro door instead of a reopen.
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
  test('a blocking halt read while capturing closes the microphone and '
      'undoes the listening', () async {
    final harness = SalaHarness();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );
    final captureIndex = harness.sounds.lastIndexOf('recorder:start');

    await _haltLandsBlocking(harness, read);

    expect(read().needsPerson, isTrue);
    expect(read().needsPerson, isTrue);
    expect(
      harness.sounds.sublist(captureIndex + 1),
      contains('recorder:discard'),
      reason:
          'o gravador tem de ser descartado depois de ter sido aberto — o '
          'testemunho que a nota do harness pede',
    );
    expect(
      harness.recorder.deleted,
      isNotEmpty,
      reason: 'a peça que estava sendo escrita se foi',
    );
    expect(
      read().btPhase,
      BtPhase.playing,
      reason: 'a fase volta para a que a captura interrompeu',
    );
    expect(
      read().btClipRodando,
      isFalse,
      reason: 'o halo do clipe para junto com o microfone',
    );
    expect(
      harness.room.calls,
      isNot(contains('sendChunk')),
      reason: 'a captura fechada não vira um trecho enviado',
    );
  });

  test('after the attend, the check sends nothing', () async {
    final harness = SalaHarness();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );
    await _haltLandsBlocking(harness, read);
    final chunksBefore = harness.room.chunksSent;

    harness.room.theDeskAttended();
    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

    await notifier.confirmarTraducao();
    await settle();

    expect(
      harness.room.calls,
      isNot(contains('sendChunk')),
      reason:
          'a captura já estava fechada quando a parada pousou; o V depois '
          'do atendimento não pode mandá-la como se fosse uma tradução '
          'pendente',
    );
    expect(harness.room.chunksSent, chunksBefore);
  });

  test('after the attend, the circle opens a fresh capture', () async {
    final harness = SalaHarness();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );
    await _haltLandsBlocking(harness, read);
    harness.room.theDeskAttended();
    await waitFor('o círculo voltar ao convite', () => !read().needsPerson);

    harness.playback.at = const Duration(seconds: 2);
    notifier.cortarTrecho();
    notifier.retroTap();
    await waitFor(
      'uma nova captura abrir',
      () => read().btPhase == BtPhase.capturing,
    );

    expect(
      harness.sounds.where((s) => s == 'recorder:start').length,
      2,
      reason: 'o círculo abre um microfone novo, do zero',
    );
  });

  test('a recording already in the outbox is still delivered while the halt '
      'stands', () async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );
    final fila = harness.takes as FakeTakeQueue;
    final sessionId = read().sessionId!;
    final segunda = File(
      '${Directory.systemTemp.createTempSync('sala-963-fila').path}/p2.m4a',
    )..writeAsBytesSync([4, 5, 6]);
    addTearDown(() => segunda.parent.deleteSync(recursive: true));

    harness.room.holdNextTake(KeptScope.parte(2));
    await fila.enqueue(
      segunda,
      sessionId: sessionId,
      kind: 'ensaio',
      scope: KeptScope.parte(2),
    );
    unawaited(fila.flush());
    await harness.room.untilTakeHeld();

    await _haltLandsBlocking(harness, read);
    expect(
      fila.rows.single.stored,
      isFalse,
      reason: 'ainda presa no envio quando a parada pousa',
    );

    harness.room.finishHeldTake();
    await waitFor('a gravação em fila chegar', () => fila.rows.single.stored);

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a parada é sobre a equipe, não sobre a rede: a fila entrega o '
          'que já tinha, sem esperar o atendimento',
    );
  });

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

  test('the halt the room decided on its own inside the capture close is '
      'unchanged', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.recorder.returnsEmpty = true;
    final discardsBefore = harness.sounds
        .where((s) => s == 'recorder:discard')
        .length;
    harness.playback.at = const Duration(seconds: 2);
    notifier.cortarTrecho();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
    notifier.retroTap();
    await waitFor('a sala decidir sozinha', () => read().needsPerson);

    expect(
      harness.sounds.where((s) => s == 'recorder:discard').length,
      discardsBefore,
      reason:
          'o gravador já tinha sido parado por _finishChunkCapture; a '
          'entrada da parada não tem mais nada para descartar',
    );
    expect(read().btPhase, BtPhase.playing);
  });

  test('a halt landing while the start is still in the air leaves nothing '
      'open once it lands', () async {
    final harness = SalaHarness();
    harness.recorder.holdNextStart();
    final (container, notifier, read) = await _capturingWithAWarningArmed(
      harness,
    );

    await _haltLandsBlocking(harness, read);
    expect(read().btPhase, BtPhase.playing);
    final discardsBeforeStart = harness.sounds
        .where((s) => s == 'recorder:discard')
        .length;

    harness.recorder.finishStart();
    await settle();

    expect(
      harness.sounds.where((s) => s == 'recorder:discard').length,
      greaterThan(discardsBeforeStart),
      reason:
          'o gravador só respondeu depois de a parada já ter desistido '
          'dele; nada mais o fecharia',
    );
    expect(read().btPhase, BtPhase.playing);
  });
}
