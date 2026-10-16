import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_question.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';
const _articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);
const _offline = NetworkFailed('sem rede');

const _p02 = [
  Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
  Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
  Scene(sceneId: 'S3', title: 'Segundo apelo e a separação'),
];

const _question = 'Qual cena vocês vão ensaiar?';
const _scene1 = 'cena 1 Ouvir a notícia e partir';
const _scene2 = 'cena 2 Primeiro apelo e recusa';
const _scene3 = 'cena 3 Segundo apelo e a separação';
const _buttons = [_scene1, _scene2, _scene3];
const _chip2 = 'cena 2 · Primeiro apelo e recusa — $_question';
const _chip3 = 'cena 3 · Segundo apelo e a separação — $_question';
const _record = 'Gravar o ensaio da cena';
const _recording =
    'gravem o ensaio da cena na língua materna; toquem para parar';
const _saving = 'guardando o ensaio da cena…';
const _retry = 'falhou — toque para tentar de novo';
const _again = 'gravar o ensaio da cena de novo';

const _wake = Duration(milliseconds: 600);

/// The stage's cross-fade, before which VoiceOver does not reach the new screen.
const _theStageFadesIn = Duration(milliseconds: 1400);

Uint8List _aTake(int seed) =>
    Uint8List.fromList([for (var i = 0; i < 1200; i++) (i * seed) % 251]);

SceneRehearsalRecord _rehearsal(int n, {String? scene, bool sent = false}) =>
    SceneRehearsalRecord(
      rehearsalId: 'ensaio-da-cena-$n',
      sessionId: _session,
      n: n,
      scene: scene,
      sentAt: sent ? '2026-10-16T10:0$n:00+00:00' : null,
    );

final class _Room {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.tester, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int asked(String call) => room.calls.where((asked) => asked == call).length;

  Future<void> pump([Duration by = Duration.zero]) => tester.pump(by);

  Future<void> pumpUntil(
    String what,
    bool Function() done, {
    Duration beat = const Duration(milliseconds: 10),
    Duration limit = const Duration(seconds: 20),
  }) async {
    var waited = Duration.zero;
    while (!done()) {
      if (waited >= limit) fail('esperei $limit e $what não aconteceu');
      await tester.pump(beat);
      waited += beat;
    }
  }

  Future<void> sleepThrough() => pump(_wake);

  Future<void> pick(String button) async {
    await tester.tap(byLabel(button));
    await pump();
  }

  Future<void> theMicrophoneOpens() async {
    sala.sceneTap();
    await pumpUntil(
      'o microfone da cena abrir',
      () => switch (state.channel) {
        Microphone(owner: MicOwner.scene) => true,
        _ => false,
      },
    );
  }

  Future<void> recordAndStop({int seed = 7}) async {
    harness.recorder.rehearsalSpeaks = _aTake(seed);
    await theMicrophoneOpens();
    await stop();
  }

  Future<void> stop() async {
    sala.sceneTap();
    await pumpUntil(
      'o take ser guardado ou ficar esperando',
      () => state.channel is! Microphone && state.scene.keep is! Keeping,
    );
    await pump(const Duration(milliseconds: 100));
  }

  Future<void> again() async {
    sala.recordTheSceneAgain();
    await pump();
  }
}

bool _shows(String label) => byLabel(label).evaluate().isNotEmpty;

const _theList = 'ensaios da cena desta sessão';

String _rowOf(WidgetTester tester, int n) => _labelsOnScreen(tester).firstWhere(
  (label) =>
      label.toLowerCase().contains('ensaio da cena $n,') ||
      label.toLowerCase().startsWith('continuar o ensaio da cena $n') ||
      label.toLowerCase().startsWith('ensaio da cena $n'),
);

({String words, bool live}) _theChip(WidgetTester tester) {
  final chip = tester.widget<SceneChip>(find.byType(SceneChip));
  return (words: chip.words, live: chip.live);
}

