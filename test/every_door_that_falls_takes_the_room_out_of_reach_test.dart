import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;

const _aLadderThatWaits = [Duration(hours: 1)];
const _theKeyStillInFlight = Refused('IDEMPOTENCY_KEY_IN_FLIGHT');
final _parte1 = KeptScope.parte(1);

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  Future<void> outOfReach(String why) =>
      waitFor('a sala ficar fora de alcance $why', () => estado.unreachable);

  void theNetworkFalls() {
    harness.network.reachable = false;
    harness.room.reachable = false;
  }

  void theNetworkReturns() {
    harness.network.reachable = true;
    harness.room.reachable = true;
    harness.network.networkComesBack();
  }

  int get offlineNotices => harness.voice.assets
      .where((asset) => asset == offlineNoticeAsset(testLanguage))
      .length;
}

Future<_Room> _conversa(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

Future<void> _keepARehearsalPart(_Room room) async {
  room.sala.goEnsaio();
  room.sala.ensaioTap();
  room.sala.ensaioTap();
  await settle();
  room.sala.takeKeep();
}

Future<_Room> _aResumedBackTranslation(
  SalaHarness harness, {
  List<SegmentView> told = const [],
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-alcance');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness.playback
    ..length = const Duration(seconds: 30)
    ..measured = const Duration(seconds: 30);
  harness.room.retroSoFar = BackTranslationProgress(segments: told);
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: _parte1,
        path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await room.sala.abrirEscolha();
  await room.sala.goConversa(pericope: 'P01');
  await waitFor(
    'a tradução retomada pôr a parte no ar',
    () => room.estado.stage == SalaStage.retro,
  );
  return room;
}

Future<void> _tellAStretchUpTo(_Room room, Duration where) async {
  await theClipOpens(room.harness);
  room.harness.playback.at = where;
  room.sala.cortarTrecho();
  room.sala.retroTap();
  await settle();
  room.sala.retroTap();
  await waitFor(
    'a tradução ficar pendente',
    () => room.estado.btTraducaoPendente != null,
  );
}

Future<_Room> _aFindingToTellAgain(SalaHarness harness) async {
  const contado = 'gravacao-1@0-30000';
  harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingSegmentId = contado;
  final room = await _aResumedBackTranslation(
    harness,
    told: const [
      SegmentView(
        segmentId: contado,
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 30000,
      ),
    ],
  );
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução poder pedir o veredito',
    () => room.estado.canFinishBackTranslation,
  );
  await room.sala.finishBackTranslation();
  await waitFor(
    'o achado apontar o trecho',
    () => room.estado.btFindingTrecho != null,
  );
  room.sala.traduzirDeNovoEmPortugues();
  room.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => room.estado.btPhase == BtPhase.capturing,
  );
  await fecharACaptura(room.container);
  return room;
}

