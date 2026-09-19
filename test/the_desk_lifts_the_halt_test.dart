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

int _createdSessions(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'createSession').length;

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
Future<ProviderContainer> _reopensInto(
  SalaHarness harness,
  SalaStage parouEm,
) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-609').path}/p1.m4a',
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
  test('the desk lifting the halt gives the room back without a touch', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    final asked = _stateReads(harness);
    final turns = harness.room.turnsSent;

    // The facilitator marked the session attended on the desk; nobody touched the tablet.
    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    expect(_stateReads(harness), greaterThan(asked),
        reason: 'a parada bloqueante é vigiada: sem reler o estado a sala nunca '
            'saberia que a mesa a levantou, e a equipe ficaria parada na frente '
            'de uma sessão que o servidor já deu por atendida');

    await _aTurn(notifier);
    await waitFor('mais um turno chegar à sala',
        () => harness.room.turnsSent > turns);

    expect(harness.room.turnsSent, turns + 1,
        reason: 'e a sala solta de verdade: o convite sem turno seria um círculo '
            'respirando sobre uma sala ainda fechada');
  });

  test('the long press on a blocking halt asks the room now and releases nothing',
      () async {
    // A cadence far longer than any answer the fake gives, so that what the touch does
    // is measured by the touch and not by the next beat of the watch arriving under it.
    final harness = SalaHarness(settleDelay: const Duration(seconds: 5))
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    final asked = _stateReads(harness);
    final lines = _haltLines(harness);

    notifier.resolveWithPerson();
    await waitFor('a sala perguntar ao servidor na hora',
        () => _stateReads(harness) > asked,
        limit: const Duration(milliseconds: 2000));

    expect(read().needsPerson, isTrue,
        reason: 'o servidor ainda segura a parada; soltar no toque punha a '
            'equipe de volta a falar dentro de uma sala que a mesa não atendeu');
    expect(_haltLines(harness), lines,
        reason: 'e a parada que continua não é anunciada de novo a cada toque');

    harness.room.theDeskAttended();

    notifier.resolveWithPerson();
    await waitFor('o toque devolver a sala na hora',
        () => read().voice == VoiceState.invite,
        limit: const Duration(milliseconds: 3000));

    expect(read().needsPerson, isFalse,
        reason: 'quem acabou de atender na mesa não espera a próxima batida da '
            'vigia: o toque longo é o pedido de agora');
  });

  test('a warning from the server never stops the room', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala reler o estado', () => _stateReads(harness) > 0);
    await settle(const Duration(milliseconds: 300));
    final turns = harness.room.turnsSent;

    expect(read().needsPerson, isFalse);
    expect(read().voice, VoiceState.invite,
        reason: 'o aviso chama uma pessoa para olhar; nada é recusado à equipe');
    expect(_haltLines(harness), 0,
        reason: 'e nada é dito: a sala anunciar uma parada que não existe faz a '
            'equipe parar sozinha');

    await _aTurn(notifier);
    await waitFor('o turno chegar à sala', () => harness.room.turnsSent > turns);
  });

  test("the room's own halt is lifted by the server too", () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 2))
      ..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar por conta própria', () => read().needsPerson);

    // The desk sees the same halt the tablet raised, and has not attended it yet.
    harness.room.serverStatus = 'needs_person';
    harness.room.serverHalt = HaltKind.blocking;
    final asked = _stateReads(harness);
    await waitFor('a vigia reler o estado', () => _stateReads(harness) > asked);

    expect(read().needsPerson, isTrue,
        reason: 'a parada que o tablet levantou também espera a mesa: soltá-la '
            'sozinha devolveria a sala sem que ninguém tivesse olhado');

    harness.voice.succeeds = true;
    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);
    expect(read().needsPerson, isFalse);
  });

  test('the long press on a room that is out is unchanged', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(read().offline, isTrue);
    final asked = _stateReads(harness);
    final opened = _createdSessions(harness);

    notifier.resolveWithPerson();
    await waitFor('a sala tentar de novo',
        () => _createdSessions(harness) > opened);

    expect(_stateReads(harness), asked,
        reason: 'a queda não é uma parada: perguntar o estado de uma sessão que '
            'não existe gastaria o toque na rota errada');
    expect(read().offline, isTrue,
        reason: 'e o servidor continua fora; um convite aqui seria o mesmo '
            'círculo respirando sobre nada');
  });

  test('the watch ends with the halt and with the room', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    harness.room.theDeskAttended();
    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    final afterRelease = _stateReads(harness);
    await settle(const Duration(milliseconds: 400));

    expect(_stateReads(harness), afterRelease,
        reason: 'a sala solta não é mais vigiada: uma vigia que sobrevive à '
            'soltura bate na rota de estado para sempre, em toda sala aberta');

    harness.room.serverStatus = 'needs_person';
    await _aTurn(notifier);
    await waitFor('a sala parar de novo', () => read().needsPerson);
    await waitFor('a vigia reler o estado',
        () => _stateReads(harness) > afterRelease + 1);
    final beforeDispose = _stateReads(harness);
    container.dispose();
    await settle(const Duration(milliseconds: 400));

    expect(_stateReads(harness), beforeDispose,
        reason: 'e a sala fechada não vigia nada: o tablet guardado seguiria '
            'perguntando por uma sessão que ninguém está olhando');
  });

  test('a room reopened into a halt is watched like any other', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await _reopensInto(harness, SalaStage.retro);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar ao reabrir', () => read().needsPerson);
    final asked = _stateReads(harness);

    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    expect(_stateReads(harness), greaterThan(asked),
        reason: 'reabrir dentro de uma parada é a situação mais comum de todas: '
            'a equipe volta na manhã seguinte, a mesa já atendeu, e sem vigia a '
            'sala só sairia dali por um toque que ninguém sabe dar');
    expect(read().needsPerson, isFalse);
  });

  test('leaving the passage takes the watch with it', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar na primeira passagem', () => read().needsPerson);
    await waitFor('a sala vigiar a parada', () => _stateReads(harness) > 0);

    // The team walks out of the passage they were held in, which is what that gesture is
    // for, and the desk attends the session they left behind.
    notifier.leaveThePassage();
    await settle();
    harness.room.theDeskAttended();

    // In the new passage the call for a person never lands, so nobody was told and there
    // is nothing to watch.
    harness.room.askForAPersonFailsWith = const RoomRefused();
    await notifier.goConversa(pericope: 'P02');
    await settle();
    for (var i = 0; i < 3; i++) {
      await _aTurn(notifier);
    }
    await waitFor('a sala parar na segunda passagem', () => read().needsPerson);

    harness.voice.succeeds = true;
    final asked = _stateReads(harness);
    notifier.resolveWithPerson();
    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    expect(_stateReads(harness), asked,
        reason: 'a vigia da passagem anterior tinha de sair com ela: mantida, o '
            'toque nesta parada pergunta por uma sessão que não é desta sala — '
            'e a resposta que soltar a equipe será sobre o trabalho de outra');
  });

  test('a watched halt that goes offline is watched again when the room returns',
      () async {
    // A cadence wide enough to hold a turn in the air across the settle that stops the
    // room: every gesture is barred once it is stopped, so a call already in flight is
    // the only way a stopped room reaches the offline circle at all.
    final harness = SalaHarness(settleDelay: const Duration(seconds: 2));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.holdNextTurn();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.room.serverStatus = 'needs_person';
    harness.room.serverHalt = HaltKind.blocking;

    await waitFor('a sala parar com o turno no ar', () => read().needsPerson);
    await waitFor('a vigia reler o estado', () => _stateReads(harness) > 1);

    harness.room.failHeldTurnWith = const RoomUnavailable('sem rede');
    harness.room.finishHeldTurn();
    await waitFor('a sala cair', () => read().offline);
    await waitFor('a sala voltar', () => !read().offline);

    // The room is up again and the server is still holding the halt, so the next turn
    // stops the team once more — this time in a room that has been offline under it.
    await _aTurn(notifier);
    await waitFor('a sala parar de novo', () => read().needsPerson);
    final asked = _stateReads(harness);
    harness.room.theDeskAttended();

    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    expect(_stateReads(harness), greaterThan(asked),
        reason: 'a queda levou o timer da vigia e deixou a marca dela de pé: a '
            'sala voltava parada e sem vigia nenhuma, e a marca da mesa não '
            'chegava mais nela — só um toque longo, que é o gesto que esta '
            'fatia existe para tirar do caminho');
  });

  test('a halt with no session releases on the long press, as it always did',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.room.failWith = const SessionGone();
    await _aTurn(notifier);
    await waitFor('a sala parar sem sessão', () => read().needsPerson);
    harness.room.failWith = null;
    expect(read().sessionId, isNull);

    final asked = _stateReads(harness);
    await settle(const Duration(milliseconds: 300));
    expect(_stateReads(harness), asked,
        reason: 'sem sessão não há o que reler: uma vigia sobre um id que o '
            'servidor esqueceu bate numa rota que só sabe responder 404');

    notifier.resolveWithPerson();
    await waitFor('o círculo voltar ao convite',
        () => read().voice == VoiceState.invite);

    final turns = harness.room.turnsSent;
    await _aTurn(notifier);
    await waitFor('mais um turno chegar à sala',
        () => harness.room.turnsSent > turns);

    expect(read().needsPerson, isFalse,
        reason: 'não há ninguém a quem perguntar, então o toque continua sendo '
            'a saída: sem ele a equipe ficaria presa para sempre');
  });
}
