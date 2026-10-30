import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_client.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;

  void theNetworkFalls() => harness.room.reachable = false;

  void theNetworkReturns() => harness.room.reachable = true;
}

Future<_Room> _onTheCanvas(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

Future<void> _theTeamSpeaks(_Room room) async {
  room.sala.conversaTap();
  await waitFor(
    'o microfone abrir na conversa',
    () => room.state.voice == VoiceState.listening,
  );
  room.sala.conversaTap();
}

Future<void> _theRoomRests(_Room room) async {
  await waitFor(
    'a sala descansar',
    () => !room.state.awaitingTheGuide && room.state.machine.inFlight == null,
  );
  await settle();
}

/// One take on a fake clock, sent the moment the clock starts. Copied from
/// `one_look_decides_a_turn_the_tablet_gave_up_on_test.dart`: fixtures never travel
/// between modules, only the shape does.
void _aTakeOnTheClock(
  SalaHarness harness,
  void Function(FakeRoom room) arrange,
  void Function(FakeAsync clock, SalaSessionState Function() read) check,
) {
  fakeAsync((clock) {
    ProviderContainer? container;
    unawaited(inConversa(harness).then((opened) => container = opened));
    clock.elapse(const Duration(seconds: 1));
    addTearDown(() => container?.dispose());
    arrange(harness.room);
    final sala = container!.read(salaSessionProvider.notifier);
    sala.conversaTap();
    clock.elapse(const Duration(milliseconds: 100));
    sala.conversaTap();
    clock.flushMicrotasks();
    check(clock, () => container!.read(salaSessionProvider));
  });
}

const _articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);

/// An unsent scene rehearsal with two frases translated. Copied from
/// `the_scene_rehearsal_lists_its_rehearsals_and_terminei_sends_one_test.dart`.
final _aSceneRehearsalToSend = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: 'sessao-1',
  n: 1,
  recordedAt: DateTime(2026, 10, 15, 14, 5),
  frases: const [
    SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
    SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 9000),
  ],
);

Future<_Room> _onTheSceneScreen(SalaHarness harness) async {
  harness.room
    ..nextMoment = _articulation
    ..sceneRehearsals.add(_aSceneRehearsalToSend)
    ..sceneAudio = Uint8List.fromList([1, 2, 3]);
  harness.playback.measured = const Duration(seconds: 20);
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await room.sala.goConversa(book: 'Ruth');
  await waitFor(
    'a sala abrir a conversa e se calar',
    () =>
        room.state.sessionId != null &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  room.sala.openTheSceneRehearsal();
  await waitFor(
    'a tela do ensaio da cena abrir na tradução',
    () =>
        room.state.stage == SalaStage.cena &&
        room.state.scene.rehearsal?.n == 1 &&
        room.state.scene.step == SceneStep.translate &&
        !room.state.scene.waiting,
  );
  await settle();
  return room;
}

Future<void> _terminei(_Room room) async {
  room.sala.sendTheSceneRehearsal();
  await waitFor('o ensaio ir', () => room.harness.room.scenesSent.isNotEmpty);
}

Future<_Room> _aResumedBackTranslation(SalaHarness harness) async {
  final casa = Directory.systemTemp.createTempSync('sala-1355');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness.playback
    ..length = const Duration(seconds: 30)
    ..measured = const Duration(seconds: 30);
  harness.room.retroSoFar = const BackTranslationProgress(segments: []);
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-1',
        ),
      ],
    ),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await room.sala.openTheRoom();
  await intoTheBackTranslation(room.sala, () => room.state);
  await waitFor(
    'a tradução pôr a parte no ar',
    () => harness.playback.sounding,
  );
  return room;
}

Future<_Room> _aCheckedPassage(SalaHarness harness) async {
  final room = await _aResumedBackTranslation(harness);
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução poder pedir o veredito',
    () => room.state.canFinishBackTranslation,
  );
  await room.sala.finishBackTranslation();
  await waitFor(
    'a passagem ser conferida',
    () => room.state.btPhase == BtPhase.conferida,
  );
  return room;
}

const _thePanorama = Passagem(
  pericope: 'OV-Ruth',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
  book: 'Ruth',
);

