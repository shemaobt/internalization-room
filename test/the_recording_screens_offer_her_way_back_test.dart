import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _backToPassage = 'Voltar para a passagem atual';
const _backToPassageEn = 'Back to the current passage';
const _chooseAnother = 'Escolher outra passagem';
const _chooseAnotherEn = 'Choose another passage';
const _backToRecording = 'Voltar para a gravação';
const _backToRecordingEn = 'Back to recording';

const _how = 'Como vocês querem gravar?';
const _whole = 'A passagem inteira';
const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _thinking = 'pensando…';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _thePassage = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {
        'Gravar o ensaio de vocês',
        'Abrir o Ensaio Final',
        'Record your rehearsal',
        'Open the Final Rehearsal',
      }.contains(widget.properties.label),
);

SceneRehearsalRecord _rehearsal(String sessionId) => SceneRehearsalRecord(
  rehearsalId: '$sessionId-ensaio-1',
  sessionId: sessionId,
  n: 1,
  scene: 'S1',
  recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
  sentAt: '2026-10-22T10:00:00+00:00',
  durationMs: 7000,
  frases: const [
    SceneFrase(fraseId: 'frase-0', startsMs: 0, endsMs: 3500),
    SceneFrase(fraseId: 'frase-1', startsMs: 3500, endsMs: 7000),
  ],
  contentType: 'audio/wav',
  verified: true,
);

