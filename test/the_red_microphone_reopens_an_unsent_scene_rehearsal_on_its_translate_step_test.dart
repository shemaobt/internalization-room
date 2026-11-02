import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

const _session = 'sessao-1';
const _offline = NetworkFailed('sem rede');
const _question = 'Qual cena vocês vão ensaiar?';
const _record = 'Gravar o ensaio da cena';
const _placesUnknownLine =
    'as frases já traduzidas não estão neste computador — toquem em terminei '
    'para enviar, ou recomecem a tradução';

const _scenes = [
  Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
  Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
  Scene(sceneId: 'S3', title: 'Segundo apelo e a separação'),
];

const _length = Duration(seconds: 9);

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? scene,
  String? sentAt,
  int? durationMs = 9000,
  List<SceneFrase>? frases,
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  scene: scene,
  sentAt: sentAt,
  durationMs: durationMs,
  frases: frases ?? [_frase('f1', 0, 4000)],
  contentType: 'audio/wav',
  verified: true,
);

SceneRehearsalRecord _sent({
  int n = 1,
  String? scene,
  int? durationMs = 9000,
}) => _rehearsal(
  n: n,
  scene: scene,
  durationMs: durationMs,
  sentAt: '2026-10-16T10:0$n:00+00:00',
);

/// Watches the screen from the open on: whether the record step showed once the open
/// laid its loading state.
final class _TheRecordStep {
  bool _opened = false;
  bool shown = false;

  void open() => _opened = shown = false;

  void sees(SalaSessionState state) {
    if (state.scenes is ScenesAwaited) _opened = true;
    if (_opened && _onTheRecordStep(state)) shown = true;
  }
}

bool _onTheRecordStep(SalaSessionState state) =>
    state.station is SceneRehearsal &&
    state.scene.step == SceneStep.record &&
    state.scenes is! ScenesAwaited;

bool _shows(String label) => byLabel(label).evaluate().isNotEmpty;

/// The scene screen pumped over a session at rest in the Conversation, with the
/// passage's own scene ask failed so the open's ask is the one that answers.
final class _Screen {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;
  int _callsBefore = 0;
  final recordStep = _TheRecordStep();

