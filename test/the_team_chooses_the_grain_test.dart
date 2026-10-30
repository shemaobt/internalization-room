import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheRecordingHome,
        relaunch,
        thePersonSign,
        voiceOverFocusLeaves,
        voiceOverTap;

const _how = 'Como vocês querem gravar?';
const _whole = 'A passagem inteira';
const _oneRecording = 'uma gravação';
const _sceneByScene = 'Cena por cena';
const _wholeChoice = 'A passagem inteira, uma gravação';
const _sceneChoice = 'Cena por cena, 3 partes';
const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _wholeArmed = 'toquem de novo: as cenas e as traduções ficam guardadas';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _sceneInstead = 'Gravar cena por cena';
const _backToJoin = 'Ensaio Final: juntar os ensaios das cenas';
const _recordAgain = 'Gravar de novo';
const _missing = 'falta o ensaio desta cena';
const _failed = 'falhou — toque para tentar de novo';
const _wholeInstead = 'Gravar a passagem inteira';
const _theArmLapses = Duration(seconds: 8);
const _record = 'Gravar';
const _backToPassage = 'Voltar para a passagem atual';

const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _thinking = 'pensando…';
const _elsewhere =
    'Os ensaios desta passagem foram gravados com o aplicativo na outra '
    'língua. Voltem para aquela língua para abrir o Ensaio Final.';

const _recordEnsaio = 'Gravar o ensaio de vocês';
const _openEnsaioFinal = 'Abrir o Ensaio Final';

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _threeScenesEn = [
  Scene(sceneId: 'S1', title: 'Famine in Bethlehem'),
  Scene(sceneId: 'S2', title: 'Naomi decides to return'),
  Scene(sceneId: 'S3', title: 'Ruth clings to Naomi'),
];

const _midConversation = Moment(
  at: MomentAt.internalization,
  part: 2,
  parts: 3,
);

const _thePassage = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {
        _recordEnsaio,
        _openEnsaioFinal,
        'Record your rehearsal',
        'Open the Final Rehearsal',
      }.contains(widget.properties.label),
);

SceneRehearsalRecord _rehearsal(
  String sessionId, {
  String? sentAt,
  String contentType = 'audio/wav',
}) => SceneRehearsalRecord(
  rehearsalId: '$sessionId-ensaio-1',
  sessionId: sessionId,
  n: 1,
  scene: 'S1',
  recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
  sentAt: sentAt ?? '2026-10-22T10:00:00+00:00',
  durationMs: 7000,
  frases: const [
    SceneFrase(fraseId: 'frase-0', startsMs: 0, endsMs: 3500),
    SceneFrase(fraseId: 'frase-1', startsMs: 3500, endsMs: 7000),
  ],
  contentType: contentType,
  verified: true,
);

TakeView _joinedPart(int n, {String? setAsideAt}) => TakeView(
  takeId: 'gravacao-$n',
  kind: 'ensaio',
  scope: KeptScope.parte(n),
  ordinal: n,
  pass: 1,
  origin: 'cena-$n',
  setAsideAt: setAsideAt,
);