void main() {
  test('1 (a): a rehearsal upload that fails on the network takes the room out '
      'of reach, and the circle says so', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits)
      ..room.unreachableTake = 'ensaio/$_parte1';
    final room = await _conversa(harness);

    await _keepARehearsalPart(room);

    await room.outOfReach('pela Outbox');
    expect(room.estado.voice, VoiceState.offline);
  });

  test('2 (b): reachable with a part pending after a failed try, the part is '
      'tried again once its backoff passes, with no gesture', () async {
    const backoff = Duration(milliseconds: 400);
    final stumbling = _RoomThatCannotReadTheTakeOnce();
    final harness = SalaHarness(
      room: stumbling,
      takesOverride: (room, home) => TakeUploadQueue(
        room: room,
        home: () async => home,
        backoff: [backoff],
      ),
    );
    final room = await _conversa(harness);

    await _keepARehearsalPart(room);
    await waitFor('a primeira tentativa falhar', () => stumbling.stumbled);
    final failedAt = DateTime.now();

    await waitFor(
      'a parte subir sozinha',
      () => harness.room.takesKept.contains('ensaio/$_parte1'),
      limit: const Duration(seconds: 3),
    );
    expect(
      DateTime.now().difference(failedAt),
      greaterThanOrEqualTo(backoff - const Duration(milliseconds: 50)),
      reason: 'a segunda tentativa espera o tempo da Outbox',
    );
    expect(room.estado.unreachable, isFalse);
    await waitFor('a contagem zerar', () => room.estado.unsentTakes == 0);
  });

  group('3 (c): a request sent while out of reach goes out once more under '
      'the same Idempotency-Key when the network returns', () {
    test('a stretch told back lands on the Step that asked', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _aResumedBackTranslation(harness);
      await _tellAStretchUpTo(room, const Duration(seconds: 12));
      room.theNetworkFalls();

      await room.sala.confirmarTraducao();
      await room.outOfReach('pelo trecho');
      room.theNetworkReturns();

      await waitFor('o trecho pousar', () => room.estado.btTrechos.isNotEmpty);
      await settle();
      expect(harness.room.chunkKeys, hasLength(2));
      expect(harness.room.chunkKeys.first, isNotEmpty);
      expect(harness.room.chunkKeys.toSet(), hasLength(1));
      expect(harness.room.segments, hasLength(1));
      expect(room.estado.btTrechos.single.to, const Duration(seconds: 12));
      expect(room.estado.btTraducaoPendente, isNull);
      expect(room.estado.unreachable, isFalse);
    });

    test('a stretch told again lands on the Step that asked', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _aFindingToTellAgain(harness);
      room.theNetworkFalls();

      await room.sala.confirmarTraducao();
      await room.outOfReach('pela correção');
      room.theNetworkReturns();

      await waitFor(
        'a correção pousar',
        () => harness.room.replacesAsked.isNotEmpty,
      );
      await waitFor(
        'a sala sair do pensando',
        () => room.estado.btPhase != BtPhase.thinking,
      );
      await settle();
      expect(harness.room.replaceKeys, hasLength(2));
      expect(harness.room.replaceKeys.first, isNotEmpty);
      expect(harness.room.replaceKeys.toSet(), hasLength(1));
      expect(harness.room.replacesAsked, hasLength(1));
      expect(room.estado.btTraducaoPendente, isNull);
    });
  });

  test('4 (d): the Watch read that fails on the network takes the room out of '
      'reach, and on return the Watch reads at once', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 400),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    harness.network.reachable = false;
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');

    await room.outOfReach('pela Watch');
    final reads = harness.room.calls.where((c) => c == 'fetchState').length;
    room.theNetworkReturns();

    await waitFor(
      'a Watch ler na volta',
      () => harness.room.calls.where((c) => c == 'fetchState').length > reads,
      limit: const Duration(milliseconds: 250),
    );
  });

  group('5: every door\'s network failure takes the room out of reach', () {
    test('the person ask', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _conversa(harness);
      harness.room
        ..failTurnsWith = const Refused('PIPELINE_REFUSED')
        ..askForAPersonFailsWith = const NetworkFailed('sem rede');

      room.sala.conversaTap();
      await settle();
      room.sala.conversaTap();

      await waitFor('a sala chamar uma pessoa', () => room.estado.needsPerson);
      await room.outOfReach('pelo pedido de uma pessoa');
    });

    test('person-arrived', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _conversa(harness);
      harness.room
        ..failTurnsWith = const Refused('PIPELINE_REFUSED')
        ..personArrivedFailsWith = const NetworkFailed('sem rede');
      room.sala.conversaTap();
      await settle();
      room.sala.conversaTap();
      await waitFor('o pedido pousar', () => harness.room.personsAsked == 1);
      await settle();

      room.sala.resolveWithPerson();

      await room.outOfReach('pelo aviso de que alguém chegou');
    });

    test('the resume reads', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits)
        ..room.failTakesWith = const NetworkFailed('sem rede');
      harness.emAberto.rows['Ruth/P01'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: [
          KeptTake(
            scopeId: _parte1,
            path: '/nao/existe/p1.m4a',
            takeId: 'gravacao-1',
          ),
        ],
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final room = _Room(harness, container);
      await room.sala.abrirEscolha();

      await room.sala.goConversa(pericope: 'P01');

      await room.outOfReach('pela leitura da retomada');
      expect(room.estado.needsPerson, isFalse);
    });

    test('the hand reply', () async {
      final harness = SalaHarness(
        retryBackoff: _aLadderThatWaits,
        replies: const [HandReply(id: 'r1', audioUrl: '/resposta/r1')],
      );
      final room = await _conversa(harness);
      await waitFor('a resposta chegar', () => room.estado.hasUnheardReply);
      harness.voice.roomFailsWith = const NetworkFailed('sem rede');

      room.sala.handTap();

      await room.outOfReach('pela resposta da mão');
    });

    test('the inbox', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _conversa(harness);
      harness.inbox.cannotBeAsked = true;

      room.sala.conversaTap();
      await settle();
      room.sala.conversaTap();

      await room.outOfReach('pela caixa de respostas');
    });

    test('the coverage stream', () async {
      final harness = SalaHarness(
        retryBackoff: _aLadderThatWaits,
        settleDelay: const Duration(seconds: 5),
      );
      final room = await _conversa(harness);
      room.sala.conversaTap();
      await settle();
      room.sala.conversaTap();
      await waitFor(
        'a sala escutar o canal da cobertura',
        () => harness.room.coverageHasListener,
      );
      harness.network.reachable = false;

      harness.room.dropCoverageStream(error: const NetworkFailed('sem rede'));

      await room.outOfReach('pelo canal da cobertura');
    });

    test('the reads after a verdict', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true
        ..verdictFindingSegmentId = 'gravacao-1@0-30000';
      final room = await _aResumedBackTranslation(harness);
      harness.playback.finishPlayback();
      await waitFor(
        'a tradução poder pedir o veredito',
        () => room.estado.canFinishBackTranslation,
      );
      harness.room.failStateOnceWith = const NetworkFailed('sem rede');

      await room.sala.finishBackTranslation();

      await room.outOfReach('pela releitura depois do veredito');
    });

    test('the question door', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _conversa(harness);
      harness.inbox.refuses = true;

      room.sala.handTap();
      room.sala.conversaTap();
      await waitFor(
        'a pergunta abrir o microfone',
        () => room.estado.channel is Microphone,
      );
      room.sala.conversaTap();

      await room.outOfReach('pela pergunta');
    });

    test('the question door classifies a refusal as a refusal, like every '
        'other door', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await _conversa(harness);
      harness.inbox.refusesTheQuestionWith = const Refused('QUESTION_REFUSED');

      room.sala.handTap();
      room.sala.conversaTap();
      await waitFor(
        'a pergunta abrir o microfone',
        () => room.estado.channel is Microphone,
      );
      room.sala.conversaTap();
      await waitFor(
        'a pergunta sair',
        () => room.estado.channel is! Microphone && !room.estado.noteMode,
      );
      await settle();

      expect(room.estado.unreachable, isFalse);
    });
  });

  test('6: a background door\'s fall cancels no foreground wait: a turn in '
      'flight while the Watch read fails still lands', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 60),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    harness.room.holdNextTurn();
    room.sala.conversaTap();
    await settle();
    room.sala.conversaTap();
    await waitFor('o turno sair', () => harness.room.turnsSent == 1);
    final replies = harness.voice.played.where((u) => u == turnoUrl).length;

    harness.room.failStateOnceWith = const NetworkFailed('sem rede');
    harness.network.reachable = false;
    await room.outOfReach('pela Watch, com o turno no ar');
    harness.room.finishHeldTurn();

    await waitFor(
      'a resposta do turno tocar',
      () => harness.voice.played.where((u) => u == turnoUrl).length > replies,
    );
  });

  test('7: out of reach with the microphone open, a tap closes it and keeps '
      'the take, and no retry fires from it', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 60),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    room.sala.conversaTap();
    await waitFor('o microfone abrir', () => room.estado.channel is Microphone);
    room.theNetworkFalls();
    await room.outOfReach('com o microfone aberto');
    final checks = harness.network.checks;
    int discards() =>
        harness.recorder.sounds.where((s) => s == 'recorder:discard').length;
    final discarded = discards();

    room.sala.conversaTap();
    await waitFor(
      'o microfone fechar',
      () => room.estado.channel is! Microphone,
    );
    await settle();

    expect(discards(), discarded);
    expect(File(harness.recorder.lastPath!).existsSync(), isTrue);
    expect(
      harness.recorder.deleted,
      isNot(contains(harness.recorder.lastPath)),
    );
    expect(
      harness.network.checks,
      checks,
      reason: 'o toque não é a retentativa',
    );
    expect(room.estado.voice, VoiceState.offline);
  });

  test('8: on return the pending request is re-sent exactly once, and the '
      'Outbox drains', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 60),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    room.sala.conversaTap();
    await waitFor('o microfone abrir', () => room.estado.channel is Microphone);
    room.theNetworkFalls();
    await room.outOfReach('com o microfone aberto');
    room.sala.conversaTap();
    await waitFor(
      'o microfone fechar',
      () => room.estado.channel is! Microphone,
    );
    final rehearsal = harness.recorder.aFile('parte-pendente');
    await harness.takes.enqueue(
      rehearsal,
      sessionId: room.estado.sessionId!,
      kind: 'ensaio',
      scope: _parte1,
    );
    final turnsBefore = harness.room.turnsSent;

    room.theNetworkReturns();

    await waitFor(
      'o turno guardado sair',
      () => harness.room.turnsSent > turnsBefore,
    );
    await waitFor(
      'a Outbox esvaziar',
      () async => (await harness.takes.pending()).isEmpty,
    );
    await settle(const Duration(milliseconds: 300));
    expect(harness.room.turnsSent, turnsBefore + 1);
  });

  test('8: a turn of a passage the team left is never re-sent on a later '
      'return', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _conversa(harness);
    harness.room
      ..holdNextTurn()
      ..failHeldTurnWith = const NetworkFailed('sem rede');
    harness.network.reachable = false;
    room.sala.conversaTap();
    await settle();
    room.sala.conversaTap();
    await waitFor('o turno sair', () => harness.room.turnsSent == 1);

    room.sala.leaveThePassage();
    await room.sala.abrirEscolha();
    harness.room.finishHeldTurn();
    await settle();
    harness.room.reachable = false;
    await harness.takes.enqueue(
      harness.recorder.aFile('parte-guardada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: _parte1,
    );
    await harness.takes.flush();
    await room.outOfReach('pela Outbox');
    room.theNetworkReturns();
    await waitFor('a sala voltar', () => !room.estado.unreachable);
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.turnsSent, 1);
  });

  group('8: the verdict and the approval that fell are asked again once on '
      'the return', () {
    Future<_Room> ready(SalaHarness harness) async {
      final room = await _aResumedBackTranslation(harness);
      harness.playback.finishPlayback();
      await waitFor(
        'a tradução poder pedir o veredito',
        () => room.estado.canFinishBackTranslation,
      );
      return room;
    }

    test('the verdict', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await ready(harness);
      harness.room.failFinishWith = const NetworkFailed('sem rede');
      harness.network.reachable = false;

      await room.sala.finishBackTranslation();
      await room.outOfReach('pelo veredito');
      final asked = harness.room.playedByTakeSent.length;
      harness.room.failFinishWith = null;
      room.theNetworkReturns();

      await waitFor(
        'o veredito ser pedido de novo',
        () => harness.room.playedByTakeSent.length > asked,
      );
      await settle(const Duration(milliseconds: 300));
      expect(harness.room.playedByTakeSent, hasLength(asked + 1));
      expect(room.estado.btPhase, isNot(BtPhase.thinking));
    });

    test('the approval', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
      final room = await ready(harness);
      await room.sala.finishBackTranslation();
      await waitFor(
        'a passagem ser conferida',
        () => room.estado.btPhase == BtPhase.conferida,
      );
      room.theNetworkFalls();

      await room.sala.aprovarRascunhoFinal();
      await room.outOfReach('pela aprovação');
      room.theNetworkReturns();

      await waitFor(
        'a aprovação ser pedida de novo',
        () => harness.room.releasesAsked.isNotEmpty,
      );
      await settle(const Duration(milliseconds: 300));
      expect(harness.room.releasesAsked, hasLength(1));
    });
  });

  test(
    '9: a 409 IDEMPOTENCY_KEY_IN_FLIGHT on a resend waits the backoff and '
    'sends again under the same key, with no strike and no stranding',
    () async {
      final harness = SalaHarness();
      final room = await _aResumedBackTranslation(harness);
      await _tellAStretchUpTo(room, const Duration(seconds: 12));
      room.theNetworkFalls();
      await room.sala.confirmarTraducao();
      await room.outOfReach('pelo trecho');
      harness.room.chunkAnswersFirst.add(_theKeyStillInFlight);
      final marks = room.estado.btChunkFailures;

      room.theNetworkReturns();

      await waitFor('o trecho pousar', () => room.estado.btTrechos.isNotEmpty);
      expect(harness.room.chunkKeys, hasLength(3));
      expect(harness.room.chunkKeys.toSet(), hasLength(1));
      expect(harness.room.segments, hasLength(1));
      expect(room.estado.btChunkFailures, marks);
      expect(room.estado.needsPerson, isFalse);
      expect(room.estado.btTraducaoPendente, isNull);
    },
  );

  test('9: a key that met IDEMPOTENCY_KEY_IN_FLIGHT until the watchdog gave up '
      'is the key the confirmation after the lift sends', () async {
    final harness = SalaHarness(
      busyCeiling: const Duration(milliseconds: 300),
      retryBackoff: const [Duration(milliseconds: 40)],
    );
    final room = await _aResumedBackTranslation(harness);
    await _tellAStretchUpTo(room, const Duration(seconds: 12));
    harness.room.chunkAnswersFirst.addAll(
      List.filled(40, _theKeyStillInFlight),
    );

    unawaited(room.sala.confirmarTraducao());
    await waitFor('o vigia desistir', () => room.estado.needsPerson);
    harness.room.chunkAnswersFirst.clear();
    await waitFor(
      'o pedido de pessoa pousar',
      () => harness.room.personsAsked > 0,
    );
    harness.room.theDeskAttended();
    await waitFor('a mesa levantar a parada', () => !room.estado.needsPerson);
    await room.sala.confirmarTraducao();
    await waitFor('o trecho pousar', () => harness.room.segments.isNotEmpty);

    expect(harness.room.chunkKeys.toSet(), hasLength(1));
  });

  test('8: a request that fell waits under a blocking halt, and goes out once '
      'under its key when the halt lifts', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _aResumedBackTranslation(harness);
    await _tellAStretchUpTo(room, const Duration(seconds: 12));
    room.theNetworkFalls();
    await room.sala.confirmarTraducao();
    await room.outOfReach('pelo trecho');
    room.sala.haltForABrokenBuild();

    room.theNetworkReturns();
    await waitFor('a sala voltar', () => !room.estado.unreachable);
    await settle(const Duration(milliseconds: 200));
    expect(
      harness.room.chunkKeys,
      hasLength(1),
      reason: 'nada sai sob a parada',
    );

    await waitFor(
      'o pedido de pessoa pousar',
      () => harness.room.personsAsked > 0,
    );
    harness.room.theDeskAttended();
    await waitFor('o trecho pousar', () => harness.room.segments.isNotEmpty);
    await settle(const Duration(milliseconds: 200));

    expect(harness.room.chunkKeys, hasLength(2));
    expect(harness.room.chunkKeys.toSet(), hasLength(1));
    expect(harness.room.segments, hasLength(1));
  });

  test('5: a pre-flight probe asks the room once with the probe already in '
      'flight', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);
    await room.sala.abrirEscolha();
    harness.network.reachable = false;
    await room.sala.goConversa(pericope: 'P01');
    await room.outOfReach('pela sonda da conversa');
    expect(room.estado.reach, RoomReach.roomSilent);
    harness.network.reachable = true;
    harness.network.holdNextCheck();
    room.sala.retryNow();
    await settle();
    final checks = harness.network.checks;

    room.sala.resolveWithPerson();
    await settle();
    expect(harness.network.checks, checks);
    harness.network.finishHeldCheck();

    await waitFor(
      'a conversa ser aberta de novo',
      () => harness.room.calls.contains('createSession'),
    );
  });

  test('5: a probe answer that two callers wait on is one fall, one rung of '
      'the ladder', () async {
    final harness = SalaHarness(
      retryBackoff: const [
        Duration(hours: 1),
        Duration(milliseconds: 100),
        Duration(hours: 1),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);
    harness.room.reachable = false;
    await room.sala.abrirEscolha();
    await room.outOfReach('pela roda');
    harness.room.reachable = true;
    harness.network.reachable = false;
    harness.network.holdNextCheck();
    room.sala.retryNow();
    await settle();
    unawaited(room.sala.goConversa(pericope: 'P01'));
    await settle();
    final checks = harness.network.checks;

    harness.network.finishHeldCheck();

    await waitFor(
      'a escada tentar de novo no degrau seguinte',
      () => harness.network.checks > checks,
      limit: const Duration(seconds: 1),
    );
  });

  test('5: the reads after a resumed telling-back name a recording the tablet '
      'does not hold', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits)
      ..room.failTakesWith = const NetworkFailed('sem rede');

    final room = await _aResumedBackTranslation(
      harness,
      told: const [
        SegmentView(
          segmentId: 'trecho-de-fora',
          takeId: 'gravacao-de-fora',
          startsMs: 0,
          endsMs: 6000,
        ),
      ],
    );

    await room.outOfReach('pela leitura das gravações da sala');
  });

  group('10: the offline notice plays once per outage, through the queue', () {
    test('falls after returns the room never answered say it once', () async {
      final harness = SalaHarness(
        watchesWithoutAHalt: true,
        settleDelay: const Duration(milliseconds: 60),
      );
      final room = await _conversa(harness);
      harness.room.reachable = false;
      await room.outOfReach('pela Watch');
      final probes = harness.network.checks;

      await waitFor(
        'a sala voltar e cair mais três vezes',
        () => harness.network.checks >= probes + 3,
      );
      await waitFor('o aviso tocar', () => room.offlineNotices > 0);

      expect(room.offlineNotices, 1);
    });

    test('under an open microphone it waits, and leaves the queue unsaid when '
        'the reach returns', () async {
      final harness = SalaHarness(
        watchesWithoutAHalt: true,
        settleDelay: const Duration(milliseconds: 60),
        retryBackoff: _aLadderThatWaits,
      );
      final room = await _conversa(harness);
      room.sala.conversaTap();
      await waitFor(
        'o microfone abrir',
        () => room.estado.channel is Microphone,
      );
      room.theNetworkFalls();
      await room.outOfReach('com o microfone aberto');
      await settle();
      expect(room.offlineNotices, 0, reason: 'nenhuma fala sobre o microfone');
      expect(
        room.estado.machine.queue.map((line) => line.kind),
        contains(LineKind.offlineNotice),
      );

      room.theNetworkReturns();
      await waitFor('a sala voltar', () => !room.estado.unreachable);
      expect(
        room.estado.machine.queue.map((line) => line.kind),
        isNot(contains(LineKind.offlineNotice)),
      );
      room.sala.conversaTap();
      await waitFor(
        'o microfone fechar',
        () => room.estado.channel is! Microphone,
      );
      await waitFor(
        'a resposta do turno tocar',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(room.offlineNotices, 0);
    });
  });

  group('11: a take stranded on a refusal with no code gets one more try on '
      'the return; one with a known code stays stranded', () {
    Future<_Room> refusedThenTheNetworkDropsAndReturns(String code) async {
      final harness = SalaHarness(
        watchesWithoutAHalt: true,
        settleDelay: const Duration(milliseconds: 60),
        retryBackoff: _aLadderThatWaits,
      );
      harness.room
        ..refuseTake = 'ensaio/$_parte1'
        ..refuseTakeCode = code;
      final room = await _conversa(harness);
      await _keepARehearsalPart(room);
      await waitFor(
        'a sala recusar a parte',
        () async => (await harness.takes.giveUps()).isNotEmpty,
      );
      harness.room.refuseTake = null;
      room.theNetworkFalls();
      await room.outOfReach('pela Watch');
      await harness.takes.enqueue(
        harness.recorder.aFile('outra-parte'),
        sessionId: room.estado.sessionId!,
        kind: 'ensaio',
        scope: KeptScope.parte(2),
      );
      room.theNetworkReturns();
      await waitFor(
        'a volta esvaziar a Outbox do que ela pode mandar',
        () => harness.room.takesKept.contains('ensaio/${KeptScope.parte(2)}'),
      );
      return room;
    }

    test('a codeless 400 is sent again and lands', () async {
      final room = await refusedThenTheNetworkDropsAndReturns('HTTP_400');

      expect(room.harness.room.takesKept, contains('ensaio/$_parte1'));
    });

    test('a known code stays stranded', () async {
      final room = await refusedThenTheNetworkDropsAndReturns(
        'UNKNOWN_REFERENCE',
      );

      expect(room.harness.room.takesKept, isNot(contains('ensaio/$_parte1')));
    });

    test('a manifest written before the code was kept still loads', () async {
      final home = Directory.systemTemp.createTempSync('sala-manifesto-antigo');
      addTearDown(() => home.deleteSync(recursive: true));
      final guardadas = Directory('${home.path}/guardadas')..createSync();
      File('${guardadas.path}/ensaio-p1.m4a').writeAsBytesSync([1, 2, 3]);
      File('${guardadas.path}/fila.json').writeAsStringSync(
        jsonEncode([
          {
            'id': 'linha-1',
            'name': 'ensaio-p1.m4a',
            'session_id': 'sessao-1',
            'kind': 'ensaio',
            'scope': 'parte-1',
            'attempts': takeUploadAttempts,
            'waits': 0,
          },
        ]),
      );
      final queue = TakeUploadQueue(room: FakeRoom(), home: () async => home);

      final rows = await queue.entries();

      expect(rows.single.id, 'linha-1');
      expect(rows.single.refusal, isNull);
      expect(await queue.giveUps(), hasLength(1));
    });
  });
}

class _RoomThatCannotReadTheTakeOnce extends FakeRoom {
  bool stumbled = false;

  @override
  Future<RoomAnswer<String>> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) {
    if (!stumbled) {
      stumbled = true;
      throw const FileSystemException('o disco piscou');
    }
    return super.sendTake(
      sessionId,
      audio,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
    );
  }
}
