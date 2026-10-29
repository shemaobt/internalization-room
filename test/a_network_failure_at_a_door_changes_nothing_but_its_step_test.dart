import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle, traduzirOApontadoDeNovo;
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

  void theNetworkFalls() => harness.room.reachable = false;

  void theKeyStaysInFlight() => harness.room.replaceAnswersFirst.addAll(
    List.filled(3, _theKeyStillInFlight),
  );

  void theNetworkReturns() => harness.room.reachable = true;

  List<String> get said => [...harness.voice.assets];
}

Future<_Room> _conversa(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

Future<void> _keepARehearsalPart(_Room room) async {
  room.sala.goEnsaio();
  room.sala.gravarACena(1);
  room.sala.gravarACena(1);
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
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  await room.sala.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor(
    'a tradução retomada pôr a parte no ar',
    () => room.estado.stage == SalaStage.retro && harness.playback.sounding,
  );
  return room;
}

Future<void> _tellAStretchUpTo(_Room room, Duration where) async {
  await theClipOpens(room.harness);
  room.harness.playback.at = where;
  room.sala.retroTap();
  room.sala.retroTap();
  await waitFor(
    'o microfone abrir',
    () => room.estado.btPhase == BtPhase.capturing,
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
  traduzirOApontadoDeNovo(room.container);
  room.sala.retroTap();
  await waitFor(
    'o microfone abrir no trecho',
    () => room.estado.btPhase == BtPhase.capturing,
  );
  return room;
}

void main() {
  test('1 (a): a rehearsal upload that fails on the network changes nothing: '
      'no person sign and nothing said', () async {
    final harness = SalaHarness(
      retryBackoff: _aLadderThatWaits,
      takesOverride: (room, home, recordings) => TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: recordings,
      ),
    )..room.unreachableTake = 'ensaio/$_parte1';
    final room = await _conversa(harness);

    await _keepARehearsalPart(room);
    final said = room.said;
    await waitFor(
      'a parte cair na rede',
      () => harness.room.calls.contains('sendTake'),
    );
    await settle();

    expect(room.estado.needsPerson, isFalse);
    expect(room.said, said);
  });
  test('a stretch told back as the network falls is a frase the room did not '
      'understand, and is never sent again once the network is back', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _aResumedBackTranslation(harness);
    await _tellAStretchUpTo(room, const Duration(seconds: 12));
    room.theNetworkFalls();

    room.sala.retroTap();
    await waitFor(
      'a frase voltar como não entendida',
      () => room.estado.wordlessTelling,
    );
    room.theNetworkReturns();
    await settle();

    expect(
      harness.room.chunkKeys,
      hasLength(1),
      reason:
          'ENG-1197: a frase que a rede perdeu é a não entendida dela, '
          'e só sai de novo quando a equipe a conta de novo',
    );
    expect(harness.room.segments, isEmpty);
    expect(room.estado.btTrechos, isEmpty);
    expect(room.estado.btTraducaoPendente, isNull);
  });

  test('3 (c): a stretch told again lost on the network lets its Step go, '
      'shows no person sign, says nothing and is never sent again', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _aFindingToTellAgain(harness);
    room.theNetworkFalls();
    final said = room.said;

    room.sala.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => room.estado.btPhase != BtPhase.thinking,
    );
    room.theNetworkReturns();
    await settle(const Duration(milliseconds: 300));

    expect(room.estado.awaitingTheGuide, isFalse);
    expect(room.estado.needsPerson, isFalse);
    expect(room.said, said);
    expect(harness.room.replaceKeys, hasLength(1));
    expect(harness.room.replacesAsked, isEmpty);
  });

  test(
    '3 (c): a stretch told again whose key was still in flight after three '
    'answers lets its Step go, says nothing and is never sent again',
    () async {
      final harness = SalaHarness();
      final room = await _aFindingToTellAgain(harness);
      room.theKeyStaysInFlight();
      final said = room.said;

      room.sala.retroTap();
      await waitFor(
        'a sala sair do pensando',
        () => room.estado.btPhase != BtPhase.thinking,
      );
      await settle(const Duration(milliseconds: 300));

      expect(room.estado.awaitingTheGuide, isFalse);
      expect(room.estado.needsPerson, isFalse);
      expect(room.said, said);
      expect(harness.room.replaceKeys, hasLength(3));
      expect(harness.room.replaceKeys.toSet(), hasLength(1));
      expect(harness.room.replacesAsked, isEmpty);
    },
  );

  test('4 (d): the Watch read that fails on the network changes nothing: no '
      'person sign, nothing said and the room at rest', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 400),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    final voice = room.estado.voice;
    final said = room.said;
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');

    await waitFor(
      'a Watch cair na rede',
      () => harness.room.failStateOnceWith == null,
    );
    await settle();

    expect(room.estado.needsPerson, isFalse);
    expect(room.estado.voice, voice);
    expect(room.said, said);
  });

  group('5: a network failure at a door off the way in changes nothing but '
      'its Step', () {
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
      await waitFor(
        'o pedido de uma pessoa cair na rede',
        () => harness.room.calls.contains('askForAPerson'),
      );
      final said = room.said;
      await settle();

      expect(room.estado.needsPerson, isTrue);
      expect(room.said, said);
    });

    test('the resume reads go silently back to the Choice at rest, keep the '
        'session, and the next open asks again', () async {
      final harness = SalaHarness(retryBackoff: _aLadderThatWaits)
        ..room.failTakesWith = const NetworkFailed('sem rede');
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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

      await room.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a Escolha abrir',
        () =>
            harness.room.calls.contains('takesOf') &&
            room.estado.stage == SalaStage.escolha,
      );
      await settle();

      expect(room.estado.needsPerson, isFalse);
      expect(room.estado.voice, VoiceState.invite);
      expect(harness.emAberto.rows['Ruth/P01/pt'], isNotNull);
      final asked = harness.room.calls.where((c) => c == 'takesOf').length;

      await room.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a retomada ser pedida de novo',
        () => harness.room.calls.where((c) => c == 'takesOf').length > asked,
      );
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
      final said = room.said;

      harness.room.dropCoverageStream(error: const NetworkFailed('sem rede'));
      await settle();

      expect(room.estado.needsPerson, isFalse);
      expect(room.said, said);
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
      await waitFor(
        'a releitura cair na rede',
        () => harness.room.failStateOnceWith == null,
      );
      await settle();

      expect(room.estado.needsPerson, isFalse);
      expect(room.estado.awaitingTheGuide, isFalse);
    });
  });

  test('6: a Watch read lost on the network while a turn is in flight shows '
      'no person sign, and the turn still lands', () async {
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
    await waitFor(
      'a Watch cair na rede, com o turno no ar',
      () => harness.room.failStateOnceWith == null,
    );
    expect(room.estado.needsPerson, isFalse);
    harness.room.finishHeldTurn();

    await waitFor(
      'a resposta do turno tocar',
      () => harness.voice.played.where((u) => u == turnoUrl).length > replies,
    );
  });

  test('7: with the network gone under an open microphone, a tap closes it, '
      'keeps the take and sends it once, and the look that finds nothing shows '
      'the person sign', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 60),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    room.sala.conversaTap();
    await waitFor('o microfone abrir', () => room.estado.channel is Microphone);
    room.theNetworkFalls();
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
      harness.room.calls.where((call) => call == 'sendTurn'),
      hasLength(1),
    );
    expect(room.estado.needsPerson, isTrue);
  });

  test('8: a take closed while the network is gone is never sent again, not '
      'once the network is back nor when the sign is tapped away', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      settleDelay: const Duration(milliseconds: 60),
      retryBackoff: _aLadderThatWaits,
    );
    final room = await _conversa(harness);
    room.sala.conversaTap();
    await waitFor('o microfone abrir', () => room.estado.channel is Microphone);
    room.theNetworkFalls();
    room.sala.conversaTap();
    await waitFor(
      'o microfone fechar',
      () => room.estado.channel is! Microphone,
    );
    await waitFor('a sala chamar uma pessoa', () => room.estado.needsPerson);
    final turnsBefore = harness.room.turnsSent;

    room.theNetworkReturns();
    room.sala.teamTapped();
    await waitFor('a parada sair', () => !room.estado.needsPerson);
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.turnsSent, turnsBefore);
  });

  test('8: a turn of a passage the team left is never re-sent when the team '
      'opens the passage again', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _conversa(harness);
    harness.room
      ..holdNextTurn()
      ..failHeldTurnWith = const NetworkFailed('sem rede');
    room.sala.conversaTap();
    await settle();
    room.sala.conversaTap();
    await waitFor('o turno sair', () => harness.room.turnsSent == 1);

    room.sala.leaveThePassage();
    await room.sala.abrirEscolha();
    harness.room.finishHeldTurn();
    await settle();
    await room.sala.goConversa(book: 'Ruth');
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.turnsSent, 1);
  });

  test('8: the approval lost on the network shows no person sign, says nothing '
      'and is never asked again', () async {
    final harness = SalaHarness(retryBackoff: _aLadderThatWaits);
    final room = await _aResumedBackTranslation(harness);
    harness.playback.finishPlayback();
    await waitFor(
      'a tradução poder pedir o veredito',
      () => room.estado.canFinishBackTranslation,
    );
    await room.sala.finishBackTranslation();
    await waitFor(
      'a passagem ser conferida',
      () => room.estado.btPhase == BtPhase.conferida,
    );
    room.theNetworkFalls();
    final said = room.said;

    await room.sala.aprovarRascunhoFinal();
    await waitFor(
      'a aprovação cair na rede',
      () => harness.room.calls.contains('approveRelease'),
    );
    room.theNetworkReturns();
    await settle(const Duration(milliseconds: 300));

    expect(room.estado.needsPerson, isFalse);
    expect(room.said, said);
    expect(harness.room.releasesAsked, isEmpty);
    expect(
      harness.room.calls.where((call) => call == 'approveRelease'),
      hasLength(1),
    );
  });

  test(
    '9: a key still in flight is sent three times and then the room shows no '
    'person sign, with the request kept',
    () async {
      final harness = SalaHarness();
      final room = await _aResumedBackTranslation(harness);
      await _tellAStretchUpTo(room, const Duration(seconds: 12));
      harness.room.chunkAnswersFirst.addAll(
        List.filled(10, _theKeyStillInFlight),
      );

      room.sala.retroTap();
      await waitFor(
        'a chave ainda em voo chegar ao teto',
        () => harness.room.chunkKeys.length == 3,
      );
      await settle(const Duration(milliseconds: 300));

      expect(harness.room.chunkKeys, hasLength(3));
      expect(harness.room.chunkKeys.toSet(), hasLength(1));
      expect(room.estado.needsPerson, isFalse);
      expect(room.estado.btTraducaoPendente, isNotNull);
    },
  );

  test('5: the reads after a resumed telling-back that name a recording the '
      'tablet does not hold, lost on the network, show no person sign and leave '
      'the telling-back going on', () async {
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

    await waitFor(
      'a leitura das gravações cair na rede',
      () => harness.room.calls.contains('takesOf'),
    );
    await settle();

    expect(room.estado.needsPerson, isFalse);
    expect(room.estado.stage, SalaStage.retro);
  });

  group('11: a take stranded on a refusal', () {
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
      final queue = TakeUploadQueue(
        room: FakeRoom(),
        home: () async => home,
        recordings: FakeRecorder.new,
      );

      final rows = await queue.entries();

      expect(rows.single.id, 'linha-1');
      expect(rows.single.refusal, isNull);
      expect(await queue.pending(), hasLength(1));
      expect(await queue.waiting(), isEmpty);
    });
  });
}
