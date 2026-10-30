import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show byLabel, offered, enterThePassage, relaunch, settle, stateReads;
import 'support/temp.dart';

const _session = 'sessao-1';
const _placesUnknownLine =
    'as frases já traduzidas não estão neste computador — toquem em terminei '
    'para enviar, ou recomecem a tradução';
final _v4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final _redMicrophone = byLabel('ensaio da cena');

SceneFrase _frase(
  String id,
  int? startsMs,
  int? endsMs, {
  String? replacedBy,
}) => SceneFrase(
  fraseId: id,
  startsMs: startsMs,
  endsMs: endsMs,
  replacedBy: replacedBy,
);

SceneRehearsalRecord _rehearsal({
  String sessionId = _session,
  int n = 1,
  String? sentAt,
  String? afterRestart,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: sessionId,
  n: n,
  sentAt: sentAt,
  afterRestart: afterRestart,
  frases: frases,
);

/// Open the screen and tap the circle's place while what the open asked is still in
/// the air: nothing is on screen yet, and no microphone opens.
Future<void> _aTapWhileTheOpeningWaits(
  SceneRoom room, {
  required bool Function() until,
}) async {
  room.sala.openTheSceneRehearsal();
  await waitFor('a abertura esperar a sala', until);
  room.sala.sceneTap();
  await settle();
  expect(room.state.channel, isNot(isA<Microphone>()));
}

Future<void> _theWayBack(SceneRoom room) async {
  room.sala.leaveTheSceneRehearsal();
  await waitFor(
    'a conversa voltar ao convite',
    () =>
        room.state.stage == SalaStage.conversa &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
}

/// A second unsent rehearsal reopens with [hold] in the air; the team goes back and
/// opens the screen again, now with nothing unsent, and rests on the record step.
Future<void> _aLateAnswerOutlivesTheWayBack(
  SceneRoom room, {
  required void Function() hold,
  required bool Function() until,
}) async {
  await _theWayBack(room);
  room.harness.room.sceneRehearsals
    ..[0] = _rehearsal(
      sentAt: '2026-10-16T10:00:00+00:00',
      frases: [_frase('f1', 0, 4000)],
    )
    ..add(_rehearsal(n: 2, frases: [_frase('f1', 0, 4000)]));
  hold();
  room.sala.openTheSceneRehearsal();
  await waitFor('a reabertura ficar no ar', until);
  await _theWayBack(room);
  room.harness.room.sceneRehearsals[1] = _rehearsal(
    n: 2,
    sentAt: '2026-10-16T10:01:00+00:00',
    frases: [_frase('f1', 0, 4000)],
  );
  final asked = room.asked('sceneRehearsalsOf');
  room.sala.openTheSceneRehearsal();
  await waitFor(
    'a tela abrir de novo no passo de gravar',
    () =>
        room.asked('sceneRehearsalsOf') > asked &&
        room.state.scene.step == SceneStep.record &&
        room.asked('scenesOf') > 0,
  );
  await settle();
}

String _audioOf(String rehearsalId) =>
    '/api/internalization-room/sessions/$_session/scene-rehearsals/'
    '$rehearsalId/audio';

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
  final harness =
      SalaHarness(watchesWithoutAHalt: watching, filaEmMemoria: true)
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.nextMoment = articulation;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
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
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
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
    expect(harness.room.calls, isNot(contains('sceneRehearsalsOf')));
  });

  test(
    'the red microphone tapped over the facilitator\'s reply stops the reply and opens the scene rehearsal',
    () async {
      final room = await atRest(
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

  group(
    'an unsent scene rehearsal of this session reopens on its translate step',
    () {
      test(
        'an unsent one of this session: translate, and nothing plays',
        () async {
          final room = await atRest();
          room.harness.room.sceneRehearsals.add(
            _rehearsal(
              frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 9000)],
            ),
          );
          final before = room.harness.sounds.length;

          room.sala.openTheSceneRehearsal();
          await translateOpens(room);
          await settle();

          expect(room.state.stage, SalaStage.cena);
          expect(
            room.harness.sounds.skip(before),
            isNot(contains('playback:play')),
            reason: 'nada toca antes do toque',
          );
        },
      );

      test('a sent one of this session: the record step', () async {
        final room = await atRest();
        room.harness.room.sceneRehearsals.add(
          _rehearsal(sentAt: '2026-10-14T10:00:00Z'),
        );

        await theScreenOpens(room);

        expect(room.state.scene.step, SceneStep.record);
      });

      test(
        'an older unsent one under a newer sent one is abandoned: the record step',
        () async {
          final room = await atRest();
          room.harness.room.sceneRehearsals.addAll([
            _rehearsal(frases: [_frase('f1', 0, 4000)]),
            _rehearsal(n: 2, sentAt: '2026-10-14T10:00:00Z'),
          ]);

          await theScreenOpens(room);

          expect(room.state.scene.step, SceneStep.record);
        },
      );

      test(
        'an unsent one of another session of the passage: the record step',
        () async {
          final room = await atRest();
          room.harness.room.sceneRehearsals.add(
            _rehearsal(sessionId: 'sessao-9', frases: [_frase('f1', 0, 4000)]),
          );

          await theScreenOpens(room);

          expect(room.state.scene.step, SceneStep.record);
        },
      );
    },
  );

  test(
    'a scene take already on the tablet is reopened without a second download',
    () async {
      final room = await atRest();
      room.harness.room.sceneRehearsals.add(
        _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);
      room.sala.leaveTheSceneRehearsal();
      await settle();

      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a disk that cannot be read for the held take falls back to the download',
    () async {
      final room = await atRest();
      room.harness.recorder.heldAsFails = true;
      room.harness.room.sceneRehearsals.add(
        _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );

      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'an unsent scene rehearsal listed late never opens over the microphone: a '
    'tap while the list is in the air opens none, and a list that outlives the '
    'way back never draws over the take recorded next',
    () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..holdNextSceneList();
      await _aTapWhileTheOpeningWaits(
        room,
        until: () => room.asked('sceneRehearsalsOf') == 1,
      );
      room.harness.room.finishHeldSceneList();
      await translateOpens(room);

      await _aLateAnswerOutlivesTheWayBack(
        room,
        hold: room.harness.room.holdNextSceneList,
        until: () => room.asked('sceneRehearsalsOf') == 2,
      );
      await theSceneMicrophoneOpens(room);

      room.harness.room.finishHeldSceneList();
      await settle();

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.channel, const Microphone(MicOwner.scene));
    },
  );

  test('a take download that lands late never opens over the microphone: a tap '
      'while it is in the air opens none, and a download that outlives the way '
      'back never draws over the take recorded next', () async {
    final room = await atRest();
    room.harness.room
      ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
      ..holdNextClip();
    await _aTapWhileTheOpeningWaits(
      room,
      until: () => room.harness.room.clipsFetched.length == 1,
    );
    room.harness.room.finishHeldClip();
    await translateOpens(room);

    await _aLateAnswerOutlivesTheWayBack(
      room,
      hold: room.harness.room.holdNextClip,
      until: () => room.harness.room.clipsFetched.length == 2,
    );
    await theSceneMicrophoneOpens(room);

    room.harness.room.finishHeldClip();
    await settle();

    expect(room.state.scene.step, SceneStep.record);
    expect(room.state.channel, const Microphone(MicOwner.scene));
  });

  test(
    'a take download that outlives the way back leaves the take kept next on '
    'the screen',
    () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..holdNextClip();
      await _aTapWhileTheOpeningWaits(
        room,
        until: () => room.harness.room.clipsFetched.length == 1,
      );
      room.harness.room.finishHeldClip();
      await translateOpens(room);

      await _aLateAnswerOutlivesTheWayBack(
        room,
        hold: room.harness.room.holdNextClip,
        until: () => room.harness.room.clipsFetched.length == 2,
      );
      await theSceneMicrophoneOpens(room);
      room.sala.sceneTap();
      await translateOpens(room);

      room.harness.room.finishHeldClip();
      await settle();

      expect(room.state.scene.rehearsal?.rehearsalId, 'ensaio-da-cena-3');
    },
  );

  testWidgets('the scene rehearsal\'s screen never offers «Ouvir de novo»', (
    tester,
  ) async {
    await _inArticulation(tester);
    expect(byLabel('Ouvir de novo'), findsOneWidget);

    await tester.tap(_redMicrophone);
    await tester.pump(const Duration(milliseconds: 1500));

    expect(offered('Ouvir de novo'), findsNothing);
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

  test(
    'a scene rehearsal translated to frase 3 resumes after frase 3 on another tablet',
    () async {
      final room = await atRest();
      room.harness.room.sceneRehearsals.add(
        _rehearsal(
          frases: [
            _frase('f1', 0, 4000),
            _frase('f2', 4000, 9000),
            _frase('f3', 9000, 15000),
          ],
        ),
      );
      final before = room.harness.sounds.length;

      room.sala.openTheSceneRehearsal();
      await translateOpens(room);
      await settle();
      expect(
        room.harness.sounds.skip(before),
        isNot(contains('playback:play')),
      );

      room.sala.playTheSceneRehearsal();
      await waitFor(
        'o ensaio da cena tocar',
        () => room.harness.playback.played.isNotEmpty,
      );

      expect(
        room.harness.playback.playedFrom.last,
        const Duration(seconds: 15),
      );
      expect(
        room.harness.room.clipsFetched,
        contains(_audioOf('ensaio-da-cena-1')),
      );
    },
  );

  group('a last pause moved on another tablet is followed', () {
    Future<Duration> theFirstTapPlaysFrom(List<SceneFrase> frases) async {
      final room = await atRest();
      room.harness.room.sceneRehearsals.add(_rehearsal(frases: frases));
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);
      room.sala.playTheSceneRehearsal();
      await waitFor(
        'o ensaio da cena tocar',
        () => room.harness.playback.played.isNotEmpty,
      );
      return room.harness.playback.playedFrom.last;
    }

    test('moved later', () async {
      expect(
        await theFirstTapPlaysFrom([
          _frase('f1', 0, 4000),
          _frase('f2', 4000, 9000),
          _frase('f3', 9000, 15000, replacedBy: 'f4'),
          _frase('f4', 9000, 16200),
        ]),
        const Duration(milliseconds: 16200),
      );
    });

    test('moved earlier', () async {
      expect(
        await theFirstTapPlaysFrom([
          _frase('f1', 0, 4000),
          _frase('f2', 4000, 9000),
          _frase('f3', 9000, 15000, replacedBy: 'f4'),
          _frase('f4', 9000, 13800),
        ]),
        const Duration(milliseconds: 13800),
        reason: 'a pausa substituída não conta mais',
      );
    });
  });

  testWidgets(
    'a scene rehearsal whose frase places cannot be read offers only terminei, recomeçar and gravar de novo',
    (tester) async {
      final (harness, container) = await _inArticulation(tester);
      harness.room.sceneRehearsals.add(
        _rehearsal(frases: [_frase('f1', 0, 12000)]),
      );
      harness.playback.measured = const Duration(seconds: 10);

      await tester.tap(_redMicrophone);
      await _pumpUntil(
        tester,
        () =>
            container.read(salaSessionProvider).scene.step ==
            SceneStep.placesUnknown,
      );
      await tester.pump(const Duration(milliseconds: 1500));

      expect(byLabel(_placesUnknownLine), findsOneWidget);
      expect(byLabel('terminei'), findsOneWidget);
      expect(
        tester.widget<Semantics>(byLabel('terminei')).properties.enabled,
        isTrue,
      );
      expect(byLabel('recomeçar a tradução'), findsOneWidget);
      expect(byLabel('gravar o ensaio da cena de novo'), findsOneWidget);
      expect(byLabel('traduzir o ensaio da cena'), findsNothing);
      expect(byLabel('Gravar o ensaio da cena'), findsNothing);
      expect(offered('Ouvir de novo'), findsNothing);
    },
  );

  test('a frase with no place opens places unknown', () async {
    final room = await atRest();
    room.harness.room.sceneRehearsals.add(
      _rehearsal(frases: [_frase('f1', 0, 4000), _frase('f2', 4000, null)]),
    );

    room.sala.openTheSceneRehearsal();
    await waitFor(
      'as frases não poderem ser postas',
      () => room.state.scene.step == SceneStep.placesUnknown,
    );
  });

  group('the red microphone\'s gesture does nothing without a session or with '
      'a turn in flight', () {
    test('without a session', () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final room = SceneRoom(harness, container);
      await room.sala.abrirEscolha();
      await settle();
      final station = room.state.station;

      room.sala.openTheSceneRehearsal();
      await settle();

      expect(room.state.sessionId, isNull);
      expect(room.state.station, station);
      expect(room.asked('sceneRehearsalsOf'), 0);
    });

    test('with a turn in flight', () async {
      final room = await atRest();
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
      expect(room.asked('sceneRehearsalsOf'), 0);
      room.harness.room.finishHeldTurn();
    });
  });

  test(
    'opening the scene rehearsal over a half-spoken note discards it',
    () async {
      final room = await atRest();
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

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(_redMicrophoneIsSeen(tester), isFalse);
    closeTheRoom(container);
  });

  test('the way back finds the Conversation as it was', () async {
    final room = await atRest(SalaHarness(watchesWithoutAHalt: true));
    final was = room.state;
    final calls = room.harness.room.calls.length;
    await theScreenOpens(room);

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
      final room = await atRest(SalaHarness(watchesWithoutAHalt: true));
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);
      room.sala.sceneTap();
      await translateOpens(room);

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
      final room = await atRest();
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);
      room.sala.sceneTap();
      await translateOpens(room);

      room.sala.goEnsaio();
      await settle();

      expect(room.state.stage, SalaStage.ensaio);
      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.rehearsal, isNull);
      expect(room.state.scene.take, isNull);
    },
  );

  test(
    'a second tap on the scene circle while its recording is starting does nothing',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder.holdNextStart();

      room.sala.sceneTap();
      await settle(Duration.zero);
      final soundsAtTheStart = room.harness.sounds.length;
      room.sala.sceneTap();
      room.harness.recorder.finishStart();
      await settle();

      expect(
        room.state.channel,
        isA<Microphone>().having((mic) => mic.owner, 'owner', MicOwner.scene),
        reason:
            'o segundo toque chegou antes de o gravador abrir; fechá-lo ali '
            'guarda uma gravação que nunca começou',
      );
      expect(room.harness.sounds.skip(soundsAtTheStart), isEmpty);
      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.take, isNull);
      expect(room.state.scene.keep, isNot(isA<Keeping>()));
      expect(await room.harness.takes.entries(), isEmpty);
      expect(room.harness.room.scenesKept, isEmpty);
    },
  );

  test('a relaunch never lands on the scene rehearsal', () async {
    final home = aTempDir('sala-sessao-atual');
    final harness = SalaHarness(
      currentSession: LedgerThatReadsLate(home: () async => home),
    );
    final container = harness.container();
    final room = SceneRoom(harness, container);
    await enterThePassage(room.sala, () => room.state, 'P01');
    await waitFor(
      'a abertura ser dita',
      () =>
          room.state.voice == VoiceState.invite && room.state.sessionId != null,
    );
    await settle();
    await theScreenOpens(room);
    final session = room.state.sessionId;

    final (again, next) = await relaunch(harness, container);
    final relaunched = SceneRoom(again, next);
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
      final room = await atRest();
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await translateOpens(room);
      room.sala.playTheSceneRehearsal();
      await waitFor(
        'o ensaio da cena tocar',
        () => room.harness.playback.played.isNotEmpty,
      );

      expect(room.harness.room.scenesKept, [_session]);
      expect(room.harness.playback.playedFrom.last, Duration.zero);
      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        isEmpty,
        reason: 'o take gravado neste tablet não é baixado de novo',
      );

      room.sala.leaveTheSceneRehearsal();
      await settle();
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        isEmpty,
        reason: 'reaberto, o take da própria equipe também não é baixado',
      );
    },
  );

  test(
    'a keep answered after the team left still leaves the take under the rehearsal\'s name',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);
      room.harness.room.holdNextKeep();
      room.sala.sceneTap();
      await waitFor(
        'o take ser enviado',
        () => room.asked('keepSceneRehearsal') > 0,
      );

      room.sala.leaveTheSceneRehearsal();
      room.harness.room.finishHeldKeep();
      await settle();
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        isEmpty,
      );
    },
  );

  group('recomeçar sends a fresh attempt that closes the current one', () {
    const current = '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b';

    Future<SceneRoom> inPlacesUnknown() async {
      final room = await atRest(SalaHarness(restartWake: Duration.zero));
      room.harness.room.sceneRehearsals.add(
        _rehearsal(afterRestart: current, frases: [_frase('f1', 0, 12000)]),
      );
      room.harness.playback.measured = const Duration(seconds: 10);
      room.sala.openTheSceneRehearsal();
      await waitFor(
        'as frases não poderem ser postas',
        () => room.state.scene.step == SceneStep.placesUnknown,
      );
      return room;
    }

    test('each tap mints a v4 attempt that closes the current one', () async {
      final room = await inPlacesUnknown();
      room.harness.room.failSceneWith = const NetworkFailed('sem rede');

      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'o recomeço subir',
        () => room.harness.room.restartsSent.isNotEmpty,
      );
      await settle();
      room.harness.room.failSceneWith = null;
      await restartTheTranslationInTwoTaps(room);
      await translateOpens(room);

      final sent = room.harness.room.restartsSent;
      expect(sent, hasLength(2));
      expect(sent.map((restart) => restart.closes), [current, current]);
      expect(sent[0].attempt, matches(_v4));
      expect(sent[1].attempt, matches(_v4));
      expect(sent[0].attempt, isNot(sent[1].attempt));
    });

    test(
      'two re-reads answering out of order leave the screen on sent',
      () async {
        final room = await inPlacesUnknown();
        room.harness.room
          ..refuseRestartWith = RefusalCode.restartOutOfOrder
          ..holdNextSceneList();
        final read = room.asked('sceneRehearsalsOf');

        await restartTheTranslationInTwoTaps(room);
        await waitFor(
          'a primeira releitura ficar no ar',
          () =>
              room.asked('sceneRehearsalsOf') == read + 1 &&
              !room.state.scene.waiting,
        );
        room.harness.room
          ..refuseRestartWith = RefusalCode.sceneRehearsalSent
          ..sceneRehearsals[0] = _rehearsal(
            afterRestart: current,
            sentAt: '2026-10-14T10:00:00Z',
          );
        await restartTheTranslationInTwoTaps(room);
        await waitFor(
          'o ensaio aparecer enviado',
          () => room.state.scene.step == SceneStep.sent,
        );

        room.harness.room.finishHeldSceneList();
        await settle();

        expect(room.state.scene.step, SceneStep.sent);
      },
    );

    test('a rehearsal already sent is shown as sent and never halts', () async {
      final room = await inPlacesUnknown();
      room.harness.room
        ..refuseRestartWith = RefusalCode.sceneRehearsalSent
        ..sceneRehearsals[0] = _rehearsal(
          afterRestart: current,
          sentAt: '2026-10-14T10:00:00Z',
        );

      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'o ensaio aparecer enviado',
        () => room.state.scene.step == SceneStep.sent,
      );

      expect(room.state.needsPerson, isFalse);
      expect(room.state.stage, SalaStage.cena);
    });

    test(
      'a restart answered after «gravar de novo» leaves the record step',
      () async {
        final room = await inPlacesUnknown();
        room.harness.room.holdNextRestart();

        await restartTheTranslationInTwoTaps(room);
        await waitFor(
          'o recomeço subir',
          () => room.harness.room.restartsSent.isNotEmpty,
        );
        room.sala.recordTheSceneAgain();
        room.harness.room.finishHeldRestart();
        await settle();

        expect(room.state.scene.step, SceneStep.record);
        expect(room.state.scene.rehearsal, isNull);
      },
    );

    test(
      'a rehearsal the room no longer knows never ends the session',
      () async {
        final room = await inPlacesUnknown();
        final session = room.state.sessionId;
        room.harness.room
          ..refuseRestartWith = RefusalCode.notFound
          ..sceneRehearsals.clear();

        await restartTheTranslationInTwoTaps(room);
        await waitFor(
          'o recomeço subir',
          () => room.harness.room.restartsSent.isNotEmpty,
        );
        await settle();

        expect(room.state.sessionId, session);
        expect(room.state.stage, SalaStage.cena);
        expect(room.state.scene.step, SceneStep.placesUnknown);
      },
    );

    test('arming twice and firing sends one restart', () async {
      final room = await inPlacesUnknown();
      room.harness.room.holdNextRestart();

      await restartTheTranslationInTwoTaps(room);
      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'o recomeço subir',
        () => room.harness.room.restartsSent.isNotEmpty,
      );
      await settle();

      expect(room.harness.room.restartsSent, hasLength(1));
      room.harness.room.finishHeldRestart();
    });

    test('a gone session on recomeçar leaves for the Choice', () async {
      final room = await inPlacesUnknown();
      room.harness.room.forgetTheSession(_session);

      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
    });

    test('a late re-read of the list never replaces a newer screen', () async {
      const landed = 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11';
      final room = await inPlacesUnknown();
      room.harness.room
        ..refuseRestartWith = RefusalCode.restartOutOfOrder
        ..holdNextSceneList();
      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'a lista ser relida',
        () => room.asked('sceneRehearsalsOf') == 2,
      );
      room.sala.leaveTheSceneRehearsal();
      room.harness.room
        ..refuseRestartWith = null
        ..sceneRehearsals[0] = _rehearsal(afterRestart: landed);
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      room.harness.room.finishHeldSceneList();
      await settle();

      expect(room.state.scene.step, SceneStep.translate);
      expect(room.state.scene.rehearsal?.afterRestart, landed);
    });

    test(
      'a restart the room took without this tablet hearing it is read again',
      () async {
        const landed = 'c3d1a1f0-5b7e-4c1a-9a43-0d6e3f2b8a11';
        final room = await inPlacesUnknown();
        room.harness.room
          ..refuseRestartWith = RefusalCode.restartOutOfOrder
          ..sceneRehearsals[0] = _rehearsal(afterRestart: landed);

        await restartTheTranslationInTwoTaps(room);
        await translateOpens(room);

        expect(room.state.scene.rehearsal?.afterRestart, landed);
        expect(room.state.needsPerson, isFalse);
      },
    );
  });

  group('a scene door that fails leaves the record step', () {
    const refused = Refused('HTTP_422');

    test('the list refused, three times over, never calls a person', () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..failSceneWith = refused;

      for (var vez = 1; vez <= 3; vez++) {
        room.sala.openTheSceneRehearsal();
        await waitFor(
          'a lista ser pedida $vez vezes',
          () => room.asked('sceneRehearsalsOf') == vez,
        );
        await settle();
        expect(room.state.stage, SalaStage.cena);
        expect(room.state.scene.step, SceneStep.record);
        room.sala.leaveTheSceneRehearsal();
        await settle();
      }

      expect(room.state.needsPerson, isFalse);
    });

    test('the scene take\'s audio refused', () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..failClipWith = refused;

      await theScreenOpens(room);
      await waitFor(
        'o áudio do ensaio ser pedido',
        () => room.harness.room.clipsFetched.isNotEmpty,
      );
      await settle();

      expect(room.state.scene.step, SceneStep.record);
    });

    test('the keep refused', () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.room.failSceneWith = refused;
      await theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await waitFor(
        'o take ser enviado',
        () => room.asked('keepSceneRehearsal') > 0,
      );
      await settle();

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.stage, SalaStage.cena);
      expect(
        room.state.scene.keep,
        isA<NotKept>(),
        reason:
            'ENG-1347: o take recusado fica esperando no tablet, com o retry',
      );
    });

    test('a gone session at the take\'s audio leaves for the Choice', () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..holdNextClip();
      room.sala.openTheSceneRehearsal();
      await waitFor(
        'o take ser pedido',
        () => room.harness.room.clipsFetched.isNotEmpty,
      );

      room.harness.room
        ..forgetTheSession(_session)
        ..finishHeldClip();
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
    });

    test('an empty scene take fetched', () async {
      final room = await atRest();
      room.harness.room
        ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 4000)]))
        ..sceneAudio = Uint8List(0);

      await theScreenOpens(room);
      await waitFor(
        'o áudio do ensaio ser pedido',
        () => room.harness.room.clipsFetched.isNotEmpty,
      );
      await settle();

      expect(room.state.scene.step, SceneStep.record);
    });

    test('an empty recording on stop', () async {
      final room = await atRest();
      room.harness.recorder.returnsEmpty = true;
      await theScreenOpens(room);
      await theSceneMicrophoneOpens(room);

      room.sala.sceneTap();
      await settle();

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.channel, isNot(isA<Microphone>()));
      expect(room.harness.room.scenesKept, isEmpty);
    });

    test('a network failure on recomeçar stays on places unknown', () async {
      final room = await atRest(SalaHarness(restartWake: Duration.zero));
      room.harness.room.sceneRehearsals.add(
        _rehearsal(frases: [_frase('f1', 0, 12000)]),
      );
      room.harness.playback.measured = const Duration(seconds: 10);
      room.sala.openTheSceneRehearsal();
      await waitFor(
        'as frases não poderem ser postas',
        () => room.state.scene.step == SceneStep.placesUnknown,
      );
      room.harness.room.failSceneWith = const NetworkFailed('sem rede');

      await restartTheTranslationInTwoTaps(room);
      await waitFor(
        'o recomeço subir',
        () => room.harness.room.restartsSent.isNotEmpty,
      );
      await settle();

      expect(room.state.scene.step, SceneStep.placesUnknown);
    });

    test('a gone session at a scene door leaves for the Choice', () async {
      final room = await atRest();
      room.harness.room.failSceneWith = const SessionGone();

      room.sala.openTheSceneRehearsal();
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
    });
  });
}