Future<void> _settles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _onTheConversation(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  bool withARehearsal = false,
  List<TakeView> roomTakes = const [],
}) async {
  final harness = SalaHarness(lingua: lingua, filaEmMemoria: true)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = const Moment(
      at: MomentAt.internalization,
      part: 2,
      parts: 3,
    )
    ..room.passageScenes = scenes
    ..room.takes.addAll(roomTakes);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  for (
    var vez = 0;
    vez < 30 && container.read(salaSessionProvider).voice != VoiceState.invite;
    vez++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 1500));
  if (withARehearsal) {
    harness.room.sceneRehearsals.add(
      _rehearsal(container.read(salaSessionProvider).sessionId!),
    );
  }
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _onTheGrainChoice(
  WidgetTester tester, {
  String lingua = 'pt',
}) async {
  final (harness, container) = await _onTheConversation(
    tester,
    lingua: lingua,
    scenes: const [],
  );
  await tester.tap(_dot);
  await _settles(tester);
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _onTheHome(WidgetTester tester) async {
  final (harness, container) = await _onTheGrainChoice(tester);
  await tester.tap(find.text(_whole));
  await _settles(tester);
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _onTheFirstListen(
  WidgetTester tester, {
  String lingua = 'pt',
}) async {
  final (harness, container) = await _onTheGrainChoice(tester, lingua: lingua);
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.chooseTheGrain(Grain.whole);
  await _settles(tester);
  notifier.gravarACena(1);
  await _settles(tester);
  notifier.gravarACena(1);
  await _settles(tester);
  notifier.takeKeep();
  await _settles(tester);
  await untilTheAdvanceDiscLights(
    notifier,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  harness.room.listeningUnheardTakeIds = [
    for (final parte in container.read(salaSessionProvider).partes)
      ?parte.takeId,
  ];
  notifier.startRetro();
  await _settles(tester);
  await _settles(tester);
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _onThePlan(WidgetTester tester) async {
  final (harness, container) = await _onTheConversation(
    tester,
    withARehearsal: true,
  );
  await tester.tap(_dot);
  await _settles(tester);
  return (harness, container);
}

void main() {
  testWidgets(
    'the grain choice offers the way back to the passage, not the way to '
    'another passage',
    (tester) async {
      await _onTheGrainChoice(tester);

      expect(find.text(_how), findsOneWidget);
      expect(byLabel(_backToPassage), findsOneWidget);
      expect(
        byLabel(_chooseAnother),
        findsNothing,
        reason:
            'o ≡ levava à escolha de outra passagem, e o dela volta à conversa',
      );
    },
  );

  testWidgets(
    'the Ensaio Final plan offers the way back to the passage, not the way to '
    'another passage',
    (tester) async {
      await _onThePlan(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(byLabel(_backToPassage), findsOneWidget);
      expect(byLabel(_chooseAnother), findsNothing);
    },
  );

  testWidgets(
    'the recording home offers the way back to the passage, not the way to '
    'another passage',
    (tester) async {
      await _onTheHome(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(byLabel(_backToPassage), findsOneWidget);
      expect(byLabel(_chooseAnother), findsNothing);
    },
  );

  testWidgets(
    'in English the grain choice says her way back, «Back to the current '
    'passage»',
    (tester) async {
      await _onTheGrainChoice(tester, lingua: 'en');

      expect(byLabel(_backToPassageEn), findsOneWidget);
      expect(byLabel(_chooseAnotherEn), findsNothing);
    },
  );

  testWidgets(
    'the way back from the recording home returns to the conversation of the '
    'same passage, where the way to another passage stands',
    (tester) async {
      final (_, container) = await _onTheHome(tester);
      final session = container.read(salaSessionProvider).sessionId;

      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason: 'o canto levava à escolha de outra passagem, nunca à conversa',
      );
      expect(container.read(salaSessionProvider).sessionId, session);
      expect(byLabel(_chooseAnother), findsOneWidget);
      expect(byLabel(_backToPassage), findsNothing);
    },
  );

  testWidgets(
    'the way back from the Ensaio Final plan returns to the conversation, '
    'not to the choice of passages',
    (tester) async {
      final (_, container) = await _onThePlan(tester);
      final session = container.read(salaSessionProvider).sessionId;

      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(container.read(salaSessionProvider).sessionId, session);
    },
  );

  testWidgets(
    'the plan\'s «pensando…» already offers the way back, and a plan read '
    'that lands after the tap leaves the team on the conversation',
    (tester) async {
      final (harness, container) = await _onTheConversation(
        tester,
        roomTakes: const [
          TakeView(
            takeId: 'gravacao-inteira',
            kind: 'ensaio',
            scope: KeptScope.whole,
            pass: 1,
          ),
        ],
      );
      harness.room.holdNextSceneList();
      await tester.tap(_dot);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_thinking), findsOneWidget);
      expect(
        byLabel(_backToPassage),
        findsOneWidget,
        reason: 'o «pensando…» não tinha canto nenhum por até 6 s',
      );

      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.finishHeldSceneList();
      await _settles(tester);
      await tester.pump(const Duration(seconds: 7));

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    'a take recorded on the home and not kept is thrown away on the way back '
    'to the conversation',
    (tester) async {
      final (harness, container) = await _onTheHome(tester);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Gravar')),
      );
      await _settles(tester);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Parar')),
      );
      await _settles(tester);
      expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);

      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(
        harness.recorder.deleted,
        hasLength(1),
        reason: 'a gravação não guardada ficava no tablet, sem dono',
      );
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.idle,
        reason: 'a casa ainda achava que havia uma gravação a guardar',
      );
    },
  );

  testWidgets(
    'a kept part playing on the home falls silent on the way back to the '
    'conversation',
    (tester) async {
      final (harness, container) = await _onTheHome(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Gravar')),
      );
      await _settles(tester);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Parar')),
      );
      await _settles(tester);
      notifier.takeKeep();
      await _settles(tester);
      await untilTheWoodPlayLights(
        notifier,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      notifier.playTheRehearsal();
      await _settles(tester);
      expect(harness.playback.sounding, isTrue);

      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'a parte seguia tocando por cima da conversa',
      );
    },
  );

  testWidgets('the back-translation\'s first listen offers the way back to the '
      'recording, not the way to another passage', (tester) async {
    final (_, container) = await _onTheFirstListen(tester);

    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
    expect(container.read(salaSessionProvider).btSoOuvir, isTrue);
    expect(
      byLabel(_backToRecording),
      findsOneWidget,
      reason: 'o ≡ da tradução levava à escolha de outra passagem',
    );
    expect(byLabel(_chooseAnother), findsNothing);
    expect(byLabel(_backToPassage), findsNothing);
  });

  testWidgets(
    'in English the back-translation says her way back, «Back to recording»',
    (tester) async {
      await _onTheFirstListen(tester, lingua: 'en');

      expect(byLabel(_backToRecordingEn), findsOneWidget);
      expect(byLabel(_chooseAnotherEn), findsNothing);
    },
  );

  testWidgets(
    'the way back from the back-translation returns to the recording home, '
    'not to the choice of passages',
    (tester) async {
      final (harness, container) = await _onTheFirstListen(tester);
      final session = container.read(salaSessionProvider).sessionId;

      await tester.tap(byLabel(_backToRecording));
      await _settles(tester);

      expect(
        container.read(salaSessionProvider).station,
        const Ensaio(),
        reason: 'o canto da tradução levava à escolha de outra passagem',
      );
      expect(container.read(salaSessionProvider).sessionId, session);
      expect(find.text(_homeLine), findsOneWidget);
      expect(harness.playback.sounding, isFalse);
    },
  );

  testWidgets(
    'the back-translation\'s checked screen offers the way back to the '
    'recording, not the way to another passage',
    (tester) async {
      final (harness, container) = await _onTheGrainChoice(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.chooseTheGrain(Grain.whole);
      await _settles(tester);
      notifier.gravarACena(1);
      await _settles(tester);
      notifier.gravarACena(1);
      await _settles(tester);
      notifier.takeKeep();
      await _settles(tester);
      await untilTheAdvanceDiscLights(
        notifier,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      notifier.startRetro();
      await _settles(tester);
      harness.playback.finishPlayback();
      await _settles(tester);
      harness.room.verdictChecked = true;
      await notifier.finishBackTranslation();
      await _settles(tester);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
      expect(
        byLabel(_backToRecording),
        findsOneWidget,
        reason: 'na tela conferida o canto levava à escolha de outra passagem',
      );
      expect(byLabel(_chooseAnother), findsNothing);
    },
  );
}
