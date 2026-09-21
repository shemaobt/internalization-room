import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

/// How many times the tablet has asked the room what it is doing.
int _stateReads(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'fetchState').length;

/// How many times the room said the halt out loud.
int _haltLines(SalaHarness harness) => harness.voice.assets
    .where((asset) => asset == fixedLineAsset(needsPersonLine, testLanguage))
    .length;

/// A whole turn, from the team touching the circle to the room hearing it.
Future<void> _aTurn(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  await settle();
  notifier.conversaTap();
  await settle();
}

/// A tablet closed part-way through a passage and opened again on it.
///
/// Copied from `the_desk_lifts_the_halt_test.dart`: fixtures never travel between
/// modules, only the shape does.
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage parouEm,
) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-962').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
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
  final container = harness.container();
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

void main() {
  test('a warning that turns blocking on the watch is entered without a '
      'call', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    // The warning already armed the watch; the beat alone must find the halt, with
    // no turn to let door (b) do the finding instead.
    harness.room.serverHalt = HaltKind.blocking;
    await waitFor('a sala parar de vez', () => read().needsPerson);

    expect(_haltLines(harness), 1,
        reason: 'a parada é anunciada uma vez, como qualquer entrada nela');
    expect(harness.room.personsAsked, 0,
        reason: 'a parada foi lida na vigia; o servidor já sabe dela, e o '
            'próprio pedido do tablet apagaria o atendimento da mesa');
    expect(harness.room.calls, isNot(contains('askForAPerson')));

    final asked = _stateReads(harness);
    await waitFor('a vigia continuar batendo', () => _stateReads(harness) > asked);
  });

  test('the pull after a turn enters a blocking halt without a call',
      () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);

    expect(_haltLines(harness), 1);
    expect(harness.room.personsAsked, 0,
        reason: 'a leitura depois do turno de abertura já achou a parada '
            'pronta; pedir de novo marcaria a sessão como se ninguém tivesse '
            'contado ao tablet ainda');
    expect(harness.room.calls, isNot(contains('askForAPerson')));

    final asked = _stateReads(harness);
    await waitFor('a vigia continuar batendo', () => _stateReads(harness) > asked);
  });

  test(
      'reopening into a landed passage enters a blocking halt without a '
      'call', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await _reopensInto(harness, SalaStage.retro);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar ao reabrir', () => read().needsPerson);

    expect(_haltLines(harness), 1);
    expect(harness.room.personsAsked, 0,
        reason: 'reabrir sobre uma parada que o servidor já mantém não é a '
            'sala decidindo nada; contar de novo à mesa apagaria o que ela '
            'já sabe');
    expect(harness.room.calls, isNot(contains('askForAPerson')));

    final asked = _stateReads(harness);
    await waitFor('a vigia continuar batendo', () => _stateReads(harness) > asked);
  });

  test('the room deciding it cannot play its own audio still calls',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.failPlayback();
    await settle();

    expect(read().needsPerson, isTrue);
    expect(harness.room.personsAsked, 1,
        reason: 'pin: a sala decidiu sozinha que não consegue tocar a '
            'própria equipe, e isso continua chamando alguém como sempre');
  });

  test('three degraded turns in a row still call', () async {
    final harness = SalaHarness()..room.turnsAreDegraded = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar por turnos degradados', () => read().needsPerson);

    expect(harness.room.personsAsked, 1,
        reason: 'pin: três turnos degradados são a sala decidindo, e isso '
            'continua chamando alguém como sempre');
  });

  test('the recorder that never started twice in the retro still calls',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await settle();

    harness.recorder.startThrows = true;
    notifier.cortarTrecho();
    await settle();
    notifier.cortarTrecho();
    await settle();

    expect(read().needsPerson, isTrue);
    expect(harness.room.personsAsked, 1,
        reason: 'pin: o microfone que nunca abre duas vezes seguidas é a '
            'sala decidindo, e isso continua chamando alguém como sempre');
  });

  test('a passage the room lost track of still calls, by the device',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const SessionGone();
    await _aTurn(notifier);
    await waitFor('a sala parar sem sessão', () => read().needsPerson);

    expect(harness.room.deviceAsksReceived, ['aparelho-1'],
        reason: 'pin: a sala decidindo que a passagem sumiu (nenhum '
            'pedido ainda pendia sobre ela, ao contrário da reentrada do '
            '404 dentro de um pedido em voo) continua chamando pelo '
            'aparelho, sem sessão para nomear');
    expect(harness.room.calls, isNot(contains('askForAPerson')),
        reason: 'sem sessão não há o que pedir por ela');
  });

  test(
      'an attend that lands in the window a read-door halt used to spend '
      'on its own call is not wiped', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.holdNextAskForAPerson();
    harness.room.serverStatus = 'needs_person';
    harness.room.serverHalt = HaltKind.blocking;
    await _aTurn(notifier);
    await waitFor('a sala parar pela leitura', () => read().needsPerson);

    harness.room.theDeskAttended();
    harness.room.finishHeldAskForAPerson();

    await waitFor(
      'o círculo voltar ao convite',
      () => read().voice == VoiceState.invite,
    );

    expect(harness.room.personsAsked, 0,
        reason: 'nenhum pedido saiu desta parada: com a leitura chamando '
            'antes desta correção, o atendimento que a mesa já tinha dado '
            'entraria na janela entre a entrada na parada e a chamada '
            'pousando, e um pedido pousando depois apagaria esse atendimento');
    expect(harness.room.personArrivedSessions, isEmpty);
    expect(_haltLines(harness), 1,
        reason: 'uma entrada só: a parada obsoleta não se anuncia de novo '
            'quando a vigia a solta em seguida');
  });

  test(
      'the long press on a read halt reaches the server like any '
      'watched halt', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);

    notifier.resolveWithPerson();
    await waitFor(
      'o toque longo avisar a chegada',
      () => harness.room.personArrivedSessions.isNotEmpty,
    );

    expect(harness.room.personArrivedSessions, hasLength(1));
    expect(harness.room.personsAsked, 0,
        reason: 'o toque longo pergunta de novo; não é um pedido');
  });

  test('a warning read after a turn stops nothing and calls nobody',
      () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    expect(read().needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
    expect(_haltLines(harness), 0);
  });
}