  _Screen(this.tester, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int asked(String call) =>
      room.calls.skip(_callsBefore).where((asked) => asked == call).length;

  Future<void> pump([Duration by = Duration.zero]) => tester.pump(by);

  Future<void> until(
    String what,
    bool Function() done, {
    Duration limit = const Duration(seconds: 3),
  }) async {
    const beat = Duration(milliseconds: 10);
    var waited = Duration.zero;
    while (!done()) {
      if (waited >= limit) fail('esperei $limit e $what não aconteceu');
      await tester.pump(beat);
      waited += beat;
    }
  }

  bool get loading =>
      state.stage == SalaStage.cena &&
      state.scene.step == SceneStep.record &&
      !_shows(_question) &&
      !_shows(_record);

  void open() {
    _callsBefore = room.calls.length;
    recordStep.open();
    sala.openTheSceneRehearsal();
  }

  Future<void> translates(int n) => until(
    'o ensaio $n abrir na tradução',
    () =>
        state.scene.step == SceneStep.translate &&
        state.scene.rehearsal?.n == n,
  );

  Future<void> leaves() async {
    sala.leaveTheSceneRehearsal();
    await until(
      'a conversa voltar',
      () => state.stage == SalaStage.conversa && state.station is Canvas,
    );
    await pump(const Duration(milliseconds: 1500));
  }
}

Future<_Screen> _atRest(
  WidgetTester tester, {
  List<SceneRehearsalRecord> rehearsals = const [],
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P02', audioUrl: '/voice/p02')]
    ..room.nextMoment = articulation
    ..room.passageScenes = _scenes
    ..room.sceneRehearsals.addAll(rehearsals)
    ..room.sceneAudio = aSpokenWav(length: _length)
    ..room.failScenesWith = _offline;
  harness.playback.measured = _length;
  addTearDown(harness.room.finishHeldClip);
  addTearDown(harness.playback.finishHeldMeasurement);
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final screen = _Screen(tester, harness, container);
  container.listen<SalaSessionState>(salaSessionProvider, (_, next) {
    screen.recordStep.sees(next);
  });
  await screen.sala.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(screen.sala.goConversa(book: 'Ruth', pericope: 'P02'));
  await screen.until(
    'a sala se calar no convite',
    () =>
        screen.state.sessionId != null &&
        screen.state.voice == VoiceState.invite &&
        !screen.state.awaitingTheGuide,
    limit: const Duration(seconds: 20),
  );
  await tester.pump(const Duration(milliseconds: 1500));
  harness.room.failScenesWith = null;
  return screen;
}

/// The red microphone over a room at rest, recording whether the record step ever showed
/// from the open on.
Future<SceneRoom> _aRoom({
  List<SceneRehearsalRecord> rehearsals = const [],
  List<Scene> scenes = const [],
}) async {
  final room = await atRest(
    SalaHarness(filaEmMemoria: true)..room.passageScenes = scenes,
  );
  room.harness.room
    ..sceneRehearsals.addAll(rehearsals)
    ..sceneAudio = aSpokenWav(length: _length);
  room.harness.playback.measured = _length;
  addTearDown(room.harness.room.finishHeldClip);
  return room;
}

_TheRecordStep _recordStepFrom(SceneRoom room, void Function() open) {
  final recordStep = _TheRecordStep()..open();
  final listening = room.container.listen<SalaSessionState>(
    salaSessionProvider,
    (_, next) => recordStep.sees(next),
  );
  addTearDown(listening.close);
  open();
  return recordStep;
}

Future<void> _translates(SceneRoom room, int n) => waitFor(
  'o ensaio $n abrir na tradução',
  () =>
      room.state.scene.step == SceneStep.translate &&
      room.state.scene.rehearsal?.n == n &&
      !room.state.scene.waiting,
);

Future<void> _theTakeLands(SceneRoom room) => waitFor(
  'o take chegar à tela',
  () => room.state.scene.take != null && !room.state.scene.waiting,
);

Future<void> _leaves(SceneRoom room) async {
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

Future<void> _onTheRecordStepAgain(SceneRoom room) => waitFor(
  'a tela abrir no passo de gravar',
  () => _onTheRecordStep(room.state),
);

int _takesAskedOf(SceneRoom room, int n) => room.harness.room.clipsFetched
    .where((url) => url.endsWith('/scene-rehearsals/ensaio-da-cena-$n/audio'))
    .length;

/// Rehearsal [n] opened online with its take landed on the tablet, then left.
Future<SceneRoom> _keptOnTheTablet({
  int n = 1,
  List<SceneRehearsalRecord> alsoListed = const [],
  List<Scene> scenes = const [],
}) async {
  final room = await _aRoom(
    rehearsals: [
      ...alsoListed,
      _rehearsal(n: n),
    ],
    scenes: scenes,
  );
  room.sala.openTheSceneRehearsal();
  await _translates(room, n);
  await _theTakeLands(room);
  await _leaves(room);
  return room;
}

/// Rehearsal 1 on its translate step with a frase the room refused while it was sending
/// the rehearsal, so the tablet still holds it; then the room is unreachable, the team
/// leaves and opens the red microphone again.
Future<SceneRoom> _aHeldFraseOffline() async {
  final room = await _aRoom(rehearsals: [_rehearsal()]);
  room.sala.openTheSceneRehearsal();
  await _translates(room, 1);
  await _theTakeLands(room);
  room.sala.playTheSceneRehearsal();
  await waitFor(
    'o ensaio da cena tocar',
    () => room.state.channel is PartPlaying,
  );
  room.harness.playback.at = const Duration(seconds: 6);
  room.sala.tapTheTranslateCircle();
  await waitFor('a pausa ser marcada', () => room.state.scene.pausa != null);
  room.sala.tapTheTranslateCircle();
  await waitFor(
    'o microfone da frase abrir',
    () => room.state.channel == const Microphone(MicOwner.frase),
  );
  room.harness.room.sceneAnswersFirst.add(
    const Refused(RefusalCode.sceneRehearsalSending),
  );
  room.sala.tapTheTranslateCircle();
  await waitFor(
    'a frase ficar guardada no tablet',
    () => room.state.sceneFraseHeld && !room.state.scene.waiting,
  );
  await settle();
  room.harness.room.reachable = false;
  await _leaves(room);
  room.sala.openTheSceneRehearsal();
  await _translates(room, 1);
  return room;
}

void main() {
  group('the open', () {
    testWidgets(
      '1. an unsent scene rehearsal whose take is slow opens on its translate '
      'step before its take arrives, and stays there past 4 s',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room.holdNextClip();

        screen.open();
        await screen.translates(1);
        await screen.pump(const Duration(seconds: 10));

        expect(screen.state.scene.step, SceneStep.translate);
        expect(screen.state.scene.rehearsal?.n, 1);
        expect(screen.recordStep.shown, isFalse);

        screen.room.finishHeldClip();
        await screen.until(
          'o take chegar',
          () => screen.state.scene.take != null,
        );

        expect(screen.state.scene.step, SceneStep.translate);
        expect(screen.recordStep.shown, isFalse);
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      "2. while the room's list is in the air the screen shows only its loading "
      'state, past 4 s, then opens the unsent rehearsal on its translate step',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room.holdNextSceneList();

        screen.open();
        await screen.pump(const Duration(seconds: 6));

        expect(screen.loading, isTrue);

        screen.room.finishHeldSceneList();
        await screen.translates(1);

        expect(screen.recordStep.shown, isFalse);
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      '3. an unsent scene rehearsal opens on its translate step while the scene '
      'list is still in the air, and the late scene list leaves it there',
      (tester) async {
        final screen = await _atRest(
          tester,
          rehearsals: [_rehearsal(scene: 'S2')],
        );
        screen.room.holdNextScenes();

        screen.open();
        await screen.translates(1);

        expect(screen.asked('scenesOf'), 1);

        screen.room.finishHeldScenes();
        await screen.pump(const Duration(milliseconds: 500));

        expect(screen.state.scene.step, SceneStep.translate);
        expect(screen.state.scene.rehearsal?.n, 1);

        screen.sala.recordTheSceneAgain();
        await screen.pump(const Duration(milliseconds: 100));

        expect(byLabel(_question), findsOneWidget);
        expect(screen.asked('scenesOf'), 1);
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      '4. an unsent scene rehearsal whose frase has no place in the room\'s '
      'length opens on places unknown before its take arrives',
      (tester) async {
        final screen = await _atRest(
          tester,
          rehearsals: [
            _rehearsal(durationMs: 10000, frases: [_frase('f1', 0, 12000)]),
          ],
        );
        screen.room.holdNextClip();

        screen.open();
        await screen.until(
          'o ensaio abrir sem lugares',
          () => screen.state.scene.step == SceneStep.placesUnknown,
        );
        await screen.pump(const Duration(milliseconds: 500));

        expect(screen.state.scene.take, isNull);
        expect(find.text(_placesUnknownLine), findsOneWidget);
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      '5. a take the room refuses leaves the rehearsal on its translate step',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room.failClipWith = const Refused('HTTP_422');

        screen.open();
        await screen.translates(1);
        await screen.pump(const Duration(seconds: 2));

        expect(screen.state.scene.step, SceneStep.translate);
        expect(screen.state.scene.rehearsal?.n, 1);
        expect(screen.state.needsPerson, isFalse);
        closeTheRoom(screen.container);
      },
    );

    testWidgets('6. an empty take leaves the rehearsal on its translate step', (
      tester,
    ) async {
      final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
      screen.room.sceneAudio = Uint8List(0);

      screen.open();
      await screen.translates(1);
      await screen.pump(const Duration(seconds: 2));

      expect(screen.state.scene.step, SceneStep.translate);
      expect(screen.state.scene.rehearsal?.n, 1);
      closeTheRoom(screen.container);
    });

    testWidgets(
      '7. a row the room never measured waits for its take on the loading '
      'state, never on the record step',
      (tester) async {
        final screen = await _atRest(
          tester,
          rehearsals: [_rehearsal(durationMs: null)],
        );
        screen.room.holdNextClip();

        screen.open();
        await screen.pump(const Duration(seconds: 6));

        expect(screen.loading, isTrue);

        screen.room.finishHeldClip();
        await screen.translates(1);

        expect(screen.recordStep.shown, isFalse);
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      '8. an unsent rehearsal whose take is on the tablet opens on its '
      'translate step however slow its measure and the scene list',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.open();
        await screen.translates(1);
        await screen.until(
          'o take chegar',
          () => screen.state.scene.take != null,
        );
        await screen.leaves();
        screen.room.holdNextScenes();
        screen.harness.playback.holdNextMeasurement();

        screen.open();
        await screen.pump(const Duration(seconds: 6));

        expect(screen.asked('scenesOf'), 1);
        expect(screen.loading, isTrue);

        screen.harness.playback.finishHeldMeasurement();
        await screen.translates(1);
        screen.room.finishHeldScenes();

        expect(screen.recordStep.shown, isFalse);
        expect(screen.room.clipsFetched, hasLength(1));
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      'a take on its way when the team leaves and opens again lands on the '
      'screen opened again, asked for once',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room.holdNextClip();
        screen.open();
        await screen.translates(1);
        await screen.leaves();

        screen.open();
        await screen.translates(1);
        screen.room.finishHeldClip();
        await screen.pump(const Duration(milliseconds: 500));

        expect(screen.state.scene.step, SceneStep.translate);
        expect(screen.state.scene.rehearsal?.n, 1);
        expect(screen.state.scene.take, isNotNull);
        expect(screen.room.clipsFetched, hasLength(1));
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      'a take the room no longer has is asked for once, however the screen is '
      'laid again',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room
          ..failClipWith = const Refused(RefusalCode.notFound)
          ..clipDelay = const Duration(milliseconds: 100);

        screen.open();
        await screen.translates(1);
        await screen.pump(const Duration(seconds: 10));

        expect(screen.room.clipsFetched, hasLength(1));
        closeTheRoom(screen.container);
      },
    );
  });

  group('the take behind the step', () {
    test(
      '9. nothing plays when the take arrives after the step opened',
      () async {
        final room = await _aRoom(rehearsals: [_rehearsal()]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        final sounds = room.harness.sounds.length;

        room.harness.room.finishHeldClip();
        await _theTakeLands(room);
        await settle(const Duration(milliseconds: 400));

        expect(
          room.harness.sounds.skip(sounds),
          isNot(contains('playback:play')),
        );
      },
    );

    test(
      '10. a circle tap before the take arrives plays the take once it lands, '
      'from where the translation stopped',
      () async {
        final room = await _aRoom(rehearsals: [_rehearsal()]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        final played = room.harness.playback.played.length;
        expect(room.state.scene.waiting, isFalse);

        room.sala.tapTheTranslateCircle();
        await settle();

        expect(room.harness.playback.played.length, played);

        room.harness.room.finishHeldClip();
        await waitFor(
          'o take tocar',
          () => room.harness.playback.played.length > played,
        );
        await settle();

        expect(room.harness.playback.played.skip(played), [
          room.state.scene.take,
        ]);
        expect(
          room.harness.playback.playedFrom.last,
          const Duration(milliseconds: 4000),
        );
      },
    );

    test(
      '11. a frase\'s bar tapped before the take arrives plays that frase once '
      'the take lands',
      () async {
        final room = await _aRoom(
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 1000, 4000)]),
          ],
        );
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        final played = room.harness.playback.played.length;
        expect(room.state.scene.waiting, isFalse);

        room.sala.translateTheFraseAgain('f1');
        await settle();

        expect(room.harness.playback.played.length, played);

        room.harness.room.finishHeldClip();
        await waitFor(
          'a frase tocar',
          () => room.harness.playback.played.length > played,
        );
        await settle();

        expect(room.harness.playback.played.skip(played), [
          room.state.scene.take,
        ]);
        expect(room.harness.playback.ranges.last, startsWith('1000-'));
      },
    );

    test(
      '«traduzir» tapped before the take arrives plays the take once it lands',
      () async {
        final room = await _aRoom(rehearsals: [_rehearsal()]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        final played = room.harness.playback.played.length;
        expect(room.state.scene.waiting, isFalse);

        room.sala.playTheSceneRehearsal();
        await settle();

        expect(room.harness.playback.played.length, played);

        room.harness.room.finishHeldClip();
        await waitFor(
          'o take tocar',
          () => room.harness.playback.played.length > played,
        );
        await settle();

        expect(room.harness.playback.played.skip(played), [
          room.state.scene.take,
        ]);
      },
    );

    test('12. a take that lands after the team opened another rehearsal leaves '
        'that rehearsal on screen', () async {
      final room = await _aRoom(rehearsals: [_sent(), _rehearsal(n: 2)]);
      final kept = await room.harness.recorder.keepBytes(
        aSpokenWav(length: _length),
        'cena-ensaio-da-cena-1',
      );
      room.harness.room.holdNextClip();
      room.sala.openTheSceneRehearsal();
      await _translates(room, 2);

      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await waitFor(
        'o ensaio 1 abrir',
        () => room.state.scene.rehearsal?.n == 1 && !room.state.scene.waiting,
      );
      room.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 400));

      expect(room.state.scene.rehearsal?.n, 1);
      expect(room.state.scene.step, SceneStep.sent);
      expect(room.state.scene.take, kept);
    });

    test('13. a take that lands after the team went back draws nothing on the '
        'screen they come back to', () async {
      final room = await _aRoom(rehearsals: [_rehearsal()]);
      room.harness.room.holdNextClip();
      room.sala.openTheSceneRehearsal();
      await _translates(room, 1);
      await _leaves(room);
      room.harness.room.sceneRehearsals[0] = _sent();
      room.sala.openTheSceneRehearsal();
      await _onTheRecordStepAgain(room);

      room.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 400));

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.take, isNull);
      await theSceneMicrophoneOpens(room);
    });