const _roomWhole = TakeView(
  takeId: 'gravacao-inteira',
  kind: 'ensaio',
  scope: KeptScope.whole,
  pass: 1,
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int beats = 30,
}) async {
  for (var vez = 0; vez < beats && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapTheDot(WidgetTester tester) async {
  await tester.tap(_dot);
  await tester.pump(const Duration(milliseconds: 100));
}

bool? _enabled(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

/// A fresh passage at rest on the Conversation; [seed] fills the passage's scene
/// rehearsals once the session is known.
Future<(SalaHarness, ProviderContainer)> _atRest(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  List<SceneRehearsalRecord> Function(String session)? seed,
  void Function(SalaHarness harness)? before,
}) async {
  final harness = SalaHarness(lingua: lingua, filaEmMemoria: true)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes;
  before?.call(harness);
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
  if (seed != null) {
    harness.room.sceneRehearsals.addAll(
      seed(container.read(salaSessionProvider).sessionId!),
    );
  }
  return (harness, container);
}

/// A passage left at [stage] whose room holds [roomTakes]; one left in the Rehearsal on a
/// tablet that lost its files reaches the home by the orange dot.
Future<(SalaHarness, ProviderContainer)> _reopened(
  WidgetTester tester, {
  required List<TakeView> roomTakes,
  SalaStage stage = SalaStage.conversa,
  List<KeptTake> keptTakes = const [],
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  void Function(SalaHarness harness)? before,
}) async {
  final harness = SalaHarness(lingua: lingua, filaEmMemoria: true)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes
    ..room.openedSessions.add('sessao-antiga')
    ..room.takes.addAll(roomTakes);
  before?.call(harness);
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: stage,
    language: lingua,
    takes: keptTakes,
  );
  final pelaEscolha = stage != SalaStage.ensaio;
  if (pelaEscolha) {
    harness.emAberto.rows['Ruth/P01/$lingua'] = row;
  } else {
    await holdTheSession(harness, row, language: lingua);
  }
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  if (!pelaEscolha) {
    if (keptTakes.every((take) => File(take.path).existsSync())) {
      await intoTheRecordingHome(
        notifier,
        read,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
    } else {
      await waitFor(
        'a sala pousar na conversa',
        () => read().station is Canvas && !read().awaitingTheGuide,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      notifier.openTheEnsaioFinal();
      await waitFor(
        'as partes da sala chegarem à casa',
        () => read().station == const Ensaio(),
        step: () => letTheRehearsalReachTheRoom(tester),
      );
    }
    await tester.pump(const Duration(seconds: 1));
    return (harness, container);
  }
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  for (
    var vez = 0;
    vez < 30 &&
        !(container.read(salaSessionProvider).stage == stage &&
            !container.read(salaSessionProvider).awaitingTheGuide);
    vez++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
  return (harness, container);
}

/// The room holds parts 1 to 3, each joined from its scene's rehearsal, and the team
/// stands on the recording home over them.
Future<(SalaHarness, ProviderContainer)> _onTheJoinedHome(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  void Function(SalaHarness harness)? before,
}) async {
  final (harness, container) = await _reopened(
    tester,
    lingua: lingua,
    scenes: scenes,
    roomTakes: [
      for (final n in [1, 2, 3]) _joinedPart(n),
    ],
    before: before,
  );
  await _tapTheDot(tester);
  await _settles(tester);
  await _settles(tester);
  return (harness, container);
}

/// The plan read runs out at 6 s and the choice stands; the held list is let go.
Future<(SalaHarness, ProviderContainer)> _onTheChoice(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  String contentType = 'audio/wav',
  bool rehearsed = true,
}) async {
  final (harness, container) = await _atRest(
    tester,
    lingua: lingua,
    scenes: scenes,
    seed: (session) => [
      if (rehearsed) _rehearsal(session, contentType: contentType),
    ],
  );
  harness.room.holdNextSceneList();
  await _tapTheDot(tester);
  await tester.pump(const Duration(milliseconds: 5900));
  await tester.pump(const Duration(milliseconds: 200));
  harness.room.finishHeldSceneList();
  await _settles(tester);
  return (harness, container);
}

/// The choice answered «A passagem inteira», the plan it opened over the rehearsal
/// answered «gravar a passagem inteira de uma vez»: the team on the empty whole home.
Future<(SalaHarness, ProviderContainer)> _onTheEmptyWholeHome(
  WidgetTester tester, {
  String contentType = 'audio/wav',
}) async {
  final (harness, container) = await _onTheChoice(
    tester,
    contentType: contentType,
  );
  await _tap(tester, _whole);
  await _settles(tester);
  await _tap(tester, _wholeAtOnce);
  await _settles(tester);
  return (harness, container);
}

/// A take the team recorded by hand for [scene], still on the tablet, unsent.
Future<PendingTake> _aHandTakeHeld(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container, {
  required int scene,
}) async {
  final held = PendingTake(
    id: 'a-mao-$scene',
    path: '/gravacoes/parte-$scene.m4a',
    sessionId: container.read(salaSessionProvider).sessionId!,
    kind: 'ensaio',
    scope: KeptScope.parte(scene),
    passNumber: 1,
    chunkIndex: scene,
  );
  (harness.takes as FakeTakeQueue).rows.add(held);
  unawaited(container.read(salaSessionProvider.notifier).refreshUnsent());
  await _settles(tester);
  return held;
}

File _anAudioFile(String scope) {
  final folder = Directory.systemTemp.createTempSync('sala-2078');
  addTearDown(() => folder.deleteSync(recursive: true));
  return File('${folder.path}/$scope.m4a')..writeAsBytesSync([1, 2, 3, 4]);
}

void _waitsInTheOutbox(SalaHarness harness, String scope, File audio) {
  harness.room.unreachableTake = 'ensaio/$scope';
  (harness.takes as FakeTakeQueue).rows.add(
    PendingTake(
      id: 'na-fila-$scope',
      path: audio.path,
      sessionId: 'sessao-antiga',
      kind: 'ensaio',
      scope: scope,
      passNumber: 1,
      chunkIndex: KeptScope.numberOf(scope),
    ),
  );
}

Future<void> _recordAndKeep(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.gravarACena(1);
  await _settles(tester);
  notifier.gravarACena(1);
  await _settles(tester);
  notifier.takeKeep();
  await _settles(tester);
  await letTheRehearsalReachTheRoom(tester);
}

Future<ProviderContainer> _relaunchOnTheApp(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final (_, next) = await relaunch(
    harness,
    container,
    filaEmMemoria: true,
    tester: tester,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: next, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = next.read(salaSessionProvider.notifier);
  await intoTheRecordingHome(
    notifier,
    () => next.read(salaSessionProvider),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return next;
}

void main() {
  testWidgets(
    '1. the plan read that runs out at 6 s shows «Como vocês querem gravar?», '
    'and «Cena por cena» opens the Ensaio Final plan',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room.holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 5800));

      expect(find.text(_thinking), findsOneWidget);
      expect(find.text(_how), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_oneRecording), findsOneWidget);
      expect(find.text(_sceneByScene), findsOneWidget);
      expect(find.text('3 partes'), findsOneWidget);
      expect(find.text(_thinking), findsNothing);

      harness.room.finishHeldSceneList();
      await _settles(tester);
      harness.room.holdNextSceneList();
      await _tap(tester, _sceneByScene);

      expect(harness.room.grainSwitches, [(grain: Grain.scene, reopens: true)]);
      expect(find.text(_thinking), findsOneWidget);

      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '1. «Cena por cena» whose plan read runs out with the room unread opens the '
    'scene home, never «Como vocês querem gravar?» again',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester);
      harness.room
        ..holdNextTakesList()
        ..holdNextSceneList();

      await _tap(tester, _sceneByScene);
      await _settles(tester);
      expect(find.text(_thinking), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 6000));
      await _settles(tester);

      expect(
        find.text(_homeLine),
        findsOneWidget,
        reason:
            'a leitura do plano depois de «Cena por cena» esgotava sem a '
            'listagem e perguntava de novo o grão que a sala acabara de '
            'responder; o dela abre a casa das cenas',
      );
      expect(find.text(_wholeInstead), findsOneWidget);
      expect(find.text(_how), findsNothing);
      harness.room
        ..finishHeldTakesList()
        ..finishHeldSceneList();
    },
  );

  testWidgets(
    '2. «A passagem inteira» opens the recording home with one row, the whole',
    (tester) async {
      final (harness, container) = await _onTheChoice(tester, rehearsed: false);

      await _tap(tester, _whole);
      await _settles(tester);

      expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: true)]);
      expect(
        find.text(_homeLine),
        findsOneWidget,
        reason:
            'sem ensaio de cena desta sessão, o dela abre a casa da passagem '
            'inteira, não o plano',
      );
      expect(find.text(_whole), findsOneWidget);
      expect(find.text('Cena 1'), findsNothing);
      expect(find.text('Cena 2'), findsNothing);

      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel(_record)),
      );
      await _settles(tester);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Parar')),
      );
      await _settles(tester);
      container.read(salaSessionProvider.notifier).takeKeep();
      await _settles(tester);
      await letTheRehearsalReachTheRoom(tester);

      final kept = harness.room.takesReceivedWhole.last;
      expect(kept.kind, 'ensaio');
      expect(kept.scope, 'passagem-inteira');
      expect(kept.chunkIndex, isNull);
    },
  );

  testWidgets(
    '«A passagem inteira» over a scene rehearsal of this session lands on the '
    'Ensaio Final plan, not on the empty whole home',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester);

      await _tap(tester, _whole);
      await _settles(tester);

      expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: true)]);
      expect(
        find.text(_planLine),
        findsOneWidget,
        reason:
            'a passagem inteira abria a casa vazia, e o dela volta pelo '
            'efScreen e para no plano quando há ensaio de cena',
      );
      expect(find.text(_homeLine), findsNothing);
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '«A passagem inteira» draws the whole home at once and moves to the plan '
    'only when the rehearsals answer with one of this session',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester);
      harness.room.holdNextSceneList();

      await _tap(tester, _whole);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(_homeLine),
        findsOneWidget,
        reason:
            'a escolha esperava a leitura do plano em «pensando…», e o dela '
            'desenha a casa inteira na hora',
      );
      expect(find.text(_thinking), findsNothing);

      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
    },
  );

  testWidgets(
    'a whole recording under way when the rehearsals answer stays on the home, '
    'never moved to the plan',
    (tester) async {
      final (harness, container) = await _onTheChoice(tester);
      harness.room.holdNextSceneList();
      await _tap(tester, _whole);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel(_record)),
      );
      await _settles(tester);

      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsNothing,
        reason:
            'o plano abria por cima da gravação e o microfone era jogado fora',
      );
      expect(
        container.read(salaSessionProvider).ensaio,
        isNot(EnsaioStatus.idle),
      );
    },
  );

  testWidgets(
    '«Gravar cena por cena» tapped before the rehearsals answer keeps the team '
    'on the scene home, never moved to the plan',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester);
      harness.room.holdNextSceneList();
      await _tap(tester, _whole);
      await tester.pump(const Duration(milliseconds: 100));
      await _tap(tester, _sceneInstead);
      await _settles(tester);
      expect(find.text('Cena 1'), findsOneWidget);

      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsNothing,
        reason:
            'a leitura tardia abria o plano por cima da casa por cenas que a '
            'equipe tinha acabado de escolher, e o dela deixa de lado',
      );
      expect(find.text('Cena 1'), findsOneWidget);
    },
  );

  testWidgets(
    'a whole take kept before the rehearsals answer stays on the home, as her '
    'draft with a clip does',
    (tester) async {
      final (harness, container) = await _onTheChoice(tester);
      harness.room.holdNextSceneList();
      await _tap(tester, _whole);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel(_record)),
      );
      await _settles(tester);
      await tester.tap(
        find.descendant(of: byLabel(_whole), matching: byLabel('Parar')),
      );
      await _settles(tester);
      container.read(salaSessionProvider.notifier).takeKeep();
      await _settles(tester);
      expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle);

      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsNothing,
        reason: 'o plano abria por cima de uma passagem já gravada',
      );
      expect(find.text(_homeLine), findsOneWidget);
    },
  );

  testWidgets(
    'after «A passagem inteira» the room answered, a plan read with the '
    'listing unread opens the whole home, not the choice again',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester);
      harness.room.failTakesWith = const NetworkFailed('sem rede');

      await _tap(tester, _whole);
      await _settles(tester);
      await _settles(tester);

      expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: true)]);
      expect(
        find.text(_homeLine),
        findsOneWidget,
        reason:
            'a sala já tinha dito o grão na troca, e a leitura sem a listagem '
            'perguntava a escolha de novo; o dela, sem plano, abre a casa',
      );
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '«Cena por cena» counts the passage\'s scenes on a choice that stood before '
    'they were read, not «0 partes»',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
        before: (harness) =>
            harness.room.failScenesWith = const NetworkFailed('sem rede'),
      );
      harness.room
        ..failScenesWith = null
        ..holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 5900));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_how), findsOneWidget);
      expect(
        find.text('3 partes'),
        findsOneWidget,
        reason:
            'a escolha só contava as cenas que o plano tinha guardado, e dizia '
            '«0 partes» quando a leitura não chegava',
      );
      expect(find.text('0 partes'), findsNothing);
      harness.room.finishHeldSceneList();
      await _settles(tester);
    },
  );

  testWidgets(
    'the choice counts the scenes from the ask the plan read already sent, '
    'never a second ask on the same slow link',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        before: (harness) =>
            harness.room.failScenesWith = const NetworkFailed('sem rede'),
      );
      harness.room
        ..failScenesWith = null
        ..holdNextScenes();
      final asked = harness.room.calls.where((c) => c == 'scenesOf').length;

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(_how), findsOneWidget);
      expect(
        harness.room.calls.where((c) => c == 'scenesOf').length - asked,
        1,
        reason:
            'a escolha pedia as cenas de novo com o pedido do plano ainda no ar',
      );

      harness.room.finishHeldScenes();
      await _settles(tester);

      expect(find.text('3 partes'), findsOneWidget);
    },
  );

  testWidgets(
    '3. a passage the room answers with no scenes shows the choice without the '
    '6 s wait',
    (tester) async {
      await _atRest(tester, scenes: const []);

      await _tapTheDot(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_thinking), findsNothing);
    },
  );

  testWidgets(
    'a part an earlier visit kept on the tablet never answers for the grain, '
    'the room naming none shows the choice',
    (tester) async {
      final audio = _anAudioFile(KeptScope.parte(1));
      final (_, container) = await _reopened(
        tester,
        stage: SalaStage.ensaio,
        scenes: const [],
        roomTakes: const [],
        keptTakes: [KeptTake(scopeId: KeptScope.parte(1), path: audio.path)],
        before: (harness) =>
            _waitsInTheOutbox(harness, KeptScope.parte(1), audio),
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      await _tapTheDot(tester);
      await _settles(tester);

      expect(container.read(salaSessionProvider).partes, hasLength(1));
      expect(
        find.text(_how),
        findsOneWidget,
        reason:
            'a gravação que ficou no tablet decidia o grão, e a sala não '
            'nomeava nenhum',
      );
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    'a part an earlier visit kept on the tablet never answers for the grain at '
    'the 6 s cut, the room\'s listing naming none',
    (tester) async {
      final audio = _anAudioFile(KeptScope.parte(1));
      final (harness, container) = await _reopened(
        tester,
        stage: SalaStage.ensaio,
        roomTakes: const [],
        keptTakes: [KeptTake(scopeId: KeptScope.parte(1), path: audio.path)],
        before: (harness) =>
            _waitsInTheOutbox(harness, KeptScope.parte(1), audio),
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      await _settles(tester);

      expect(container.read(salaSessionProvider).partes, hasLength(1));
      expect(
        find.text(_how),
        findsOneWidget,
        reason:
            'com a listagem lida e sem grão, o corte dos 6 s abria a casa do '
            'grão que o tablet tirou das suas gravações',
      );
      expect(find.text(_homeLine), findsNothing);
      harness.room.finishHeldSceneList();
    },
  );

  testWidgets(
    '4. rehearsals in the other language\'s session show the choice under her line',
    (tester) async {
      await _atRest(tester, seed: (_) => [_rehearsal('outra-sessao')]);

      await _tapTheDot(tester);
      await _settles(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_elsewhere), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_sceneByScene), findsOneWidget);
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    'a hand take still on the tablet does not hide the other language\'s line, '
    'the choice stands under it',
    (tester) async {
      final (harness, container) = await _atRest(
        tester,
        seed: (_) => [_rehearsal('outra-sessao')],
      );
      await _aHandTakeHeld(tester, harness, container, scene: 1);

      await _tapTheDot(tester);
      await _settles(tester);

      expect(
        find.text(_elsewhere),
        findsOneWidget,
        reason:
            'a gravação que só estava no tablet escondia a linha da outra '
            'língua',
      );
      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_sceneByScene), findsOneWidget);
    },
  );

  testWidgets(
    'a part an earlier visit kept on the tablet does not hide the other '
    'language\'s line, the choice stands under it',
    (tester) async {
      final audio = _anAudioFile(KeptScope.parte(1));
      final (_, container) = await _reopened(
        tester,
        stage: SalaStage.ensaio,
        roomTakes: const [],
        keptTakes: [KeptTake(scopeId: KeptScope.parte(1), path: audio.path)],
        before: (harness) {
          _waitsInTheOutbox(harness, KeptScope.parte(1), audio);
          harness.room.sceneRehearsals.add(_rehearsal('outra-sessao'));
        },
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      await _tapTheDot(tester);
      await _settles(tester);

      expect(container.read(salaSessionProvider).partes, hasLength(1));
      expect(
        find.text(_elsewhere),
        findsOneWidget,
        reason:
            'a gravação que voltou ao tablet escondia a linha da outra língua',
      );
      expect(find.text(_how), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
    },
  );

  testWidgets(
    'a whole-passage take an earlier visit kept on the tablet is offered on the '
    'choice by the passage\'s name, never as a scene',
    (tester) async {
      final audio = _anAudioFile(KeptScope.whole);
      final (harness, container) = await _reopened(
        tester,
        stage: SalaStage.ensaio,
        scenes: const [],
        roomTakes: const [],
        keptTakes: [KeptTake(scopeId: KeptScope.whole, path: audio.path)],
        before: (harness) {
          _waitsInTheOutbox(harness, KeptScope.whole, audio);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);

      await _tapTheDot(tester);
      await _settles(tester);

      expect(container.read(salaSessionProvider).partes, hasLength(1));
      expect(find.text(_how), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'a gravação da passagem inteira guardada no tablet era oferecida '
            'como «Cena 1»',
      );
      expect(find.text('Cena 1 · 0:48 — enviar agora'), findsNothing);
      expect(harness.room.takesReceivedWhole, isEmpty);
    },
  );

  testWidgets(
    '5. with a grain in force, the 6 s cut opens that grain\'s home, never the '
    'choice',
    (tester) async {
      final (harness, _) = await _atRest(tester);
      harness.room.grain = Grain.whole;
      harness.room.holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      await _settles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(find.text('Cena 1'), findsNothing);
      expect(find.text(_how), findsNothing);
      harness.room.finishHeldSceneList();
    },
  );

  testWidgets(
    'with a grain only in memory, the 6 s cut with no listing read shows the '
    'choice, not that grain\'s home',
    (tester) async {
      final (harness, _) = await _onTheEmptyWholeHome(tester);
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room
        ..holdNextTakesList()
        ..holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      await _settles(tester);

      expect(
        find.text(_how),
        findsOneWidget,
        reason:
            'sem a listagem da sala, o tablet abria a casa do grão que lembrava, '
            'e o dela mostra a escolha',
      );
      expect(find.text(_homeLine), findsNothing);
      harness.room
        ..finishHeldTakesList()
        ..finishHeldSceneList();
    },
  );

  testWidgets(
    'with a grain only in memory, a listing that fails shows the choice, not '
    'that grain\'s home',
    (tester) async {
      final (harness, _) = await _onTheEmptyWholeHome(tester);
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.failTakesWith = const NetworkFailed('sem rede');

      await _tapTheDot(tester);
      await _settles(tester);

      expect(
        find.text(_how),
        findsOneWidget,
        reason:
            'a listagem que falhou abria a casa do grão lembrado, e o dela, sem '
            'o rascunho lido, mostra a escolha',
      );
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    'on the choice over a grain in memory, a tap on that grain the room does not '
    'answer stays on the choice and says nothing',
    (tester) async {
      final (harness, _) = await _onTheEmptyWholeHome(tester);
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.failTakesWith = const NetworkFailed('sem rede');
      await _tapTheDot(tester);
      await _settles(tester);
      harness.room.grainAnswersFirst.add(const NetworkFailed('sem rede'));
      final switches = harness.room.grainSwitches.length;
      final played = harness.voice.played.length;
      final lines = harness.voice.fixedLines.length;

      await _tap(tester, _whole);
      await _settles(tester);

      expect(
        harness.room.grainSwitches.skip(switches),
        [(grain: Grain.whole, reopens: true)],
        reason: 'o grão lembrado abria a casa sem perguntar à sala',
      );
      expect(find.text(_how), findsOneWidget);
      expect(find.text(_homeLine), findsNothing);
      expect(_enabled(tester, _wholeChoice), isTrue);
      expect(_enabled(tester, _sceneChoice), isTrue);
      expect(thePersonSign, findsNothing);
      expect(harness.voice.played, hasLength(played));
      expect(harness.voice.fixedLines, hasLength(lines));

      harness.room.failTakesWith = null;
      await _tap(tester, _whole);
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '6. after a join, «gravar a passagem inteira de uma vez» arms with her text '
    'and a second tap 2 s later calls the grain door; the parts are no longer '
    'shown',
    (tester) async {
      final (harness, container) = await _onTheJoinedHome(tester);
      for (final n in [1, 2, 3]) {
        expect(find.text('Cena $n'), findsOneWidget);
      }
      expect(byLabel(_recordAgain), findsNWidgets(3));

      await _tap(tester, _wholeAtOnce);

      expect(find.text(_wholeArmed), findsOneWidget);
      expect(harness.room.grainSwitches, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await _tap(tester, _wholeArmed);
      await _settles(tester);

      expect(harness.room.grainSwitches, [
        (grain: Grain.whole, reopens: false),
      ]);
      expect(find.text(_whole), findsOneWidget);
      expect(byLabel(_recordAgain), findsNothing);
      for (final n in [1, 2, 3]) {
        expect(find.text('Cena $n'), findsNothing);
      }

      final fetched = harness.room.clipsFetched.length;
      await _relaunchOnTheApp(tester, harness, container);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(byLabel(_recordAgain), findsNothing);
      expect(find.text('Cena 1'), findsNothing);
      expect(harness.room.clipsFetched.length, fetched);
    },
  );

  testWidgets('7. a second tap after 0.3 s does nothing', (tester) async {
    final (harness, _) = await _onTheJoinedHome(tester);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(milliseconds: 200));
    await _tap(tester, _wholeArmed);
    await _settles(tester);

    expect(find.text(_wholeArmed), findsOneWidget);
    expect(harness.room.grainSwitches, isEmpty);
    expect(byLabel(_recordAgain), findsNWidgets(3));
    await tester.pump(_theArmLapses);
  });

  testWidgets(
    'on the recording home, VoiceOver focus leaving the armed whole switch '
    'reads «gravar a passagem inteira de uma vez» again, and the next tap only '
    'arms',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _onTheJoinedHome(tester);
      await _tap(tester, _wholeAtOnce);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_wholeArmed), findsOneWidget);

      voiceOverFocusLeaves(tester, byLabel(_wholeArmed));
      await _settles(tester);

      expect(
        find.text(_wholeAtOnce),
        findsOneWidget,
        reason: 'na casa o botão seguia armado depois que o foco saiu dele',
      );
      expect(find.text(_wholeArmed), findsNothing);

      await _tap(tester, _wholeAtOnce);
      await _settles(tester);

      expect(find.text(_wholeArmed), findsOneWidget);
      expect(
        harness.room.grainSwitches,
        isEmpty,
        reason: 'o toque seguinte trocava o grão em vez de só armar',
      );
      await tester.pump(_theArmLapses);
      semantics.dispose();
    },
  );

  testWidgets('8. a second tap after 8 s does nothing: the arm lapsed', (
    tester,
  ) async {
    final (harness, _) = await _onTheJoinedHome(tester);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 8));

    expect(find.text(_wholeAtOnce), findsOneWidget);
    expect(find.text(_wholeArmed), findsNothing);

    await _tap(tester, _wholeAtOnce);

    expect(find.text(_wholeArmed), findsOneWidget);
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
  });

  testWidgets(
    '9. with no joined scene, «gravar a passagem inteira de uma vez» on the plan '
    'switches in one tap',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      await _tapTheDot(tester);
      await _settles(tester);
      expect(find.text(_planLine), findsOneWidget);

      await _tap(tester, _wholeAtOnce);
      await _settles(tester);

      expect(harness.room.grainSwitches, [
        (grain: Grain.whole, reopens: false),
      ]);
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(find.text('Cena 1'), findsNothing);
    },
  );

  testWidgets(
    'with no joined scene, «gravar a passagem inteira de uma vez» on the plan '
    'is a plain button to VoiceOver, never one that reads not pressed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _atRest(tester, seed: (session) => [_rehearsal(session)]);
      await _tapTheDot(tester);
      await _settles(tester);
      expect(find.text(_planLine), findsOneWidget);

      expect(
        tester.getSemantics(byLabel(_wholeAtOnce)),
        isSemantics(isButton: true, hasToggledState: false),
        reason: 'o VoiceOver lia como solto um botão que troca num toque só',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'Q4. an empty whole recording opens the plan, and «gravar a passagem inteira '
    'de uma vez» there returns to the whole home with no switch',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room.grain = Grain.whole;
      await _tapTheDot(tester);
      await _settles(tester);
      expect(find.text(_planLine), findsOneWidget);

      await _tap(tester, _wholeAtOnce);
      await _settles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(harness.room.grainSwitches, isEmpty);
    },
  );

  testWidgets(
    'on the plan of a passage recorded whole, a whole-passage take left on the '
    'tablet is named by the passage, not as scene 1',
    (tester) async {
      final (harness, container) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room
        ..grain = Grain.whole
        ..unreachableTake = 'ensaio/${KeptScope.whole}';
      harness.playback.measured = const Duration(seconds: 48);
      final audio = _anAudioFile(KeptScope.whole);
      (harness.takes as FakeTakeQueue).rows.add(
        PendingTake(
          id: 'na-fila-inteira',
          path: audio.path,
          sessionId: container.read(salaSessionProvider).sessionId!,
          kind: 'ensaio',
          scope: KeptScope.whole,
          passNumber: 1,
        ),
      );

      await _tapTheDot(tester);
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'sob o grão da passagem inteira, a gravação da passagem inteira era '
            'oferecida como «Cena 1»',
      );
      expect(find.text('Cena 1 · 0:48 — enviar agora'), findsNothing);
    },
  );

  testWidgets(
    'an empty whole recording with no scene rehearsal of the session opens the '
    'whole-passage home, not the plan',
    (tester) async {
      final (harness, _) = await _atRest(tester);
      harness.room.grain = Grain.whole;

      await _tapTheDot(tester);
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsNothing,
        reason:
            'o ponto abria o plano vazio sobre a passagem inteira, onde o dela '
            'abre a tela de gravar a passagem inteira',
      );
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(harness.room.grainSwitches, isEmpty);
    },
  );

  testWidgets(
    'an empty whole recording with only an unsent scene rehearsal of the session '
    'still opens the plan',
    (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [
          SceneRehearsalRecord(
            rehearsalId: '$session-ensaio-1',
            sessionId: session,
            n: 1,
            scene: 'S1',
            recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
            durationMs: 7000,
            frases: const [
              SceneFrase(fraseId: 'frase-0', startsMs: 0, endsMs: 3500),
            ],
            contentType: 'audio/wav',
            verified: true,
          ),
        ],
      );
      harness.room.grain = Grain.whole;

      await _tapTheDot(tester);
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason: 'um ensaio da cena ainda não enviado não contava como ensaio',
      );
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    '10. over an approved draft the whole switch arms with «toquem de novo: isto '
    'abre de novo o rascunho aprovado» and goes up with the re-open',
    (tester) async {
      final (harness, _) = await _onTheJoinedHome(
        tester,
        before: (harness) =>
            harness.room.approvedDraft = const ApprovedDraft(version: 1),
      );

      await _tap(tester, _wholeAtOnce);

      expect(find.text(_reopenArmed), findsOneWidget);
      expect(find.text(_wholeArmed), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await _tap(tester, _reopenArmed);
      await _settles(tester);

      expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: true)]);
      expect(find.text(_whole), findsOneWidget);
    },
  );

  testWidgets(
    '11. a refused switch over a draft the tablet did not know was approved arms '
    'on the next tap',
    (tester) async {
      final (harness, _) = await _onTheJoinedHome(tester);
      harness.room.approvedDraft = const ApprovedDraft(version: 1);

      await _tap(tester, _wholeAtOnce);
      await tester.pump(const Duration(seconds: 2));
      await _tap(tester, _wholeArmed);
      await _settles(tester);

      expect(harness.room.grainSwitches, [
        (grain: Grain.whole, reopens: false),
      ]);
      expect(byLabel(_recordAgain), findsNWidgets(3));
      expect(find.text(_wholeAtOnce), findsOneWidget);
      expect(thePersonSign, findsNothing);

      await _tap(tester, _wholeAtOnce);

      expect(find.text(_reopenArmed), findsOneWidget);
      await tester.pump(_theArmLapses);
    },
  );

  testWidgets(
    'on the choice over a draft the tablet knows is approved, one tap opens '
    'that grain\'s home, never her armed text',
    (tester) async {
      final (harness, container) = await _onTheJoinedHome(
        tester,
        before: (harness) =>
            harness.room.approvedDraft = const ApprovedDraft(version: 1),
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.failTakesWith = const NetworkFailed('sem rede');
      await _tapTheDot(tester);
      await _settles(tester);
      expect(find.text(_how), findsOneWidget);
      expect(container.read(salaSessionProvider).overAnApprovedDraft, isTrue);
      harness.room.failTakesWith = null;
      final switches = harness.room.grainSwitches.length;

      await _tap(tester, _whole);

      expect(
        find.text(_reopenArmed),
        findsNothing,
        reason:
            'o botão do grão armava com «toquem de novo» sobre o rascunho '
            'aprovado, e o dela age no primeiro toque',
      );
      await _settles(tester);

      expect(
        harness.room.grainSwitches.skip(switches),
        [(grain: Grain.whole, reopens: true)],
        reason: 'o primeiro toque só armava, sem chamar a sala',
      );
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    'on the choice over an approved draft, a tap on the grain the room already '
    'holds keeps the approval and the parts',
    (tester) async {
      final (harness, container) = await _onTheJoinedHome(
        tester,
        before: (harness) =>
            harness.room.approvedDraft = const ApprovedDraft(version: 1),
      );
      await tester.tap(byLabel(_backToPassage));
      await _settles(tester);
      harness.room.failTakesWith = const NetworkFailed('sem rede');
      await _tapTheDot(tester);
      await _settles(tester);
      expect(find.text(_how), findsOneWidget);
      harness.room.failTakesWith = null;
      final switches = harness.room.grainSwitches.length;

      await _tap(tester, _sceneByScene);
      await _settles(tester);
      await _settles(tester);

      expect(harness.room.grainSwitches.skip(switches), [
        (grain: Grain.scene, reopens: true),
      ]);
      expect(
        harness.room.approvedDraft,
        isNotNull,
        reason:
            'o toque no grão que a sala já tinha levava o reabrir e desfazia a '
            'aprovação',
      );
      expect(
        container.read(salaSessionProvider).overAnApprovedDraft,
        isTrue,
        reason:
            'a sessão lida depois do toque já não trazia a aprovação, num toque '
            'que não mudou nada',
      );
      expect(byLabel(_recordAgain), findsNWidgets(3));
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '11. on the choice over a draft the tablet did not know was approved, the '
    'one tap re-opens it and opens the home, not a refusal',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester, rehearsed: false);
      harness.room.approvedDraft = const ApprovedDraft(version: 1);

      await _tap(tester, _whole);
      await _settles(tester);

      expect(
        harness.room.grainSwitches,
        [(grain: Grain.whole, reopens: true)],
        reason:
            'a escolha subia sem reabrir, a sala recusava, e a equipe ficava '
            'na escolha tocando de novo',
      );
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_how), findsNothing);
    },
  );

  testWidgets(
    '12. a switch whose answer is lost after the room acted opens the grain the '
    'room holds',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester, rehearsed: false);
      harness.room.loseTheNextGrainAnswer = true;

      await _tap(tester, _whole);
      await _settles(tester);

      expect(harness.room.grainSwitches, hasLength(1));
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(thePersonSign, findsNothing);
    },
  );

  group('1. a listing that answers after the 6 s cut', () {
    testWidgets('with a grain in force takes the team off the choice', (
      tester,
    ) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room
        ..grain = Grain.scene
        ..holdTheTakesListing();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_how), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      harness.room.finishTheTakesListing();
      await _settles(tester);

      expect(find.text(_how), findsNothing);
      expect(find.text(_planLine), findsOneWidget);
    });

    testWidgets(
      'naming the scene grain reads the plan again with the grain heard: a '
      'read that runs out there opens the scene home, never the choice again',
      (tester) async {
        final (harness, _) = await _atRest(
          tester,
          seed: (session) => [_rehearsal(session)],
        );
        harness.room
          ..grain = Grain.scene
          ..holdTheTakesListing();

        await _tapTheDot(tester);
        await tester.pump(const Duration(milliseconds: 6000));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(_how), findsOneWidget);

        harness.room
          ..holdNextTakesList()
          ..holdNextSceneList()
          ..finishTheTakesListing();
        await _settles(tester);
        expect(find.text(_thinking), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 6000));
        await _settles(tester);

        expect(
          find.text(_homeLine),
          findsOneWidget,
          reason:
              'a listagem tardia que nomeava as cenas relia o plano com o grão '
              'por ouvir, e a releitura esgotada perguntava o grão de novo; o '
              'dela, com o rascunho lido, abre a casa das cenas',
        );
        expect(find.text(_wholeInstead), findsOneWidget);
        expect(find.text(_how), findsNothing);
        harness.room
          ..finishHeldTakesList()
          ..finishHeldSceneList();
      },
    );

    testWidgets(
      'naming the whole over a scene rehearsal of this session lands on the '
      'plan, not on the empty whole home',
      (tester) async {
        final (harness, _) = await _atRest(
          tester,
          seed: (session) => [_rehearsal(session)],
        );
        harness.room
          ..grain = Grain.whole
          ..holdTheTakesListing();

        await _tapTheDot(tester);
        await tester.pump(const Duration(milliseconds: 6000));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(_how), findsOneWidget);

        harness.room.finishTheTakesListing();
        await _settles(tester);
        await _settles(tester);

        expect(
          find.text(_planLine),
          findsOneWidget,
          reason:
              'a listagem tardia abria a casa inteira vazia, e o dela passa '
              'pelo efScreen e para no plano',
        );
        expect(find.text(_how), findsNothing);
      },
    );

    testWidgets('never overwrites the grain the team chose after it', (
      tester,
    ) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room
        ..grain = Grain.whole
        ..holdTheTakesListing();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6100));
      expect(find.text(_how), findsOneWidget);

      await _tap(tester, _sceneByScene);
      await _settles(tester);
      expect(find.text(_planLine), findsOneWidget);

      harness.room.finishTheTakesListing();
      await _settles(tester);
      expect(find.text(_planLine), findsOneWidget);

      await _tap(tester, _sceneInstead);
      await _settles(tester);

      expect(harness.room.grainSwitches, [(grain: Grain.scene, reopens: true)]);
      expect(find.text(_homeLine), findsOneWidget);
    });
  });

  testWidgets(
    'a join row of the earlier grain still in the Outbox is no scene\'s join on '
    'the plan over an empty whole recording',
    (tester) async {
      final (harness, container) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      harness.room
        ..grain = Grain.whole
        ..unreachableTake = 'ensaio/${KeptScope.parte(1)}';
      (harness.takes as FakeTakeQueue).rows.add(
        PendingTake(
          id: 'juntada-1',
          path: '/nao/existe/parte-1.m4a',
          sessionId: container.read(salaSessionProvider).sessionId!,
          kind: 'ensaio',
          scope: KeptScope.parte(1),
          passNumber: 1,
          origin: 'cena-1',
        ),
      );

      await _tapTheDot(tester);
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_missing), findsNWidgets(2));
    },
  );

  testWidgets(
    'a join row of the earlier grain still in the Outbox does not hold the plan '
    'over an empty whole recording with no scene rehearsal',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      harness.room
        ..grain = Grain.whole
        ..unreachableTake = 'ensaio/${KeptScope.parte(1)}';
      (harness.takes as FakeTakeQueue).rows.add(
        PendingTake(
          id: 'juntada-1',
          path: '/nao/existe/parte-1.m4a',
          sessionId: container.read(salaSessionProvider).sessionId!,
          kind: 'ensaio',
          scope: KeptScope.parte(1),
          passNumber: 1,
          origin: 'cena-1',
        ),
      );

      await _tapTheDot(tester);
      await _settles(tester);

      expect(
        find.text(_planLine),
        findsNothing,
        reason:
            'a linha da junta do grão anterior deixava o plano vazio de pé sobre '
            'a passagem inteira',
      );
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
    },
  );

  testWidgets(
    'a whole the disk refused stays the whole\'s: after «Gravar cena por cena» no '
    'scene row shows it or sends it',
    (tester) async {
      final (harness, container) = await _onTheEmptyWholeHome(tester);
      (harness.takes as FakeTakeQueue).refusesTheNextKeep = true;
      await _recordAndKeep(tester, container);
      expect(find.text(_failed), findsOneWidget);

      await _tap(tester, _sceneInstead);
      await _settles(tester);

      expect(find.text('Cena 1'), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      container.read(salaSessionProvider.notifier).enviarACena(1);
      await letTheRehearsalReachTheRoom(tester);
      expect(
        harness.room.takesReceivedWhole.where(
          (take) => take.scope == KeptScope.parte(1),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'a whole the disk refused is set aside by the switch: back on the whole it '
    'never shows «falhou» again and never goes up',
    (tester) async {
      final (harness, container) = await _onTheEmptyWholeHome(tester);
      (harness.takes as FakeTakeQueue).refusesTheNextKeep = true;
      await _recordAndKeep(tester, container);
      expect(find.text(_failed), findsOneWidget);

      await _tap(tester, _sceneInstead);
      await _settles(tester);
      await _tap(tester, _wholeInstead);
      await _settles(tester);

      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      container.read(salaSessionProvider.notifier).enviarACena(1);
      await letTheRehearsalReachTheRoom(tester);
      expect(
        harness.room.takesReceivedWhole.where(
          (take) => take.scope == KeptScope.whole,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'a scene part the disk refused stays the scene\'s: after «Gravar a passagem '
    'inteira» the whole row neither shows it nor sends it',
    (tester) async {
      final (harness, container) = await _onTheChoice(tester);
      await _tap(tester, _sceneByScene);
      await _settles(tester);
      await _tap(tester, _sceneInstead);
      await _settles(tester);
      (harness.takes as FakeTakeQueue).refusesTheNextKeep = true;
      await _recordAndKeep(tester, container);
      expect(find.text(_failed), findsOneWidget);

      await _tap(tester, _wholeInstead);
      await _settles(tester);

      expect(find.text(_whole), findsOneWidget);
      expect(find.text(_failed), findsNothing);
      container.read(salaSessionProvider.notifier).enviarACena(1);
      await letTheRehearsalReachTheRoom(tester);
      expect(
        harness.room.takesReceivedWhole.where(
          (take) => take.scope == KeptScope.whole,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'another tablet\'s switch to scene by scene, learned from the room\'s listing, '
    'opens the scene rows at the 6 s cut, with the whole it set aside nowhere',
    (tester) async {
      final (harness, _) = await _atRest(tester);
      harness.room
        ..takes.add(
          const TakeView(
            takeId: 'gravacao-inteira',
            kind: 'ensaio',
            scope: KeptScope.whole,
            pass: 1,
            setAsideAt: FakeRoom.grainSwitchedAt,
          ),
        )
        ..grain = Grain.scene
        ..holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6000));
      harness.room.finishHeldSceneList();
      await _settles(tester);

      expect(find.text(_how), findsNothing);
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text('Cena 1'), findsOneWidget);
      expect(find.text(_whole), findsNothing);
      expect(byLabel(_recordAgain), findsNothing);
      expect(harness.room.clipsFetched, isEmpty);
    },
  );

  testWidgets(
    'a whole the disk refused shows «falhou» on the whole row and goes up whole',
    (tester) async {
      final (harness, container) = await _onTheEmptyWholeHome(tester);
      (harness.takes as FakeTakeQueue).refusesTheNextKeep = true;

      await _recordAndKeep(tester, container);

      expect(find.text(_failed), findsOneWidget);

      await _tap(tester, _failed);
      await letTheRehearsalReachTheRoom(tester);
      await _settles(tester);

      final kept = harness.room.takesReceivedWhole.last;
      expect(kept.scope, KeptScope.whole);
      expect(kept.chunkIndex, isNull);
      expect(find.text(_failed), findsNothing);
    },
  );

  testWidgets('12. a switch the room does not answer changes nothing', (
    tester,
  ) async {
    final (harness, _) = await _onTheChoice(tester, rehearsed: false);
    harness.room.grainAnswersFirst.add(const NetworkFailed('sem rede'));
    final played = harness.voice.played.length;
    final lines = harness.voice.fixedLines.length;

    await _tap(tester, _whole);
    await _settles(tester);

    expect(find.text(_how), findsOneWidget);
    expect(find.text(_homeLine), findsNothing);
    expect(_enabled(tester, _wholeChoice), isTrue);
    expect(_enabled(tester, _sceneChoice), isTrue);
    expect(thePersonSign, findsNothing);
    expect(harness.voice.played, hasLength(played));
    expect(harness.voice.fixedLines, hasLength(lines));

    await _tap(tester, _whole);
    await _settles(tester);

    expect(find.text(_homeLine), findsOneWidget);
    expect(find.text(_whole), findsOneWidget);
  });

  testWidgets(
    '13. while the switch is in the air, the grain controls are closed and the '
    'new grain\'s home waits for the door',
    (tester) async {
      final (harness, _) = await _onTheChoice(tester, rehearsed: false);
      harness.room.holdTheGrainSwitch();

      await _tap(tester, _whole);

      expect(_enabled(tester, _wholeChoice), isFalse);
      expect(_enabled(tester, _sceneChoice), isFalse);
      expect(find.text(_homeLine), findsNothing);

      await _tap(tester, _sceneByScene);
      await _tap(tester, _whole);

      expect(harness.room.grainSwitches, hasLength(1));

      harness.room.finishTheGrainSwitch();
      await _settles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(harness.room.grainSwitches, hasLength(1));
    },
  );

  testWidgets(
    'a VoiceOver double-tap on «$_sceneInstead» on the home switches the grain, '
    'as a finger does',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _onTheEmptyWholeHome(tester);
      final switches = harness.room.grainSwitches.length;

      voiceOverTap(tester, _sceneInstead);
      await _settles(tester);

      expect(
        harness.room.grainSwitches,
        hasLength(switches + 1),
        reason:
            'o VoiceOver anunciava o botão e o toque duplo não trocava nada',
      );
      expect(find.text('Cena 1'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('a VoiceOver double-tap on «$_wholeChoice» chooses the whole, as '
      'a finger does', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _onTheChoice(tester, rehearsed: false);

    voiceOverTap(tester, _wholeChoice);
    await _settles(tester);

    expect(
      harness.room.grainSwitches,
      [(grain: Grain.whole, reopens: true)],
      reason: 'o VoiceOver anunciava a escolha e o toque duplo não escolhia',
    );
    expect(find.text(_homeLine), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('while the switch is in the air the two choices offer VoiceOver '
      'no tap', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _onTheChoice(tester);
    harness.room.holdTheGrainSwitch();

    await _tap(tester, _whole);

    for (final choice in [_wholeChoice, _sceneChoice]) {
      expect(
        tester.getSemantics(byLabel(choice)),
        isSemantics(hasTapAction: false),
        reason: 'a escolha apagada ainda oferecia o toque ao leitor',
      );
    }
    harness.room.finishTheGrainSwitch();
    await _settles(tester);
    semantics.dispose();
  });

  group('14. «Ensaio Final: juntar os ensaios das cenas»', () {
    testWidgets('is offered over an empty whole recording and opens the plan', (
      tester,
    ) async {
      final (harness, _) = await _onTheEmptyWholeHome(tester);

      await _tap(tester, _backToJoin);
      await _settles(tester);

      expect(harness.room.grainSwitches.last, (
        grain: Grain.scene,
        reopens: false,
      ));
      expect(find.text(_planLine), findsOneWidget);
    });

    testWidgets(
      'armed over an approved draft, VoiceOver focus leaving it reads its own '
      'text again, and the next tap only arms',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, container) = await _onTheEmptyWholeHome(tester);
        harness.room.approvedDraft = const ApprovedDraft(version: 1);
        await _relaunchOnTheApp(tester, harness, container);
        await _settles(tester);
        await _tap(tester, _backToJoin);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text(_reopenArmed), findsOneWidget);

        voiceOverFocusLeaves(tester, byLabel(_reopenArmed));
        await _settles(tester);

        expect(
          find.text(_backToJoin),
          findsOneWidget,
          reason: 'a linha seguia armada depois que o foco do VoiceOver saiu',
        );
        expect(find.text(_reopenArmed), findsNothing);
        final before = harness.room.grainSwitches.length;

        await _tap(tester, _backToJoin);
        await _settles(tester);

        expect(find.text(_reopenArmed), findsOneWidget);
        expect(
          harness.room.grainSwitches,
          hasLength(before),
          reason: 'o toque seguinte voltava para a junção em vez de só armar',
        );
        await tester.pump(_theArmLapses);
        semantics.dispose();
      },
    );
    testWidgets('is gone once the whole has a take', (tester) async {
      final (_, container) = await _onTheEmptyWholeHome(tester);

      await _recordAndKeep(tester, container);

      expect(find.text(_backToJoin), findsNothing);
      expect(find.text(_sceneInstead), findsOneWidget);
    });

    testWidgets('is not offered when no scene rehearsal can be joined', (
      tester,
    ) async {
      final (_, container) = await _onTheEmptyWholeHome(
        tester,
        contentType: 'audio/webm',
      );

      expect(container.read(salaSessionProvider).recordsTheWhole, isTrue);
      expect(container.read(salaSessionProvider).partes, isEmpty);
      expect(
        find.text(_backToJoin),
        findsNothing,
        reason:
            'a linha voltava para uma junção que não teria o que juntar: o único '
            'ensaio da cena não é um WAV',
      );
    });

    testWidgets(
      'leaves «Gravar cena por cena» in place, one tap to the scene rows',
      (tester) async {
        final (harness, _) = await _onTheEmptyWholeHome(
          tester,
          contentType: 'audio/webm',
        );

        await _tap(tester, _sceneInstead);
        await _settles(tester);

        expect(harness.room.grainSwitches.last.grain, Grain.scene);
        for (final n in [1, 2, 3]) {
          expect(find.text('Cena $n'), findsOneWidget);
        }
      },
    );

    testWidgets('is not offered while the scene rehearsals could not be read', (
      tester,
    ) async {
      final (harness, container) = await _onTheChoice(tester);
      harness.room.sceneListsAnswerFirst.addAll(const [
        NetworkFailed('sem rede'),
        NetworkFailed('sem rede'),
      ]);

      await _tap(tester, _whole);
      await _settles(tester);

      expect(container.read(salaSessionProvider).recordsTheWhole, isTrue);
      expect(find.text(_sceneInstead), findsOneWidget);
      expect(
        find.text(_backToJoin),
        findsNothing,
        reason:
            'sem a lista dos ensaios a linha aparecia mesmo assim, sem saber se '
            'havia o que juntar',
      );
    });

    testWidgets(
      'is not offered while the only joinable scene\'s hand take is held on '
      'the tablet',
      (tester) async {
        final (harness, container) = await _onTheEmptyWholeHome(tester);
        await _aHandTakeHeld(tester, harness, container, scene: 1);

        expect(container.read(salaSessionProvider).recordsTheWhole, isTrue);
        expect(find.text(_sceneInstead), findsOneWidget);
        expect(
          find.text(_backToJoin),
          findsNothing,
          reason:
              'a linha contava a cena cuja gravação à mão o tablet ainda não '
              'enviou, e a junção passaria por cima dela',
        );
      },
    );

    testWidgets('comes back once that hand take is sent', (tester) async {
      final (harness, container) = await _onTheEmptyWholeHome(tester);
      final held = await _aHandTakeHeld(tester, harness, container, scene: 1);
      expect(find.text(_backToJoin), findsNothing);

      final rows = (harness.takes as FakeTakeQueue).rows;
      rows[rows.indexOf(held)] = held.copyWith(stored: true);
      unawaited(container.read(salaSessionProvider.notifier).refreshUnsent());
      await _settles(tester);

      expect(
        find.text(_backToJoin),
        findsOneWidget,
        reason:
            'a cena continuava fora da junção depois que a gravação à mão '
            'chegou à sala',
      );
    });
  });

  testWidgets(
    '15. «Gravar cena por cena» on the whole home switches in one tap to the '
    'scene rows',
    (tester) async {
      final (harness, container) = await _onTheEmptyWholeHome(tester);
      await _recordAndKeep(tester, container);
      expect(byLabel(_recordAgain), findsOneWidget);

      await _tap(tester, _sceneInstead);
      await _settles(tester);

      expect(harness.room.grainSwitches.last.grain, Grain.scene);
      for (final n in [1, 2, 3]) {
        expect(find.text('Cena $n'), findsOneWidget);
      }
      expect(byLabel(_recordAgain), findsNothing);
      expect(find.text(_whole), findsNothing);

      final played = harness.playback.played.length;
      await tester.tap(byLabel('Ouvir'));
      await _settles(tester);

      expect(harness.playback.played, hasLength(played));
    },
  );

  group('16. a take the room set aside is never a part on the tablet', () {
    testWidgets('a relaunch whose parts are gone brings back only the current '
        'whole', (tester) async {
      final (harness, _) = await _reopened(
        tester,
        stage: SalaStage.ensaio,
        keptTakes: [
          for (final n in [1, 2, 3])
            KeptTake(
              scopeId: KeptScope.parte(n),
              path: '/nao/existe/parte-$n.m4a',
              takeId: 'gravacao-$n',
            ),
        ],
        roomTakes: [
          for (final n in [1, 2, 3])
            _joinedPart(n, setAsideAt: FakeRoom.grainSwitchedAt),
          _roomWhole,
        ],
        before: (harness) => harness.room.grain = Grain.whole,
      );
      await _settles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_whole), findsOneWidget);
      expect(byLabel(_recordAgain), findsOneWidget);
      expect(find.text('Cena 1'), findsNothing);
      expect(harness.room.clipsFetched, hasLength(1));
      expect(harness.room.clipsFetched.single, contains(_roomWhole.takeId));
    });

    testWidgets('the dot over set-aside joined parts is «Gravar o ensaio de '
        'vocês»', (tester) async {
      final semantics = tester.ensureSemantics();
      await _reopened(
        tester,
        roomTakes: [
          for (final n in [1, 2, 3])
            _joinedPart(n, setAsideAt: FakeRoom.grainSwitchedAt),
          _roomWhole,
        ],
        before: (harness) => harness.room.grain = Grain.whole,
      );
      await _settles(tester);

      expect(find.bySemanticsLabel(_recordEnsaio), findsOneWidget);
      expect(find.bySemanticsLabel(_openEnsaioFinal), findsNothing);
      semantics.dispose();
    });
  });

  test('16. scene parts the tablet still holds are never current once the room '
      'records the passage whole', () {
    final state = SalaSessionState(
      grainInForce: Grain.whole,
      keptTakes: [
        for (final n in [1, 2, 3])
          KeptTake(
            scopeId: KeptScope.parte(n),
            path: '/gravacoes/parte-$n.m4a',
            takeId: 'gravacao-$n',
          ),
      ],
    );

    expect(state.partes, isEmpty);
    expect(state.everySceneHasItsPart, isFalse);
    expect(state.sceneRows.single.part, isNull);
  });

  test('16. a whole the room set aside is no part while it records scene by '
      'scene', () {
    const state = SalaSessionState(
      grainInForce: Grain.scene,
      keptTakes: [
        KeptTake(
          scopeId: KeptScope.whole,
          path: '/gravacoes/inteiro.m4a',
          takeId: 'gravacao-inteira',
        ),
      ],
    );

    expect(state.partes, isEmpty);
  });

  test('16. while the room records the passage whole, the whole is never set '
      'aside', () {
    const state = SalaSessionState(
      grainInForce: Grain.whole,
      keptTakes: [
        KeptTake(
          scopeId: KeptScope.whole,
          path: '/gravacoes/inteiro.m4a',
          takeId: 'gravacao-inteira',
        ),
        KeptTake(
          scopeId: 'parte-1',
          path: '/gravacoes/parte-1.m4a',
          takeId: 'gravacao-1',
        ),
      ],
      wholeHeldByTheRoom: {'gravacao-inteira'},
    );

    expect(state.wholeSetAside, isEmpty);
    expect(state.partes.single.takeId, 'gravacao-inteira');
  });

  group('17. the choice and a switch say nothing', () {
    testWidgets('across the choice and «A passagem inteira»', (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      final played = harness.voice.played.length;
      final lines = harness.voice.fixedLines.length;
      harness.room.holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6100));
      harness.room.finishHeldSceneList();
      await _settles(tester);
      expect(find.text(_how), findsOneWidget);
      await _tap(tester, _whole);
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(harness.voice.played, hasLength(played));
      expect(harness.voice.fixedLines, hasLength(lines));
    });

    testWidgets('across the choice and «Cena por cena»', (tester) async {
      final (harness, _) = await _atRest(
        tester,
        seed: (session) => [_rehearsal(session)],
      );
      final played = harness.voice.played.length;
      final lines = harness.voice.fixedLines.length;
      harness.room.holdNextSceneList();

      await _tapTheDot(tester);
      await tester.pump(const Duration(milliseconds: 6100));
      harness.room.finishHeldSceneList();
      await _settles(tester);
      await _tap(tester, _sceneByScene);
      await _settles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(harness.voice.played, hasLength(played));
      expect(harness.voice.fixedLines, hasLength(lines));
    });

    testWidgets('across the armed switch over a join', (tester) async {
      final (harness, _) = await _onTheJoinedHome(tester);
      final played = harness.voice.played.length;
      final lines = harness.voice.fixedLines.length;

      await _tap(tester, _wholeAtOnce);
      await tester.pump(const Duration(seconds: 2));
      await _tap(tester, _wholeArmed);
      await _settles(tester);

      expect(harness.room.grainSwitches, hasLength(1));
      expect(harness.voice.played, hasLength(played));
      expect(harness.voice.fixedLines, hasLength(lines));
    });
  });

  group('18. an English room reads her English', () {
    testWidgets('on the choice and the whole home', (tester) async {
      await _onTheChoice(tester, lingua: 'en', scenes: _threeScenesEn);

      expect(find.text('How would you like to record it?'), findsOneWidget);
      expect(find.text('The whole passage'), findsOneWidget);
      expect(find.text('one recording'), findsOneWidget);
      expect(find.text('Scene by scene'), findsOneWidget);
      expect(find.text('3 parts'), findsOneWidget);

      await _tap(tester, 'The whole passage');
      await _settles(tester);
      await _tap(tester, 'record the whole passage in one go');
      await _settles(tester);

      expect(find.text('Record scene by scene instead'), findsOneWidget);
      expect(
        find.text('Final Rehearsal: join the scene rehearsals'),
        findsOneWidget,
      );
    });

    testWidgets('on a joined home', (tester) async {
      await _onTheJoinedHome(tester, lingua: 'en', scenes: _threeScenesEn);

      await _tap(tester, 'record the whole passage in one go');

      expect(
        find.text('tap again: the scenes and the translations are kept'),
        findsOneWidget,
      );
      await tester.pump(_theArmLapses);
    });
  });
}