/// A scene take recorded earlier that still waits in the Outbox for this session.
Future<void> _aTakeWaits(SalaHarness harness, {required String? scene}) =>
    harness.takes.enqueue(
      harness.recorder.aFile('cena-que-espera'),
      sessionId: _session,
      kind: 'cena',
      scope: 'cena',
      scene: scene,
    );

bool _theCircleShows() =>
    _shows(_record) || _shows(_recording) || _shows(_saving);

bool _theScreenRests() => _shows(_question) || _theCircleShows();

Future<_Room> _theScreenOpens(
  WidgetTester tester, {
  List<Scene> scenes = _p02,
  List<SceneRehearsalRecord> rehearsals = const [],
  String lingua = 'pt',
  FutureOr<void> Function(SalaHarness harness)? before,
  bool rests = true,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: lingua)
    ..room.passages = const [Passagem(pericope: 'P02', audioUrl: '/voice/p02')]
    ..room.nextMoment = _articulation
    ..room.passageScenes = scenes
    ..room.sceneRehearsals.addAll(rehearsals)
    ..room.sceneAudio = Uint8List.fromList([1, 2, 3]);
  harness.playback.measured = const Duration(seconds: 20);
  await before?.call(harness);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container);
  await room.sala.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(room.sala.goConversa(pericope: 'P02'));
  await room.pumpUntil(
    'a sala se calar no convite',
    () =>
        room.state.sessionId != null &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
    beat: const Duration(milliseconds: 100),
  );
  await tester.pump(const Duration(milliseconds: 1500));
  room.sala.openTheSceneRehearsal();
  await tester.pump();
  if (rests) {
    await room.pumpUntil('a tela do ensaio da cena assentar', () {
      final scene = room.state.scene;
      return room.state.stage == SalaStage.cena &&
          !scene.waiting &&
          (scene.step != SceneStep.record || _theScreenRests());
    });
  }
  return room;
}

List<String> _highlighted(WidgetTester tester) => [
  for (final button in tester.widgetList<SceneButton>(find.byType(SceneButton)))
    if (button.highlighted) button.label,
];

List<String> _buttonsInOrder(WidgetTester tester) => [
  for (final button in tester.widgetList<SceneButton>(find.byType(SceneButton)))
    button.label,
];

void _voiceOverTaps(WidgetTester tester, String label) {
  final node = tester.getSemantics(byLabel(label));
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '$label precisa de uma ação de toque para o VoiceOver',
  );
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      type: SemanticsAction.tap,
      viewId: tester.view.viewId,
      nodeId: node.id,
    ),
  );
}

bool _focused(WidgetTester tester, String label) {
  final node = tester.getSemantics(byLabel(label));
  return node.getSemanticsData().flagsCollection.isFocused == Tristate.isTrue;
}

