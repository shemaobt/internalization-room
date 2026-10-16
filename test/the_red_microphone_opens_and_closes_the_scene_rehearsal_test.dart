import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show byLabel, enterThePassage, relaunch, settle, stateReads;

const _session = 'sessao-1';
const _articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);
final _redMicrophone = byLabel('ensaio da cena');

double _opacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: _redMicrophone, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

bool _deaf(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: _redMicrophone, matching: find.byType(IgnorePointer)),
    )
    .any((pointer) => pointer.ignoring);

bool _redMicrophoneIsSeen(WidgetTester tester) =>
    _redMicrophone.evaluate().isNotEmpty &&
    _opacity(tester) > 0 &&
    !_deaf(tester);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(beat);
  }
}

Future<(SalaHarness, ProviderContainer)> _inArticulation(
  WidgetTester tester, {
  bool watching = false,
}) async {
  final harness = SalaHarness(watchesWithoutAHalt: watching)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = _articulation;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

void _expectSeenAtRest(WidgetTester tester) => expect(
  _redMicrophoneIsSeen(tester),
  isTrue,
  reason: 'em repouso na cena o microfone vermelho aparece',
);

final class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;
}

Future<_Room> _atRest([SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  harness.room.nextMoment = _articulation;
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await room.sala.goConversa();
  await waitFor(
    'a sala abrir a conversa e se calar',
    () =>
        room.state.sessionId != null &&
        room.state.stage == SalaStage.conversa &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  return room;
}

Future<void> _theScreenOpens(_Room room) async {
  room.sala.openTheSceneRehearsal();
  await waitFor('a tela do ensaio da cena abrir', () {
    return room.state.stage == SalaStage.cena;
  });
  await settle();
}

Future<void> _theSceneMicrophoneOpens(_Room room) async {
  room.sala.sceneTap();
  await waitFor(
    'o microfone da cena abrir',
    () => switch (room.state.channel) {
      Microphone(owner: MicOwner.scene) => true,
      _ => false,
    },
  );
}

Future<void> _translateOpens(_Room room) => waitFor(
  'o ensaio abrir na tradução',
  () => room.state.scene.step == SceneStep.translate,
);

void main() {
  testWidgets(
    'a session at rest in Articulação shows the red microphone named and tooltipped «ensaio da cena»',
    (tester) async {
      await _inArticulation(tester);

      expect(_redMicrophone, findsOneWidget);
      expect(find.byTooltip('ensaio da cena'), findsOneWidget);
      _expectSeenAtRest(tester);
      expect(
        find.descendant(of: _redMicrophone, matching: find.byType(Text)),
        findsNothing,
        reason: 'o microfone vermelho não escreve palavra nenhuma',
      );
    },
  );

  group('no red microphone while the voice thinks, speaks or listens, or a '
      'raised-hand note is open', () {
    testWidgets('the voice thinks', (tester) async {
      final (harness, container) = await _inArticulation(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      _expectSeenAtRest(tester);
      harness.room.holdNextTurn();

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      notifier.conversaTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).voice == VoiceState.thinking,
      );

      expect(container.read(salaSessionProvider).voice, VoiceState.thinking);
      expect(_redMicrophoneIsSeen(tester), isFalse);
      harness.room.finishHeldTurn();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );
    });

    testWidgets('the voice speaks', (tester) async {
      final (harness, container) = await _inArticulation(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      _expectSeenAtRest(tester);
      harness.voice.holdNextLine();

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      notifier.conversaTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
      expect(_redMicrophoneIsSeen(tester), isFalse);
      harness.voice.finishHeldLine();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );
    });

    testWidgets('the conversation microphone listens', (tester) async {
      final (_, container) = await _inArticulation(tester);
      _expectSeenAtRest(tester);

      container.read(salaSessionProvider.notifier).conversaTap();
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).voice, VoiceState.listening);
      expect(_redMicrophoneIsSeen(tester), isFalse);
    });

    testWidgets('the hand arms a note', (tester) async {
      final (_, container) = await _inArticulation(tester);
      _expectSeenAtRest(tester);

      container.read(salaSessionProvider.notifier).handTap();
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).noteMode, isTrue);
      expect(_redMicrophoneIsSeen(tester), isFalse);
    });
  });

  testWidgets('no red microphone in the Panorama', (tester) async {
    final harness = SalaHarness()
      ..room.passages = const [
        Passagem(
          pericope: 'panorama',
          audioUrl: '/voice/panorama',
          kind: PassagemKind.panorama,
        ),
        Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
      ];
    final container = await pumpSala(tester, harness);
    addTearDown(() => closeTheRoom(container));
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.entrarNaOferecida();
    await _pumpUntil(tester, () {
      final state = container.read(salaSessionProvider);
      return state.station is Panorama &&
          state.panoramaSaid &&
          state.voice == VoiceState.invite;
    });
    await tester.pump(const Duration(milliseconds: 1500));

    expect(container.read(salaSessionProvider).station, isA<Panorama>());
    expect(_redMicrophoneIsSeen(tester), isFalse);
    notifier.openTheSceneRehearsal();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(salaSessionProvider).station, isA<Panorama>());
  });

  test(
    'the red microphone tapped over the facilitator\'s reply stops the reply and opens the scene rehearsal',
    () async {
      final room = await _atRest(
        SalaHarness(
          replies: const [HandReply(id: 'r1', audioUrl: '/r1')],
        ),
      );
      await waitFor(
        'a resposta chegar à mão',
        () => room.state.hasUnheardReply,
      );
      room.harness.voice.holdNextLine();
      room.sala.handTap();
      await waitFor(
        'a resposta tocar',
        () => room.state.playingReplyId != null,
      );
      final sounds = room.harness.sounds;
      final before = sounds.length;
      int? openedAt;
      room.container.listen<SalaStage>(
        salaSessionProvider.select((state) => state.stage),
        (_, stage) {
          if (stage == SalaStage.cena) openedAt ??= sounds.length;
        },
      );

      room.sala.openTheSceneRehearsal();

      expect(room.state.stage, SalaStage.cena);
      expect(openedAt, isNotNull);
      final stopAt = sounds.indexOf('voice:stop', before);
      expect(stopAt, isNonNegative, reason: 'a resposta não parou');
      expect(
        stopAt,
        lessThan(openedAt!),
        reason: 'a tela mudou antes de a resposta parar',
      );

      room.sala.leaveTheSceneRehearsal();
      await waitFor(
        'voltar à conversa',
        () => room.state.stage == SalaStage.conversa,
      );
      expect(
        room.state.hasUnheardReply,
        isTrue,
        reason: 'a resposta parada continua oferecida pela mão',
      );
    },
  );

  testWidgets('the scene rehearsal\'s screen never offers «Ouvir de novo»', (
    tester,
  ) async {
    await _inArticulation(tester);
    expect(byLabel('Ouvir de novo'), findsOneWidget);

    await tester.tap(_redMicrophone);
    await tester.pump(const Duration(milliseconds: 1500));

    expect(byLabel('Ouvir de novo'), findsNothing);
  });

  testWidgets(
    'while recording, the way back returns to the Conversation and the take is not kept',
    (tester) async {
      final (harness, container) = await _inArticulation(tester);
      await tester.tap(_redMicrophone);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(byLabel('Gravar o ensaio da cena'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(salaSessionProvider).channel,
        const Microphone(MicOwner.scene),
      );
      final before = harness.sounds.length;

      await tester.tap(byLabel('Voltar para a passagem atual'));
      await tester.pump(const Duration(milliseconds: 1500));

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(harness.sounds.skip(before), contains('recorder:discard'));
      expect(harness.room.scenesKept, isEmpty);
    },
  );

  group('the red microphone\'s gesture does nothing without a session or with '
      'a turn in flight', () {
    test('without a session', () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final room = _Room(harness, container);
      await room.sala.abrirEscolha();
      await settle();
      final station = room.state.station;

      room.sala.openTheSceneRehearsal();
      await settle();

      expect(room.state.sessionId, isNull);
      expect(room.state.station, station);
    });

    test('with a turn in flight', () async {
      final room = await _atRest();
      room.harness.room.holdNextTurn();
      room.sala.conversaTap();
      await settle();
      room.sala.conversaTap();
      await waitFor(
        'a voz pensar',
        () => room.state.voice == VoiceState.thinking,
      );

      room.sala.openTheSceneRehearsal();
      await settle();

      expect(room.state.station, isA<Canvas>());
      room.harness.room.finishHeldTurn();
    });
  });

  test(
    'opening the scene rehearsal over a half-spoken note discards it',
    () async {
      final room = await _atRest();
      room.sala.handTap();
      await settle();
      room.sala.conversaTap();
      await waitFor(
        'o microfone da nota abrir',
        () => switch (room.state.channel) {
          Microphone(owner: MicOwner.question) => true,
          _ => false,
        },
      );
      final before = room.harness.sounds.length;

      room.sala.openTheSceneRehearsal();
      await settle();

      expect(room.state.stage, SalaStage.cena);
      expect(room.state.noteMode, isFalse);
      expect(room.harness.sounds.skip(before), contains('recorder:discard'));
      expect(room.harness.inbox.questionsSent, isEmpty);
    },
  );

  testWidgets('no red microphone while a person is called', (tester) async {
    final (harness, container) = await _inArticulation(tester, watching: true);
    _expectSeenAtRest(tester);

    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    final reads = stateReads(harness);
    await _pumpUntil(
      tester,
      () => stateReads(harness) != reads,
      beat: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(_redMicrophoneIsSeen(tester), isFalse);
    closeTheRoom(container);
  });

  test('the way back finds the Conversation as it was', () async {
    final room = await _atRest(SalaHarness(watchesWithoutAHalt: true));
    final was = room.state;
    final calls = room.harness.room.calls.length;
    await _theScreenOpens(room);

    room.harness.room.readsDone = true;
    final reads = stateReads(room.harness);
    await waitFor(
      'a sala ler a sessão',
      () => stateReads(room.harness) > reads,
    );
    await settle();
    room.harness.room.readsDone = false;
    final notDone = stateReads(room.harness);
    await waitFor(
      'a sala ler a sessão sem o fim',
      () => stateReads(room.harness) > notDone + 1,
    );
    room.sala.leaveTheSceneRehearsal();
    await waitFor(
      'voltar à conversa',
      () => room.state.stage == SalaStage.conversa,
    );
    await settle();

    expect(room.state.sessionId, was.sessionId);
    expect(room.state.coverage, was.coverage);
    expect(room.state.moment, was.moment);
    expect(room.state.lastSpoken, was.lastSpoken);
    final asked = room.harness.room.calls.skip(calls);
    expect(asked, isNot(contains('createSession')));
    expect(asked, isNot(contains('openSession')));
    expect(room.state.redMicrophoneIsShown, isTrue);
    expect(
      room.state.endOfThePassage,
      isTrue,
      reason: 'o done lido na tela da cena acende o ponto na volta',
    );
  });

  test(
    'a session gone while on the scene rehearsal leaves nothing of its screen',
    () async {
      final room = await _atRest(SalaHarness(watchesWithoutAHalt: true));
      await _theScreenOpens(room);
      await _theSceneMicrophoneOpens(room);
      room.sala.sceneTap();
      await _translateOpens(room);

      room.harness.room.forgetTheSession(_session);
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.rehearsal, isNull);
      expect(room.state.scene.take, isNull);
    },
  );

  test(
    'another Station reached from the scene rehearsal leaves nothing of its screen',
    () async {
      final room = await _atRest();
      await _theScreenOpens(room);
      await _theSceneMicrophoneOpens(room);
      room.sala.sceneTap();
      await _translateOpens(room);

      room.sala.goEnsaio();
      await settle();

      expect(room.state.stage, SalaStage.ensaio);
      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.rehearsal, isNull);
      expect(room.state.scene.take, isNull);
    },
  );

  test('a relaunch never lands on the scene rehearsal', () async {
    final home = Directory.systemTemp.createTempSync('sala-sessao-atual');
    addTearDown(() => home.deleteSync(recursive: true));
    final harness = SalaHarness(
      currentSession: LedgerThatReadsLate(home: () async => home),
    );
    final container = harness.container();
    final room = _Room(harness, container);
    await enterThePassage(room.sala, () => room.state, 'P01');
    await waitFor(
      'a abertura ser dita',
      () =>
          room.state.voice == VoiceState.invite && room.state.sessionId != null,
    );
    await settle();
    await _theScreenOpens(room);
    final session = room.state.sessionId;

    final (again, next) = await relaunch(harness, container);
    final relaunched = _Room(again, next);
    await relaunched.sala.openTheRoom();
    await waitFor(
      'a equipe pousar na sessão',
      () =>
          relaunched.state.sessionId == session &&
          relaunched.state.voice == VoiceState.invite,
    );
    await settle();

    expect(relaunched.state.stage, SalaStage.conversa);
  });

  test(
    'a scene take recorded on the record step is kept by the room for this session and opens on translate',
    () async {
      final room = await _atRest();
      await _theScreenOpens(room);
      await _theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await _translateOpens(room);
      room.sala.playTheSceneRehearsal();
      await waitFor(
        'o ensaio da cena tocar',
        () => room.harness.playback.played.isNotEmpty,
      );

      expect(room.harness.room.scenesKept, [_session]);
      expect(room.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  group('a scene door that fails leaves the record step', () {
    const refused = Refused('HTTP_422');

    test('the keep refused', () async {
      final room = await _atRest();
      await _theScreenOpens(room);
      room.harness.room.failSceneWith = refused;
      await _theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await waitFor(
        'o take ser enviado',
        () => room.asked('keepSceneRehearsal') > 0,
      );
      await settle();

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.stage, SalaStage.cena);
    });

    test('an empty recording on stop', () async {
      final room = await _atRest();
      room.harness.recorder.returnsEmpty = true;
      await _theScreenOpens(room);
      await _theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await settle();

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.channel, isNot(isA<Microphone>()));
      expect(room.harness.room.scenesKept, isEmpty);
    });

    test('a gone session at a scene door leaves for the Choice', () async {
      final room = await _atRest();
      await _theScreenOpens(room);
      await _theSceneMicrophoneOpens(room);
      room.harness.room.failSceneWith = const SessionGone();

      room.sala.sceneTap();
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
    });
  });
}