    test(
      '14. one take is asked for once, whatever taps come before it lands',
      () async {
        final room = await _aRoom(rehearsals: [_rehearsal()]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        expect(room.state.scene.waiting, isFalse);

        for (var vez = 0; vez < 3; vez++) {
          room.sala.tapTheTranslateCircle();
          await settle();
        }
        room.harness.room.finishHeldClip();
        await _theTakeLands(room);

        expect(_takesAskedOf(room, 1), 1);
      },
    );

    test(
      'a listed row the room never measured whose take cannot be had gives up, '
      'and the screen stays where it was',
      () async {
        final room = await _aRoom(rehearsals: [_sent(durationMs: null)]);
        room.sala.openTheSceneRehearsal();
        await _onTheRecordStepAgain(room);
        room.harness.room.sceneAudio = Uint8List(0);

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await waitFor('a sala pedir o take', () => _takesAskedOf(room, 1) == 1);
        await settle(const Duration(milliseconds: 400));

        expect(room.state.scene.step, SceneStep.record);
        expect(room.state.scene.rehearsal, isNull);
        expect(room.state.scene.waiting, isFalse);
      },
    );
  });

  group('the record step', () {
    testWidgets(
      '15. with nothing unsent, the record step waits for the scene list at '
      'most 4 s from the open',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_sent()]);
        screen.room.holdNextScenes();

        screen.open();
        await screen.pump(const Duration(milliseconds: 3900));

        expect(screen.asked('scenesOf'), 1);
        expect(screen.loading, isTrue);

        await screen.pump(const Duration(milliseconds: 100));
        await screen.pump();

        expect(byLabel(_record), findsOneWidget);

        screen.room.finishHeldScenes();
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      "16. with nothing unsent, the record step waits for the room's list "
      'however long it takes',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_sent()]);
        screen.room.holdNextSceneList();

        screen.open();
        await screen.pump(const Duration(seconds: 6));

        expect(screen.loading, isTrue);

        screen.room.finishHeldSceneList();
        await screen.until('a pergunta aparecer', () => _shows(_question));
        closeTheRoom(screen.container);
      },
    );

    testWidgets(
      '17. the scene list is not asked again while the translate step shows',
      (tester) async {
        final screen = await _atRest(tester, rehearsals: [_rehearsal()]);
        screen.room.failScenesWith = _offline;

        screen.open();
        await screen.translates(1);
        await screen.pump(const Duration(seconds: 12));

        expect(screen.asked('scenesOf'), 1);

        screen.sala.recordTheSceneAgain();
        await screen.pump(const Duration(milliseconds: 100));

        expect(screen.asked('scenesOf'), 2);
        closeTheRoom(screen.container);
      },
    );
  });

  group('the room unreachable', () {
    test(
      '19. with the room unreachable, the red microphone opens the kept '
      'rehearsal from its take on the tablet, on its translate step',
      () async {
        final room = await _keptOnTheTablet();
        final fetched = room.harness.room.clipsFetched.length;
        room.harness.room.reachable = false;

        final recordStep = _recordStepFrom(
          room,
          room.sala.openTheSceneRehearsal,
        );
        await _translates(room, 1);
        await settle(const Duration(milliseconds: 400));

        expect(room.state.scene.step, SceneStep.translate);
        expect(room.state.scene.take, isNotNull);
        expect(recordStep.shown, isFalse);
        expect(room.harness.room.clipsFetched, hasLength(fetched));
      },
    );

    test('20. with the room unreachable, a kept rehearsal whose frase is held '
        'reopens on its translate step with that frase still held', () async {
      final room = await _aHeldFraseOffline();

      expect(room.state.scene.step, SceneStep.translate);
      expect(room.state.sceneFraseHeld, isTrue);
    });

    test(
      '21. when the room answers again, the rehearsal opened offline takes the '
      "room's answer without leaving its translate step",
      () async {
        final room = await _aHeldFraseOffline();
        room.harness.room.reachable = true;
        final posts = room.harness.room.frasesKept.length;

        room.sala.tapTheTranslateCircle();
        await waitFor(
          'o ensaio da cena tocar',
          () => room.state.channel is PartPlaying,
        );
        room.harness.playback.at = const Duration(seconds: 6);
        room.sala.tapTheTranslateCircle();
        await waitFor(
          'a pausa ser marcada',
          () => room.state.scene.pausa != null,
        );
        room.sala.tapTheTranslateCircle();
        await waitFor(
          'a frase guardada ir para a sala',
          () =>
              room.harness.room.frasesKept.length > posts &&
              !room.state.scene.waiting,
        );
        await settle(const Duration(milliseconds: 400));

        expect(room.state.scene.step, SceneStep.translate);
        expect(room.state.sceneFraseHeld, isFalse);
        expect(
          room.harness.room.frasesKept
              .skip(posts)
              .map((kept) => (kept.startsMs, kept.endsMs)),
          [(4000, 6000)],
        );
        expect(room.state.scene.rehearsal?.translatedFrases, 2);
      },
    );

    test(
      '22. with the room unreachable and nothing of a rehearsal on the tablet, '
      'the record step opens as before',
      () async {
        final room = await _aRoom(rehearsals: [_rehearsal()]);
        room.harness.room.failClipWith = const Refused('HTTP_422');
        room.sala.openTheSceneRehearsal();
        await _translates(room, 1);
        await settle();
        await _leaves(room);
        room.harness.room.reachable = false;

        room.sala.openTheSceneRehearsal();
        await _onTheRecordStepAgain(room);
        await settle();

        expect(room.state.scene.rehearsal, isNull);
        await theSceneMicrophoneOpens(room);
      },
    );

    test('after a session change, an offline open names nothing from the old '
        'session', () async {
      final room = await _keptOnTheTablet();
      await room.sala.abrirEscolha();
      unawaited(room.sala.goConversa(book: 'Ruth'));
      await waitFor(
        'a sessão nova se calar no convite',
        () =>
            room.state.sessionId == 'sessao-2' &&
            room.state.voice == VoiceState.invite &&
            !room.state.awaitingTheGuide,
      );
      await settle();
      room.harness.room.reachable = false;

      room.sala.openTheSceneRehearsal();
      await _onTheRecordStepAgain(room);
      await settle(const Duration(milliseconds: 400));

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.rehearsal, isNull);
    });

    test(
      '23. with the room unreachable, «gravar esta cena de novo» still resumes '
      'nothing',
      () async {
        final room = await _keptOnTheTablet(
          n: 3,
          alsoListed: [
            _sent(scene: 'S1'),
            _sent(n: 2, scene: 'S1'),
          ],
          scenes: _scenes,
        );
        room.sala.openTheEnsaioFinal();
        await waitFor(
          'o plano ser lido',
          () => room.state.ensaioFinalPlan is PlanRead,
        );
        room.sala.swapTheRehearsal('S1');
        await waitFor('a folha abrir', () => room.state.planSheet == 'S1');
        room.harness.room.reachable = false;

        room.sala.rehearseThisSceneAgain();
        await _onTheRecordStepAgain(room);
        await settle(const Duration(milliseconds: 400));

        expect(room.state.scene.step, SceneStep.record);
        expect(room.state.scene.rehearsal, isNull);
        expect(room.state.scene.again, 'S1');
      },
    );

    test('24. a scene take waiting in the Outbox comes back on the record step '
        'with its retry, offline too', () async {
      final room = await _keptOnTheTablet();
      room.harness.room.reachable = false;
      await room.harness.takes.enqueue(
        room.harness.recorder.aFile('cena-que-espera'),
        sessionId: room.state.sessionId,
        kind: 'cena',
        scope: 'cena',
      );
      await room.harness.takes.flush();

      room.sala.openTheSceneRehearsal();
      await waitFor(
        'o take que espera voltar à tela',
        () => room.state.scene.keep is NotKept,
      );
      await settle(const Duration(milliseconds: 400));

      expect(room.state.scene.step, SceneStep.record);
      expect(room.state.scene.keep, isA<NotKept>());
      expect(room.state.scene.rehearsal, isNull);
    });
  });
}