Iterable<String> _labelsOnScreen(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((widget) => widget.properties.label)
    .whereType<String>();

void main() {
  group('the question', () {
    testWidgets(
      'case 2: a passage with three scenes, none rehearsed, asks «Qual cena '
      'vocês vão ensaiar?» with three buttons in passage order, scene 1 '
      'highlighted and focused, and no circle',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _theScreenOpens(tester);
        await tester.pump(_theStageFadesIn);

        expect(byLabel(_question), findsOneWidget);
        expect(_buttonsInOrder(tester), _buttons);
        for (final button in _buttons) {
          expect(
            find.descendant(of: byLabel(_question), matching: byLabel(button)),
            findsOneWidget,
            reason: 'os botões ficam sob o grupo da pergunta',
          );
        }
        expect(_highlighted(tester), [_scene1]);
        expect(_focused(tester, _scene1), isTrue);
        expect(_theCircleShows(), isFalse);
        semantics.dispose();
      },
    );

    testWidgets(
      'case 3: with scene 1 sent, scene 2 is highlighted; the team taps scene '
      '3, «cena 3 · Segundo apelo e a separação» shows above the circle and '
      'the recording is labelled scene 3',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
        );

        expect(_highlighted(tester), [_scene2]);

        await room.sleepThrough();
        await room.pick(_scene3);
        await tester.pump();

        expect(byLabel(_chip3), findsOneWidget);
        expect(byLabel(_record), findsOneWidget);
        expect(_shows(_question), isFalse);
        expect(_focused(tester, _record), isTrue);

        await room.sleepThrough();
        await room.recordAndStop();

        expect(room.room.sceneLabels, ['S3']);
        semantics.dispose();
      },
    );

    testWidgets(
      'case 4: an unsent or an unlabelled rehearsal never counts as rehearsed',
      (tester) async {
        await _theScreenOpens(
          tester,
          rehearsals: [
            _rehearsal(1, sent: true),
            _rehearsal(2, scene: 'S1'),
            _rehearsal(3, scene: 'S2', sent: true),
          ],
        );

        expect(_highlighted(tester), [_scene1]);
      },
    );

    testWidgets(
      'case 5: with every scene sent, no scene is highlighted and the question '
      'is still asked',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _theScreenOpens(
          tester,
          rehearsals: [
            _rehearsal(1, scene: 'S1', sent: true),
            _rehearsal(2, scene: 'S2', sent: true),
            _rehearsal(3, scene: 'S3', sent: true),
          ],
        );
        await tester.pump(_theStageFadesIn);

        expect(byLabel(_question), findsOneWidget);
        expect(_highlighted(tester), isEmpty);
        expect(_focused(tester, _scene1), isTrue);
        semantics.dispose();
      },
    );

    testWidgets(
      'case 6: after «gravar o ensaio da cena de novo» the question is asked '
      'again, with the scene of the rehearsal on screen highlighted and '
      'nothing picked',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [
            _rehearsal(1, scene: 'S1', sent: true),
            _rehearsal(2, scene: 'S3'),
          ],
        );
        expect(room.state.scene.rehearsal?.n, 2, reason: 'reaberto na tela');

        await tester.tap(byLabel(_again));
        await room.pump();

        expect(byLabel(_question), findsOneWidget);
        expect(_highlighted(tester), [_scene3]);
        expect(_theCircleShows(), isFalse);
      },
    );

    testWidgets(
      'case 7: after «gravar o ensaio da cena de novo» on a sent scene, that '
      'scene is highlighted even when every scene is sent',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [
            _rehearsal(1, scene: 'S1', sent: true),
            _rehearsal(2, scene: 'S2', sent: true),
            _rehearsal(3, scene: 'S3', sent: true),
          ],
        );
        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-2');
        await room.pumpUntil(
          'o ensaio 2 abrir',
          () =>
              room.state.scene.rehearsal?.n == 2 &&
              room.state.scene.step == SceneStep.sent,
        );

        await room.again();

        expect(_highlighted(tester), [_scene2]);
      },
    );

    testWidgets(
      'case 8: the question waits for the team\'s tap: nothing is picked, '
      'however long it stands',
      (tester) async {
        final room = await _theScreenOpens(tester);

        for (var second = 0; second < 60; second++) {
          await room.pump(const Duration(seconds: 1));
        }

        expect(byLabel(_question), findsOneWidget);
        expect(_theCircleShows(), isFalse);

        final sounds = room.harness.sounds.length;
        room.sala.sceneTap();
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.channel, isNot(isA<Microphone>()));
        expect(
          room.harness.sounds.skip(sounds),
          isNot(contains('recorder:start')),
        );
      },
    );
  });

  group('VoiceOver', () {
    testWidgets(
      'VoiceOver picks a scene with the button\'s own tap, and the chip\'s brings '
      'the question back',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final room = await _theScreenOpens(tester);
        await tester.pump(_theStageFadesIn);

        _voiceOverTaps(tester, _scene2);
        await room.pump();

        expect(byLabel(_chip2), findsOneWidget);

        await room.sleepThrough();
        _voiceOverTaps(tester, _chip2);
        await room.pump();

        expect(byLabel(_question), findsOneWidget);
        semantics.dispose();
      },
    );
  });

  group('one scene, no list', () {
    testWidgets(
      'case 12: a passage with one scene asks nothing and labels the recording '
      'with that scene',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          scenes: const [Scene(sceneId: 'S1', title: 'As gerações de Perez')],
        );

        expect(byLabel(_record), findsOneWidget);
        expect(_shows(_question), isFalse);
        expect(
          _labelsOnScreen(
            tester,
          ).where((label) => label.endsWith(' — $_question')),
          isEmpty,
          reason: 'sem chip',
        );

        await room.recordAndStop();

        expect(room.room.sceneLabels, ['S1']);
      },
    );

    testWidgets('case 14: a scene list that fails at once shows the circle at '
        'once', (tester) async {
      final room = await _theScreenOpens(
        tester,
        before: (harness) => harness.room.failScenesWith = _offline,
        rests: false,
      );
      await tester.pump(const Duration(milliseconds: 99));

      expect(byLabel(_record), findsOneWidget);
      closeTheRoom(room.container);
    });
  });

  group('the open never blocks recording', () {
    testWidgets(
      'a rehearsal list that never answers leaves the circle on screen after 4 '
      'seconds, and the team records',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          scenes: const [],
          before: (harness) => harness.room.holdNextSceneList(),
          rests: false,
        );
        await room.pump(const Duration(milliseconds: 3900));

        expect(_theCircleShows(), isFalse);

        await room.pump(const Duration(milliseconds: 100));

        expect(byLabel(_record), findsOneWidget);
        await room.theMicrophoneOpens();
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a one-scene list that arrives while the microphone is open leaves that '
      'take unlabelled',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          scenes: const [Scene(sceneId: 'S1', title: 'As gerações de Perez')],
          before: (harness) => harness.room.holdNextScenes(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        room.harness.recorder.rehearsalSpeaks = _aTake(7);
        await room.theMicrophoneOpens();

        room.room.finishHeldScenes();
        await room.pump(const Duration(milliseconds: 100));
        await room.stop();

        expect(room.room.sceneLabels, [null]);
        closeTheRoom(room.container);
      },
    );
  });

  group('a reopen whose take is late', () {
    testWidgets(
      'an unsent rehearsal whose take is still on its way never sits on the '
      'record step: its row opens from the list, and a take recorded there '
      'carries none of it',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1')],
          before: (harness) => harness.room.holdNextClip(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));

        expect(byLabel(_question), findsOneWidget);
        expect(_rowOf(tester, 1), startsWith('continuar o ensaio da cena 1'));

        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();
        room.harness.recorder.rehearsalSpeaks = _aTake(7);
        await room.theMicrophoneOpens();

        expect(_rowOf(tester, 1), startsWith('continuar o ensaio da cena 1'));

        await room.stop();
        await room.pumpUntil(
          'o take novo abrir na tradução',
          () => room.state.scene.rehearsal?.n == 2,
        );
        room.room.finishHeldClip();
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.scene.rehearsal?.n, 2);

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await room.pumpUntil(
          'o ensaio 1 abrir',
          () => room.state.scene.rehearsal?.n == 1 && !room.state.scene.waiting,
        );
        closeTheRoom(room.container);
      },
    );
  });

  group('the open after its 4 s', () {
    testWidgets(
      'the session\'s rehearsals that answer after the team picked still list, '
      'and the highlight reads them',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
          before: (harness) => harness.room.holdNextSceneList(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        await room.sleepThrough();
        await room.pick(_scene3);

        room.room.finishHeldSceneList();
        await room.pump(const Duration(milliseconds: 100));

        expect(byLabel(_theList), findsOneWidget);

        await room.sleepThrough();
        await tester.tap(byLabel(_chip3));
        await room.pump();

        expect(_highlighted(tester), [_scene2]);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a reopen whose take lands after the record step showed gives up, and its '
      'row stays openable',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1')],
          before: (harness) => harness.room
            ..holdNextScenes()
            ..holdNextClip(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        expect(byLabel(_record), findsOneWidget);

        await room.pump(const Duration(seconds: 1));
        room.room.finishHeldClip();
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.scene.step, SceneStep.record);
        expect(_theScreenRests(), isTrue);

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await room.pumpUntil(
          'o ensaio 1 abrir',
          () => room.state.scene.rehearsal?.n == 1 && !room.state.scene.waiting,
        );
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a reopen whose take lands after the question showed gives up too',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1')],
          before: (harness) => harness.room.holdNextClip(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        expect(byLabel(_question), findsOneWidget);

        await room.pump(const Duration(seconds: 1));
        room.room.finishHeldClip();
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.scene.step, SceneStep.record);
        expect(byLabel(_question), findsOneWidget);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a reopen still measuring its take when the record step shows gives up',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1')],
          before: (harness) {
            harness.room.holdNextScenes();
            harness.playback.holdNextMeasurement();
          },
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        expect(byLabel(_record), findsOneWidget);

        room.harness.playback.finishHeldMeasurement();
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.scene.step, SceneStep.record);
        expect(byLabel(_record), findsOneWidget);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a rehearsal list that answers late never drops the take kept meanwhile',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
          before: (harness) => harness.room.holdNextSceneList(),
          rests: false,
        );
        await room.pump(const Duration(seconds: 4));
        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();
        await room.recordAndStop();
        await room.pumpUntil(
          'o take abrir na tradução',
          () => room.state.scene.rehearsal?.n == 2,
        );

        room.room.finishHeldSceneList();
        await room.pump(const Duration(milliseconds: 100));

        expect(
          room.state.sceneRehearsals.map((row) => row.n),
          [1, 2],
          reason: 'a resposta velha não tira o take guardado',
        );
        expect(_rowOf(tester, 2), startsWith('Ensaio da cena 2'));
        closeTheRoom(room.container);
      },
    );

    test(
      'a late list adds the rows the screen lacks, keeps the rest, and never '
      'turns a sent rehearsal back to unsent',
      () {
        final held = [
          _rehearsal(1, scene: 'S1', sent: true),
          _rehearsal(2, scene: 'S2'),
        ];
        final listed = [_rehearsal(1, scene: 'S1'), _rehearsal(3, scene: 'S3')];

        expect(
          [
            for (final row in SceneRehearsalRecord.listedOver(
              held,
              listed,
              _session,
            ))
              (row.n, row.unsent),
          ],
          [(1, false), (2, true), (3, true)],
        );
      },
    );
  });

  group('the label at the record tap', () {
    testWidgets(
      'case 21: the label is read at the tap that starts the recording, before '
      'the microphone is asked',
      (tester) async {
        final room = await _theScreenOpens(tester);
        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();
        room.harness.recorder
          ..rehearsalSpeaks = _aTake(7)
          ..holdNextStart();
        room.sala.sceneTap();
        await room.pump();

        room.sala.backToTheSceneQuestion();
        await room.pump(const Duration(milliseconds: 100));

        expect(_shows(_question), isFalse);
        expect(byLabel(_chip2), findsOneWidget);

        room.harness.recorder.finishStart();
        await room.pump(const Duration(milliseconds: 100));
        await room.stop();

        expect(room.room.sceneLabels, ['S2']);
      },
    );

    testWidgets(
      'case 22: a scene take whose upload failed is retried with the label it '
      'had at the record tap',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final room = await _theScreenOpens(tester);
        await room.sleepThrough();
        await room.pick(_scene3);
        await room.sleepThrough();
        room.room.failSceneWith = _offline;
        final recorded = _aTake(9);
        await room.recordAndStop(seed: 9);
        expect(room.state.scene.keep, isA<NotKept>());

        expect(
          tester
              .getSemantics(byLabel(_chip3))
              .getSemanticsData()
              .flagsCollection
              .isEnabled,
          Tristate.isFalse,
          reason: 'o chip fica apagado enquanto o take espera',
        );
        room.sala.backToTheSceneQuestion();
        await room.pump(const Duration(milliseconds: 100));
        expect(_shows(_question), isFalse);

        room.room.failSceneWith = null;
        await tester.tap(byLabel(_retry));
        await room.pumpUntil(
          'o ensaio abrir na tradução',
          () => room.state.scene.step == SceneStep.translate,
        );

        expect(room.room.sceneLabels, ['S3']);
        expect(room.room.sceneTakesSent.single, recorded);

        await room.again();
        await room.sleepThrough();
        await room.pick(_scene1);
        await room.sleepThrough();
        await room.recordAndStop();

        expect(room.room.sceneLabels, ['S3', 'S1']);
        semantics.dispose();
      },
    );
  });

  group('unknown, never guessed', () {
    testWidgets(
      'case 23: a scene the room\'s passage does not have leaves the recording '
      'unlabelled, with nothing shown',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          before: (harness) => harness.room.roomScenes = {'S1', 'S2'},
        );
        await room.sleepThrough();
        await room.pick(_scene3);
        await room.sleepThrough();
        await room.recordAndStop();
        await room.pumpUntil(
          'o ensaio abrir na tradução',
          () => room.state.scene.step == SceneStep.translate,
        );

        expect(room.room.sceneLabels, ['S3']);
        expect(room.room.sceneRehearsals.single.scene, isNull);
        expect(
          _labelsOnScreen(tester).where((label) => label.contains('— cena 3')),
          isEmpty,
          reason: 'a lista não nomeia a cena que a sala não guardou',
        );

        await room.again();

        expect(_highlighted(tester), [_scene1]);
      },
    );

    testWidgets('case 24: no «cena N» appears without the team\'s label', (
      tester,
    ) async {
      final room = await _theScreenOpens(tester, rehearsals: [_rehearsal(1)]);
      expect(room.state.scene.rehearsal?.n, 1);
      await tester.pump();

      expect(
        _labelsOnScreen(
          tester,
        ).where((label) => ['— cena 1', '— cena 2'].any(label.contains)),
        isEmpty,
        reason: 'a lista não nomeia uma cena que a equipe não tocou',
      );
    });
  });

  group('a pick the screen holds', () {
    testWidgets(
      'a waiting take with no pick shows the question beside the retry, and no '
      'chip',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          before: (harness) {
            harness.room.sceneAnswersFirst.add(_offline);
            return _aTakeWaits(harness, scene: null);
          },
        );

        expect(room.state.scene.keep, isA<NotKept>());
        expect(byLabel(_question), findsOneWidget);
        expect(byLabel(_retry), findsOneWidget);
        expect(find.byType(SceneChip), findsNothing);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a pick made while a take waits names the next take only, and the retry '
      'sends the waiting take with its own label',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          before: (harness) {
            harness.room.sceneAnswersFirst.add(_offline);
            return _aTakeWaits(harness, scene: null);
          },
        );
        await room.sleepThrough();
        await room.pick(_scene2);

        expect(_theChip(tester), (
          words: 'cena 2 · Primeiro apelo e recusa',
          live: false,
        ));

        await room.sleepThrough();
        await room.recordAndStop();
        if (room.room.sceneLabels.length < 2) {
          await tester.tap(byLabel(_retry));
        }
        await room.pumpUntil(
          'os dois takes chegarem à sala',
          () => room.room.sceneLabels.length == 2,
        );

        expect(room.room.sceneLabels, unorderedEquals([null, 'S2']));
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a waiting take labelled with a scene the passage lacks shows the question '
      'and no chip',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          before: (harness) {
            harness.room.sceneAnswersFirst.add(_offline);
            return _aTakeWaits(harness, scene: 'S9');
          },
        );

        expect(byLabel(_question), findsOneWidget);
        expect(find.byType(SceneChip), findsNothing);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a waiting take\'s pick stands: its dimmed chip names it, and a circle tap '
      'records the next take under it with no question first',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          before: (harness) {
            harness.room.sceneAnswersFirst.add(_offline);
            return _aTakeWaits(harness, scene: 'S2');
          },
        );

        expect(_shows(_question), isFalse);
        expect(_theChip(tester), (
          words: 'cena 2 · Primeiro apelo e recusa',
          live: false,
        ));

        await room.recordAndStop();
        if (room.room.sceneLabels.length < 2) {
          await tester.tap(byLabel(_retry));
        }
        await room.pumpUntil(
          'os dois takes chegarem à sala',
          () => room.room.sceneLabels.length == 2,
        );

        expect(room.room.sceneLabels, ['S2', 'S2']);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'the rehearsals of the session are listed when a waiting take reopens, so '
      'the question after it highlights the first scene not yet sent',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
          before: (harness) {
            harness.room.sceneAnswersFirst.add(_offline);
            return _aTakeWaits(harness, scene: null);
          },
        );

        expect(room.state.scene.keep, isA<NotKept>());
        expect(byLabel(_theList), findsOneWidget);

        await tester.tap(byLabel(_retry));
        await room.pumpUntil(
          'o ensaio abrir na tradução',
          () => room.state.scene.step == SceneStep.translate,
        );
        await tester.tap(byLabel(_again));
        await room.pump();

        expect(_highlighted(tester), [_scene2]);
        closeTheRoom(room.container);
      },
    );

    testWidgets(
      'a row the team asked to open over a pick opens whatever they tap while '
      'it loads',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
        );
        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();
        room.room.holdNextClip();

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await room.pump(const Duration(milliseconds: 100));
        room.sala
          ..backToTheSceneQuestion()
          ..sceneTap();
        await room.pump(const Duration(milliseconds: 100));
        room.room.finishHeldClip();
        await room.pumpUntil(
          'o ensaio 1 abrir',
          () => room.state.scene.step == SceneStep.sent,
        );

        expect(room.state.scene.rehearsal?.n, 1);
      },
    );

    testWidgets(
      'a row the team asked to open opens whatever they tap while it loads',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
        );
        await room.sleepThrough();
        room.room.holdNextClip();

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await room.pump(const Duration(milliseconds: 100));
        room.sala
          ..pickTheScene('S2')
          ..sceneTap()
          ..backToTheSceneQuestion();
        await room.pump(const Duration(milliseconds: 100));
        room.room.finishHeldClip();
        await room.pumpUntil(
          'o ensaio 1 abrir',
          () => room.state.scene.step == SceneStep.sent,
        );

        expect(room.state.scene.rehearsal?.n, 1);
      },
    );

    testWidgets(
      'a listed rehearsal opened from the record step keeps the pick on screen '
      'while it loads',
      (tester) async {
        final room = await _theScreenOpens(
          tester,
          rehearsals: [_rehearsal(1, scene: 'S1', sent: true)],
        );
        await room.sleepThrough();
        await room.pick(_scene2);
        room.room.holdNextClip();

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await room.pump(const Duration(milliseconds: 100));

        expect(_shows(_question), isFalse);
        expect(byLabel(_chip2), findsOneWidget);
        room.room.finishHeldClip();
        await room.pump(const Duration(milliseconds: 100));
      },
    );
  });

  group('the chip', () {
    testWidgets(
      'case 25: tapping «cena 2 · Primeiro apelo e recusa» above the circle '
      'brings the question back',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final room = await _theScreenOpens(tester);
        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();

        await tester.tap(byLabel(_chip2));
        await room.pump();
        await room.pump();

        expect(byLabel(_question), findsOneWidget);
        expect(_shows(_record), isFalse);
        expect(_highlighted(tester), [_scene1]);
        expect(_focused(tester, _scene1), isTrue);
        semantics.dispose();
      },
    );

    testWidgets(
      'case 26: the chip does nothing while the microphone is open or a keep '
      'is in the air',
      (tester) async {
        final room = await _theScreenOpens(tester);
        await room.sleepThrough();
        await room.pick(_scene2);
        await room.sleepThrough();
        room.harness.recorder.rehearsalSpeaks = _aTake(7);
        await room.theMicrophoneOpens();

        room.sala.backToTheSceneQuestion();
        await room.pump(const Duration(milliseconds: 100));

        expect(byLabel(_recording), findsOneWidget);
        expect(_shows(_question), isFalse);

        room.room.holdNextKeepBeforeTheRoomActs();
        room.sala.sceneTap();
        await room.pumpUntil(
          'a sala receber o take',
          () => room.asked('keepSceneRehearsal') > 0,
        );
        room.sala.backToTheSceneQuestion();
        await room.pump(const Duration(milliseconds: 100));

        expect(byLabel(_saving), findsOneWidget);
        expect(_shows(_question), isFalse);

        room.room
          ..failSceneWith = _offline
          ..finishHeldKeep();
        await room.pumpUntil(
          'o take ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        await room.pump();

        expect(
          byLabel(_chip2),
          findsOneWidget,
          reason: 'nenhum dos toques no chip voltou à pergunta',
        );
        expect(_shows(_question), isFalse);
      },
    );
  });

  group('failure policy and the way out', () {
    test(
      'case 27a: a scene list that fails, however it fails, changes nothing in '
      'the room',
      () {
        for (final result in [
          const RoomNetworkFailed(),
          const RoomTimedOut(),
          const RoomSessionGone(),
          for (final code in RefusalCode.stopsTheRoom) RoomRefused(code),
          const RoomRefused(RefusalCode.unreadable),
          const RoomRefused('ANY_OTHER'),
        ]) {
          for (final rule in RefusalRule.values) {
            expect(
              FailurePolicy.decide(
                result,
                FailureContext(
                  station: Station.stored(SalaStage.cena),
                  generation: 4,
                  door: Door.sceneList,
                  rule: rule,
                  refusals: 2,
                ),
              ),
              isA<TheScenesMissed>().having(
                (event) => event.generation,
                'generation',
                4,
              ),
              reason: '$result ($rule)',
            );
          }
        }
      },
    );

    testWidgets(
      'case 27b: a scene list the room answers as a session gone changes '
      'nothing in the room',
      (tester) async {
        late int personsAsked;
        late _Room room;
        room = await _theScreenOpens(
          tester,
          before: (harness) {
            personsAsked = harness.room.personsAsked;
            harness.room.failScenesWith = const SessionGone();
          },
          rests: false,
        );
        final reach = room.state.reach;
        await room.pump(const Duration(milliseconds: 100));

        expect(room.state.stage, SalaStage.cena);
        expect(room.state.needsPerson, isFalse);
        expect(room.room.personsAsked, personsAsked);
        expect(room.state.reach, reach);
        expect(byLabel(_record), findsOneWidget);
        closeTheRoom(room.container);
      },
    );
  });

  group('words', () {
    testWidgets('case 29: the question and the chip speak the room\'s '
        'language', (tester) async {
      const question = 'Which scene are you going to rehearse?';
      final room = await _theScreenOpens(
        tester,
        lingua: 'en',
        rests: false,
        scenes: const [
          Scene(sceneId: 'S1', title: 'Hearing and setting out'),
          Scene(sceneId: 'S2', title: 'First appeal and refusal'),
          Scene(sceneId: 'S3', title: 'Second appeal and the split'),
        ],
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(byLabel(question), findsOneWidget);
      expect(byLabel('scene 1 Hearing and setting out'), findsOneWidget);

      await room.sleepThrough();
      await room.pick('scene 2 First appeal and refusal');

      expect(
        byLabel('scene 2 · First appeal and refusal — $question'),
        findsOneWidget,
      );
    });

    testWidgets('case 30: the scene question writes her words on the screen', (
      tester,
    ) async {
      final room = await _theScreenOpens(tester);

      expect(find.text(_question), findsOneWidget);

      await room.sleepThrough();
      await room.pick(_scene2);

      expect(find.text('cena 2 · Primeiro apelo e recusa'), findsOneWidget);
    });
  });
}