Future<_Room> _onThePanorama(SalaHarness harness) async {
  harness.room.passages = [_thePanorama, ...harness.room.passages];
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await enterThePanorama(room.sala, () => room.state);
  await waitFor(
    'o Panorama descansar no convite',
    () =>
        room.state.panoramaSessionId != null &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  return room;
}

/// P01 opened, spoken into once and left, so that opening it again resumes its session.
Future<_Room> _aPassageToResume(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await enterThePassage(room.sala, () => room.state, 'P01');
  await waitFor(
    'a passagem descansar no convite',
    () =>
        room.state.sessionId != null &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await _theTeamSpeaks(room);
  await _theRoomRests(room);
  room.sala.leaveThePassage();
  await waitFor('a Escolha abrir', () => room.state.entriesOpen);
  container.invalidate(salaSessionProvider);
  await room.sala.openTheRoom();
  await waitFor('a sala refeita abrir a Escolha', () => room.state.entriesOpen);
  return room;
}

final _theCanonIsGone = RoomClient.classify(
  409,
  utf8.encode(
    jsonEncode({
      'detail': 'no kept canon for pin 2026-10-01',
      'code': 'CANON_NOT_KEPT',
    }),
  ),
  asksForTheSession: true,
)!;

void main() {
  test('the voice\'s service down: the acknowledgement plays, then the person '
      'sign; no line, nothing resent', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.failTurnsWith = const NetworkFailed('HTTP 502');
    final fixedLinesBefore = harness.voice.fixedLines.length;
    final playedBefore = harness.voice.played.length;
    final assetsBefore = harness.voice.assets.length;

    await _theTeamSpeaks(room);
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);
    await settle();

    expect(
      harness.voice.fixedLines.skip(fixedLinesBefore).map((line) => line.$1),
      [isIn(instantAckLines)],
    );
    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(harness.voice.assets.skip(assetsBefore), isEmpty);

    harness.room.failTurnsWith = null;
    room.sala.teamTapped();
    await waitFor('o sinal sair', () => !room.state.needsPerson);
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.turnsSent, 1);
  });

  test('a turn whose answer never arrives within its wait, and the look finds '
      'nothing: the person sign', () {
    _aTakeOnTheClock(
      SalaHarness(busyCeiling: const Duration(seconds: 30)),
      (room) => room.holdNextTurn(),
      (clock, read) {
        clock.elapse(const Duration(seconds: 29));
        expect(read().needsPerson, isFalse);

        clock.elapse(const Duration(seconds: 2));
        expect(read().needsPerson, isTrue);
      },
    );
  });

  test('the same, but the look finds the reply that landed: the reply plays, '
      'no sign', () {
    final harness = SalaHarness(busyCeiling: const Duration(seconds: 30));
    _aTakeOnTheClock(
      harness,
      (room) => room
        ..holdNextTurn()
        ..turnsLandBeforeTheyFail = true,
      (clock, read) {
        final played = harness.voice.played.length;
        clock.elapse(const Duration(seconds: 31));

        expect(harness.voice.played.skip(played), contains(turnoUrl));
        expect(read().needsPerson, isFalse);
      },
    );
  });

  test('a spoken turn answered without a reply brings the person sign at '
      'once', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.answersTurnsWithoutAReply = true;

    await _theTeamSpeaks(room);
    await waitFor('a sala responder', () => harness.room.turnsSent == 1);
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);

    expect(harness.room.turnIdsLookedAt, isEmpty);
  });

  test('a spoken turn refused TURN_COLLISION brings the person sign and no '
      'line', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.failTurnsWith = const Refused('TURN_COLLISION');
    final playedBefore = harness.voice.played.length;
    final assetsBefore = harness.voice.assets.length;

    await _theTeamSpeaks(room);
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);
    await settle();

    expect(harness.voice.played.skip(playedBefore), isEmpty);
    expect(harness.voice.assets.skip(assetsBefore), isEmpty);
  });

  test('a reply sound that fails to load twice brings the sign; once brings '
      'nothing', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.voice.failsToLoad[turnoUrl] = 1;

    await _theTeamSpeaks(room);
    await _theRoomRests(room);
    expect(room.state.needsPerson, isFalse);

    harness.voice.refuses.add(turnoUrl);
    await _theTeamSpeaks(room);
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);
  });

  group('the microphone failing to start', () {
    test('once brings nothing; twice in a row brings the sign', () async {
      final harness = SalaHarness();
      final room = await _onTheCanvas(harness);
      harness.recorder.startThrows = true;

      room.sala.conversaTap();
      await settle();
      expect(room.state.needsPerson, isFalse);

      room.sala.conversaTap();
      await waitFor('o sinal da pessoa', () => room.state.needsPerson);
    });

    test(
      'after a start that worked, one more failure brings nothing',
      () async {
        final harness = SalaHarness();
        final room = await _onTheCanvas(harness);
        harness.recorder.startThrows = true;
        room.sala.conversaTap();
        await settle();
        harness.recorder.startThrows = false;
        await _theTeamSpeaks(room);
        await _theRoomRests(room);

        harness.recorder.startThrows = true;
        room.sala.conversaTap();
        await settle();

        expect(room.state.needsPerson, isFalse);
      },
    );
  });

  test('the facilitator resets the passage: the screen goes calmly back to the '
      'passage menu, no sign', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final room = await _onTheCanvas(harness);

    harness.room.forgetTheSession(room.state.sessionId!);
    await waitFor(
      'a sala voltar à Escolha',
      () => room.state.stage == SalaStage.escolha,
    );
    await settle();

    expect(room.state.needsPerson, isFalse);
  });

  group('an opening that cannot be drafted: the quiet invite, no sign', () {
    Future<_Room> enterP01(SalaHarness harness) async {
      final container = harness.container();
      addTearDown(container.dispose);
      final room = _Room(harness, container);
      await enterThePassage(room.sala, () => room.state, 'P01');
      await waitFor(
        'a abertura ser pedida',
        () => harness.room.turnIdsAsked.isNotEmpty,
      );
      await waitFor(
        'a sala descansar no convite',
        () =>
            room.state.voice == VoiceState.invite &&
            !room.state.awaitingTheGuide,
      );
      await settle();
      return room;
    }

    for (final (how, arrange) in <(String, void Function(FakeRoom))>[
      (
        'refused',
        (room) => room.failHeldTurnWith = const Refused('BAD_REQUEST'),
      ),
      (
        'refused with a code that once stopped the room',
        (room) =>
            room.failHeldTurnWith = const Refused(RefusalCode.deviceRevoked),
      ),
      (
        'answered without a reply',
        (room) => room.answersTurnsWithoutAReply = true,
      ),
    ]) {
      test(how, () async {
        final harness = SalaHarness();
        arrange(harness.room);

        final room = await enterP01(harness);

        expect(room.state.needsPerson, isFalse);
        expect(room.state.awaitingTheGuide, isFalse);
      });
    }
  });

  group('a scene rehearsal the room refuses with a named reason: the scene '
      'screen stays, no sign', () {
    for (final code in [
      RefusalCode.sceneRehearsalSent,
      RefusalCode.deviceRevoked,
    ]) {
      test(code, () async {
        final harness = SalaHarness();
        final room = await _onTheSceneScreen(harness);
        harness.room.sendRefusalsFirst.add(code);

        await _terminei(room);
        await _theRoomRests(room);
        await settle(const Duration(milliseconds: 300));

        expect(room.state.stage, SalaStage.cena);
        expect(room.state.needsPerson, isFalse);
      });
    }
  });

  test('an empty back-translation take: no sign and nothing left '
      'waiting', () async {
    final harness = SalaHarness();
    final room = await _aResumedBackTranslation(harness);
    await theClipOpens(harness);
    harness.recorder.returnsEmpty = true;
    harness.playback.at = const Duration(seconds: 2);

    room.sala.retroTap();
    room.sala.retroTap();
    await waitFor(
      'a captura abrir',
      () => room.state.btPhase == BtPhase.capturing,
    );
    room.sala.retroTap();
    await waitFor(
      'a captura fechar',
      () => room.state.btPhase == BtPhase.playing,
    );
    await settle();

    expect(room.state.needsPerson, isFalse);
    expect(room.state.awaitingTheGuide, isFalse);
  });

  group('a network failure with no turn, off a way in: no sign', () {
    const ladder = [Duration(milliseconds: 20)];
    const tenLadders = Duration(milliseconds: 200);

    void expectNothingChanged(_Room room) {
      expect(room.state.needsPerson, isFalse);
    }

    test('the Watch\'s read', () async {
      final harness = SalaHarness(
        watchesWithoutAHalt: true,
        retryBackoff: ladder,
      );
      final room = await _onTheCanvas(harness);
      final reads = stateReads(harness);
      harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      await waitFor('a Watch ler', () => stateReads(harness) > reads);
      await settle();
      expectNothingChanged(room);

      await settle(tenLadders);

      expectNothingChanged(room);
    });

    test('the Outbox\'s upload', () async {
      final harness = SalaHarness(retryBackoff: ladder)
        ..room.unreachableTake = 'ensaio/${KeptScope.parte(1)}';
      final room = await _onTheCanvas(harness);
      room.sala.goEnsaio();
      room.sala.gravarACena(1);
      room.sala.gravarACena(1);
      await settle();
      room.sala.takeKeep();
      await waitFor('a parte ficar pendente', () => room.state.unsentTakes > 0);
      await settle();
      expectNothingChanged(room);

      await settle(tenLadders);

      expectNothingChanged(room);
    });

    test('the Approval', () async {
      final harness = SalaHarness(retryBackoff: ladder);
      final room = await _aCheckedPassage(harness);
      room.theNetworkFalls();
      await room.sala.aprovarRascunhoFinal();
      await settle();
      expectNothingChanged(room);
      room.theNetworkReturns();

      await settle(tenLadders);

      expectNothingChanged(room);
      expect(harness.room.releasesAsked, isEmpty);
    });
  });

  test('three refusals of another request bring no sign', () async {
    final harness = SalaHarness()
      ..room.failBooksWith = Refused(RefusalCode.unnamed(500));
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);

    await room.sala.abrirEscolha();
    for (var refusal = 1; refusal < 3; refusal++) {
      await waitFor(
        'a roda ser recusada',
        () =>
            room.asked('servedBooks') == refusal &&
            !room.state.awaitingTheGuide,
      );
      room.sala.escolhaTap();
    }
    await waitFor('a terceira recusa', () => room.asked('servedBooks') == 3);
    await settle();

    expect(room.state.needsPerson, isFalse);
  });

  test('a wheel with nothing but Panoramas brings no sign', () async {
    final harness = SalaHarness()
      ..room.passages = const [
        Passagem(
          pericope: 'OV-Ruth',
          audioUrl: '/voice/panorama',
          kind: PassagemKind.panorama,
          book: 'Ruth',
        ),
      ];
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);

    await room.sala.abrirEscolha();
    await waitFor('a roda aparecer', () => room.state.naRoda != null);
    await settle();

    expect(room.state.needsPerson, isFalse);
    expect(room.state.naRoda, isNotEmpty);
    expect(room.state.entriesOpen, isTrue);
  });

  test('an empty wheel brings no sign, and the touch reads it again', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);
    await room.sala.abrirEscolha();
    await waitFor('a roda vazia aparecer', () => room.state.naRoda != null);
    await settle();
    final reads = room.asked('servedBooks');

    room.sala.escolhaTap();
    await waitFor(
      'a roda ser lida de novo',
      () => room.asked('servedBooks') > reads,
    );

    expect(room.state.needsPerson, isFalse);
  });

  test('a Session read in which the server says a person is needed raises no '
      'sign', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final room = await _onTheCanvas(harness);
    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;

    final reads = stateReads(harness);
    await waitFor('a Watch ler', () => stateReads(harness) > reads);
    await settle();

    expect(room.state.needsPerson, isFalse);
  });

  test('a scene rehearsal given up whose look finds nothing keeps its screen; '
      'back on the Canvas, the sign', () async {
    final harness = SalaHarness();
    final room = await _onTheSceneScreen(harness);
    harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');

    await _terminei(room);
    await waitFor(
      'a sala olhar a sessão',
      () => harness.room.turnIdsLookedAt.isNotEmpty,
    );
    await _theRoomRests(room);

    expect(room.state.stage, SalaStage.cena);
    expect(room.state.needsPerson, isFalse);

    room.sala.leaveTheSceneRehearsal();
    await waitFor(
      'a conversa voltar',
      () => room.state.stage == SalaStage.conversa,
    );
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);
  });

  test('a scene rehearsal answered without a reply keeps its screen; back on '
      'the Canvas, the sign', () async {
    final harness = SalaHarness();
    final room = await _onTheSceneScreen(harness);
    harness.room.answersTurnsWithoutAReply = true;

    await _terminei(room);
    await _theRoomRests(room);
    await settle(const Duration(milliseconds: 1600));

    expect(room.state.stage, SalaStage.cena);
    expect(room.state.needsPerson, isFalse);

    room.sala.leaveTheSceneRehearsal();
    await waitFor(
      'a conversa voltar',
      () => room.state.stage == SalaStage.conversa,
    );
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);
  });

  group('a resume the room fails to answer goes calmly back to the passage '
      'menu', () {
    for (final (how, failure) in <(String, RoomFailure)>[
      ('refused', Refused(RefusalCode.unnamed(500))),
      ('lost on the network', const NetworkFailed('sem rede')),
    ]) {
      test(how, () async {
        final harness = SalaHarness();
        final room = await _aPassageToResume(harness);
        final reads = room.asked('createSession');
        harness.room.failCreateOnceWith = failure;

        await enterThePassage(room.sala, () => room.state, 'P01');
        await waitFor(
          'a leitura da retomada falhar',
          () => room.asked('createSession') > reads,
        );
        await waitFor(
          'a Escolha voltar',
          () => room.state.stage == SalaStage.escolha && room.state.entriesOpen,
        );

        expect(room.state.needsPerson, isFalse);
      });
    }
  });

  test('a resume whose canon is gone goes back to the passage menu with no '
      'sign, no sound and no call', () async {
    final harness = SalaHarness();
    final room = await _aPassageToResume(harness);
    final reads = room.asked('createSession');
    final played = harness.voice.played.length;
    final fixedLines = harness.voice.fixedLines.length;
    final assets = harness.voice.assets.length;
    harness.room.failCreateOnceWith = _theCanonIsGone;

    await enterThePassage(room.sala, () => room.state, 'P01');
    await waitFor(
      'a leitura da retomada falhar',
      () => room.asked('createSession') > reads,
    );
    await waitFor(
      'a Escolha voltar',
      () => room.state.stage == SalaStage.escolha && room.state.entriesOpen,
    );
    await settle();

    expect(
      room.state.needsPerson,
      isFalse,
      reason: 'uma sessão sem cânone na retomada não é um dos casos dela',
    );
    expect(harness.voice.played.skip(played), isEmpty);
    expect(harness.voice.fixedLines.skip(fixedLines), isEmpty);
    expect(harness.voice.assets.skip(assets), isEmpty);
    expect(harness.room.personsAsked, 0);
  });

  test('two resumes in a row whose canon is gone keep the stored passage, '
      'counted on no strike', () async {
    final harness = SalaHarness();
    final room = await _aPassageToResume(harness);
    final stored = harness.emAberto.rows['Ruth/P01/pt']?.sessionId;
    for (var tap = 0; tap < 2; tap++) {
      final reads = room.asked('createSession');
      harness.room.failCreateOnceWith = _theCanonIsGone;
      await enterThePassage(room.sala, () => room.state, 'P01');
      await waitFor(
        'a leitura da retomada falhar',
        () => room.asked('createSession') > reads,
      );
      await waitFor(
        'a Escolha voltar',
        () => room.state.stage == SalaStage.escolha && room.state.entriesOpen,
      );
    }
    await settle();

    expect(stored, isNotNull);
    expect(
      harness.emAberto.rows['Ruth/P01/pt']?.sessionId,
      stored,
      reason:
          'duas leituras recusadas pelo cânone perdido esqueciam a passagem '
          'guardada, como se a equipe tivesse falhado duas vezes',
    );
  });

  test('a resume that lands clears the count of failed resumes, so only '
      'consecutive failures forget the passage', () async {
    final harness = SalaHarness();
    final casa = Directory.systemTemp.createTempSync('sala-1355-ensaio');
    addTearDown(() => casa.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);
    await room.sala.abrirEscolha();
    Future<void> aResumeIsRefused() async {
      harness.room.failCreateOnceWith = Refused(RefusalCode.unnamed(500));
      await room.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a retomada recusada deixar a passagem',
        () =>
            harness.room.failCreateOnceWith == null &&
            !room.state.awaitingTheGuide,
      );
    }

    await aResumeIsRefused();
    await room.sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a retomada pousar na conversa',
      () => room.state.station is Canvas && !room.state.awaitingTheGuide,
    );
    room.sala.leaveThePassage();
    await waitFor('a Escolha abrir', () => room.state.entriesOpen);
    await aResumeIsRefused();

    expect(harness.emAberto.rows['Ruth/P01/pt']?.sessionId, 'sessao-antiga');
  });

  test('a failed resume is logged at the resume\'s door', () async {
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final harness = SalaHarness();
    final room = await _aPassageToResume(harness);
    harness.room.failCreateOnceWith = Refused(RefusalCode.unnamed(500));

    await enterThePassage(room.sala, () => room.state, 'P01');
    await waitFor(
      'a Escolha voltar',
      () => room.state.stage == SalaStage.escolha && room.state.entriesOpen,
    );

    expect(
      logged,
      contains(allOf(contains(Door.resume.name), contains('HTTP_500'))),
    );
  });

  test('the reply\'s sound failing twice is logged as decided', () async {
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.voice.refuses.add(turnoUrl);

    await _theTeamSpeaks(room);
    await waitFor('o sinal da pessoa', () => room.state.needsPerson);

    expect(logged, contains(allOf(contains('2'), contains('RoomRaisedAHalt'))));
  });

  test('the reply\'s sound failing late, under a sign already standing, is not '
      'counted again', () async {
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    final playedBefore = harness.voice.played.length;
    harness.voice.aoFalar = () {
      if (harness.voice.played.length > playedBefore) {
        harness.voice
          ..aoFalar = null
          ..holdNextLine();
      }
    };
    await _theTeamSpeaks(room);
    await waitFor(
      'a resposta tocar',
      () => harness.voice.played.length > playedBefore,
    );
    room.sala.haltForABrokenBuild();
    await waitFor('o sinal', () => room.state.needsPerson);

    harness.voice
      ..succeeds = false
      ..finishHeldLine();
    await settle();

    expect(room.state.needsPerson, isTrue);
    expect(logged, isNot(contains(contains('o som da fala não carregou'))));
  });

  test('a wheel whose read never answers rests at the invite at the busy '
      'ceiling, the Choice being a way in', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 300))
      ..room.holdNextBooks();
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);

    unawaited(room.sala.abrirEscolha());
    await waitFor('a roda ser pedida', () => room.state.awaitingTheGuide);

    await waitFor(
      'a sala descansar no convite',
      () =>
          !room.state.awaitingTheGuide && room.state.voice == VoiceState.invite,
    );
    expect(room.state.needsPerson, isFalse);
  });

  test('a resume into the Back-translation the room refuses goes '
      'calmly back to the passage menu', () async {
    final harness = SalaHarness()
      ..room.failCreateOnceWith = Refused(RefusalCode.unnamed(500));
    final casa = Directory.systemTemp.createTempSync('sala-1355-retro');
    addTearDown(() => casa.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
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
      'a Escolha voltar',
      () => room.state.stage == SalaStage.escolha && room.state.entriesOpen,
    );

    expect(room.asked('createSession'), 1);
    expect(room.state.needsPerson, isFalse);
  });

  test('a launch with the room out of reach rests at the invite with no sign, '
      'and the next tap fills the Choice', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final room = _Room(harness, container);
    room.theNetworkFalls();

    await room.sala.abrirEscolha();
    await settle();
    expect(room.state.voice, VoiceState.invite);
    expect(room.state.naRoda, isNull);
    expect(room.state.needsPerson, isFalse);
    room.theNetworkReturns();

    room.sala.escolhaTap();

    await waitFor('a roda aparecer', () => room.state.naRoda != null);
    expect(room.state.needsPerson, isFalse);
  });

  test('a decided failure is logged with its door and its reason', () async {
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final harness = SalaHarness();
    final room = await _aCheckedPassage(harness);
    harness.room.failReleaseWith = Refused(RefusalCode.unnamed(500));

    await room.sala.aprovarRascunhoFinal();
    await settle();

    expect(
      logged,
      contains(allOf(contains(Door.step.name), contains('HTTP_500'))),
    );
  });

  group('the Panorama', () {
    test('a Panorama turn answered without a reply brings the person '
        'sign', () async {
      final harness = SalaHarness();
      final room = await _onThePanorama(harness);
      harness.room.answersTurnsWithoutAReply = true;

      room.sala.panoramaTap();
      await waitFor(
        'o microfone abrir no Panorama',
        () => room.state.voice == VoiceState.listening,
      );
      room.sala.panoramaTap();

      await waitFor('o sinal da pessoa', () => room.state.needsPerson);
    });

    test('a Panorama whose owed opening is answered without a reply rests at '
        'the invite', () async {
      final harness = SalaHarness()..room.answersTurnsWithoutAReply = true;

      final room = await _onThePanorama(harness);

      expect(room.state.needsPerson, isFalse);
    });
  });

  test('an empty rehearsal take: no sign and no halt', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    room.sala.goEnsaio();
    harness.recorder.returnsEmpty = true;

    room.sala.gravarACena(1);
    await settle();
    room.sala.gravarACena(1);
    await settle();
    room.sala.takeKeep();
    await settle();

    expect(room.state.needsPerson, isFalse);
    expect(room.state.awaitingTheGuide, isFalse);
  });

  test('a back-translation opened with no rehearsal part: no sign and no '
      'halt', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);

    room.sala.startRetro();
    await settle();

    expect(room.state.needsPerson, isFalse);
    expect(room.state.awaitingTheGuide, isFalse);
  });

  group('a refused approval', () {
    test('whose hole has no door returns the team to the Back-translation as '
        'it stood before «terminei»', () async {
      final harness = SalaHarness();
      final room = await _aCheckedPassage(harness);
      harness.room.releaseBlockers = ['coverage_floor_not_met'];

      await room.sala.aprovarRascunhoFinal();
      await settle();

      expect(room.state.needsPerson, isFalse);
      expect(room.state.canFinishBackTranslation, isTrue);
    });

    test('refused with a code returns the team to the Back-translation as it '
        'stood before «terminei»', () async {
      final harness = SalaHarness();
      final room = await _aCheckedPassage(harness);
      harness.room.failReleaseWith = Refused(RefusalCode.unnamed(422));

      await room.sala.aprovarRascunhoFinal();
      await settle();

      expect(room.state.needsPerson, isFalse);
      expect(room.state.canFinishBackTranslation, isTrue);
    });

    test('on a session whose canon is gone says her «não deu para conferir '
        'agora», with no sign, no sound and nothing sent again', () async {
      final harness = SalaHarness();
      final room = await _aCheckedPassage(harness);
      final played = harness.voice.played.length;
      final fixedLines = harness.voice.fixedLines.length;
      final assets = harness.voice.assets.length;
      harness.room.failReleaseWith = _theCanonIsGone;

      await room.sala.aprovarRascunhoFinal();
      await settle();
      await settle();

      expect(
        room.state.btRecusa,
        CheckRefusal.checkUnavailable,
        reason:
            'para qualquer outra recusa da aprovação o app dela mostra «não '
            'deu para conferir agora — tentem de novo»',
      );
      expect(room.state.needsPerson, isFalse);
      expect(harness.voice.played.skip(played), isEmpty);
      expect(harness.voice.fixedLines.skip(fixedLines), isEmpty);
      expect(harness.voice.assets.skip(assets), isEmpty);
      expect(harness.room.personsAsked, 0);
      expect(
        harness.room.releasesAsked,
        hasLength(1),
        reason: 'só o toque da equipe pede a aprovação; nada a repete sozinho',
      );
    });
  });

  test('a refused Watch read changes nothing, and the next beat reads '
      'again', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final room = await _onTheCanvas(harness);
    final reads = stateReads(harness);
    harness.room.failStateOnceWith = Refused(RefusalCode.unnamed(500));

    await waitFor('a Watch ler', () => stateReads(harness) > reads);
    await waitFor('a Watch ler de novo', () => stateReads(harness) > reads + 1);

    expect(room.state.needsPerson, isFalse);
    expect(room.state.voice, VoiceState.invite);
  });

  test('a scene rehearsal sent again that lands forgets the sign held for the '
      'Canvas', () async {
    final harness = SalaHarness();
    final room = await _onTheSceneScreen(harness);
    harness.room.failHeldTurnWith = const NetworkFailed('a rede caiu');
    await _terminei(room);
    await waitFor(
      'a sala olhar a sessão',
      () => harness.room.turnIdsLookedAt.isNotEmpty,
    );
    await _theRoomRests(room);

    room.sala.sendTheSceneRehearsal();
    await waitFor(
      'a conversa voltar',
      () => room.state.stage == SalaStage.conversa,
    );
    await settle();

    expect(room.state.needsPerson, isFalse);
  });
}
