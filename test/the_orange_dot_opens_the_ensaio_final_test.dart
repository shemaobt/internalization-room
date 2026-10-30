import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheRecordingHome,
        relaunch,
        settle,
        thePersonSign;
import 'um_ensaio_de_tres_partes.dart' show Sala;

const _recordEnsaio = 'Gravar o ensaio de vocês';
const _openEnsaioFinal = 'Abrir o Ensaio Final';
const _recordEnsaioEn = 'Record your rehearsal';
const _openEnsaioFinalEn = 'Open the Final Rehearsal';

const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _thinking = 'pensando…';
const _pendingNotice =
    'Uma gravação ainda está neste computador e não foi enviada.';
const _sendSceneOne = 'Cena 1 · 0:48 — enviar agora';
const _sceneByScene = 'Gravar cena por cena';
const _how = 'Como vocês querem gravar?';
final _backToPassage = roomLabelFor('backToPassage', 'pt');

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
const _lastScene = Moment(at: MomentAt.articulation, part: 3, parts: 3);
const _sendOff = Moment(at: MomentAt.ensaioFinal, parts: 3);

const _handReply = HandReply(id: 'r1', audioUrl: '/resposta/r1');

const _thePassage = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

const _thePanorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {
        _recordEnsaio,
        _openEnsaioFinal,
        _recordEnsaioEn,
        _openEnsaioFinalEn,
      }.contains(widget.properties.label),
);

final _label = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('Momento da sessão') ?? false),
);

double _dotOpacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: _dot, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

bool _dotIsDeaf(WidgetTester tester) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: _dot, matching: find.byType(IgnorePointer)),
    )
    .any((pointer) => pointer.ignoring);

String _labelWords(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _label, matching: find.byType(Text)))
    .map((text) => text.data)
    .join();

Color? _labelTint(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(of: _label, matching: find.byType(Container)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .map((decoration) => decoration.border)
    .whereType<Border>()
    .first
    .top
    .color;

Finder _row(int n, List<Scene> scenes) =>
    byLabel('Cena $n — ${scenes[n - 1].title}');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
  int beats = 30,
}) async {
  for (var vez = 0; vez < beats && !done(); vez++) {
    await tester.pump(beat);
  }
}

Future<void> _arriveAtRest(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

Future<(SalaHarness, ProviderContainer)> _atRest(
  WidgetTester tester, {
  String lingua = 'pt',
  Moment moment = _midConversation,
  List<Scene> scenes = _threeScenes,
  List<HandReply> replies = const [],
}) async {
  final harness =
      SalaHarness(lingua: lingua, filaEmMemoria: true, replies: replies)
        ..room.passages = const [_thePassage]
        ..room.nextMoment = moment
        ..room.passageScenes = scenes;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _arriveAtRest(tester, container);
  return (harness, container);
}

/// A passage left on the Conversation whose room already holds part 1, [origin] naming
/// the scene rehearsal it was joined from, if any.
Future<(SalaHarness, ProviderContainer)> _reopenedOverPartOne(
  WidgetTester tester, {
  required String? origin,
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
}) => _reopenedOnTheConversation(
  tester,
  lingua: lingua,
  scenes: scenes,
  roomTakes: [
    TakeView(
      takeId: 'gravacao-1',
      kind: 'ensaio',
      scope: KeptScope.parte(1),
      ordinal: 1,
      pass: 1,
      origin: origin,
    ),
  ],
);

/// A passage left on the Conversation whose room holds [roomTakes].
Future<(SalaHarness, ProviderContainer)> _reopenedOnTheConversation(
  WidgetTester tester, {
  required List<TakeView> roomTakes,
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
  harness.emAberto.rows['Ruth/P01/$lingua'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.conversa,
    language: lingua,
  );
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () =>
        container.read(salaSessionProvider).stage == SalaStage.conversa &&
        !container.read(salaSessionProvider).awaitingTheGuide,
  );
  await tester.pump(const Duration(seconds: 1));
  return (harness, container);
}

TakeView _roomPart(int n, {required int pass, String? origin}) => TakeView(
  takeId: 'gravacao-$n',
  kind: 'ensaio',
  scope: KeptScope.parte(n),
  ordinal: n,
  pass: pass,
  origin: origin,
);

/// Part 1 of the passage waits in the Outbox for a room that cannot take it.
void _partOneWaitsInTheOutbox(SalaHarness harness) {
  final waiting = Directory.systemTemp.createTempSync('sala-1382-fila');
  addTearDown(() => waiting.deleteSync(recursive: true));
  final audio = File('${waiting.path}/ensaio-parte-1.m4a')
    ..writeAsBytesSync([1, 2, 3, 4]);
  harness.room.unreachableTake = 'ensaio/${KeptScope.parte(1)}';
  (harness.takes as FakeTakeQueue).rows.add(
    PendingTake(
      id: 'na-fila-1',
      path: audio.path,
      sessionId: 'sessao-antiga',
      kind: 'ensaio',
      scope: KeptScope.parte(1),
      passNumber: 1,
      chunkIndex: 1,
    ),
  );
}

void _theWholeWaitsInTheOutbox(SalaHarness harness) {
  final waiting = Directory.systemTemp.createTempSync('sala-2078-inteira');
  addTearDown(() => waiting.deleteSync(recursive: true));
  final audio = File('${waiting.path}/ensaio-inteiro.m4a')
    ..writeAsBytesSync([1, 2, 3, 4]);
  harness.room.unreachableTake = 'ensaio/${KeptScope.whole}';
  (harness.takes as FakeTakeQueue).rows.add(
    PendingTake(
      id: 'na-fila-inteira',
      path: audio.path,
      sessionId: 'sessao-antiga',
      kind: 'ensaio',
      scope: KeptScope.whole,
      passNumber: 1,
    ),
  );
}

Future<void> _recordAgain(
  WidgetTester tester,
  ProviderContainer container,
  int n,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.gravarACena(n);
  await _theAnswerSettles(tester);
  notifier.gravarACena(n);
  await _theAnswerSettles(tester);
  notifier.takeKeep();
  await _theAnswerSettles(tester);
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _tapTheDot(WidgetTester tester) async {
  await tester.tap(_dot);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _theAnswerSettles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _theNextReplyPlays(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
  Moment moment,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.room.nextMoment = moment;
  harness.voice.holdNextLine();
  notifier.conversaTap();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.conversaTap();
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.speaking,
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
}

Future<void> _theHandReplyPlays(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).hasUnheardReply,
    beats: 200,
  );
  harness.voice.holdNextLine();
  container.read(salaSessionProvider.notifier).handTap();
  await _pumpUntil(
    tester,
    () => harness.voice.played.contains(_handReply.audioUrl),
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(harness.voice.played, contains(_handReply.audioUrl));
  expect(container.read(salaSessionProvider).playingReplyId, _handReply.id);
}

Future<void> _theReplyEnds(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.voice.finishHeldLine();
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice != VoiceState.speaking,
  );
  await tester.pump(const Duration(milliseconds: 500));
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
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => !next.read(salaSessionProvider).awaitingTheGuide,
  );
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return next;
}

const _onePart = Duration(seconds: 48);

/// The passage's rehearsal on a real Outbox and a real disk: the room holds a whole an app
/// before 19 August sent, set aside behind parts 1 to 3.
class _Home {
  final WidgetTester tester;
  final Directory home;
  SalaHarness harness;
  ProviderContainer container;

  _Home(this.tester, this.home, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get read => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get takeReads => room.calls.where((call) => call == 'takesOf').length;

  int get sends => room.calls.where((call) => call == 'sendTake').length;

  List<int?> passesOfPart(int n) => [
    for (var i = 0; i < room.takesReceived.length; i++)
      if (room.takesReceived[i].scope == KeptScope.parte(n)) room.takePasses[i],
  ];

  Finder onRow(int n, Finder target) =>
      find.descendant(of: _row(n, _threeScenes), matching: target);

  Future<void> inRealTime(Future<void> Function() body) async {
    await tester.runAsync(body);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> recordAndKeep(int n) => inRealTime(() async {
    sala.gravarACena(n);
    await waitFor(
      'a cena $n gravar',
      () => read.ensaio == EnsaioStatus.recording,
    );
    sala.gravarACena(n);
    await waitFor(
      'a gravação da cena $n esperar o visto',
      () => read.ensaio == EnsaioStatus.recorded,
    );
    final before = sends;
    sala.takeKeep();
    await waitFor('a cena $n subir', () => sends > before);
    await settle(const Duration(milliseconds: 300));
  });

  Future<void> relaunchIt() async {
    await relaunchOnTheConversation();
    await inRealTime(() async {
      container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
      await _theRowsStand();
    });
  }

  Future<void> relaunchOnTheConversation() async {
    late SalaHarness again;
    late ProviderContainer next;
    await tester.runAsync(() async {
      container.dispose();
      await harness.takes.flush();
      (again, next) = await relaunch(harness, container);
      again.playback.measured = _onePart;
      next.read(salaSessionProvider);
    });
    harness = again;
    container = next;
    await tester.pumpWidget(_theHome(container));
    await inRealTime(() async {
      await _launch(container);
      await waitFor(
        'a sala voltar à conversa',
        () => read.stage == SalaStage.conversa && !read.awaitingTheGuide,
      );
      await settle();
    });
  }

  Future<void> _theRowsStand() async {
    await waitFor(
      'a sala voltar à casa do ensaio',
      () =>
          read.stage == SalaStage.ensaio &&
          read.sceneRows.length == _threeScenes.length,
    );
    await settle(const Duration(milliseconds: 600));
  }

  void expectThreeRecordedRows() {
    for (final n in [1, 2, 3]) {
      expect(
        onRow(n, byLabel('Ouvir')),
        findsOneWidget,
        reason: 'a linha $n não estava gravada',
      );
    }
  }
}

Widget _theHome(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: EnsaioView()),
  ),
);

Future<void> _launch(ProviderContainer container) async {
  final sala = container.read(salaSessionProvider.notifier);
  await container.read(deviceLinkProvider.notifier).findTheTeam();
  await sala.refreshUnsent();
  await sala.openTheRoom();
}

const _theWhole = TakeView(
  takeId: 'gravacao-inteira',
  kind: 'ensaio',
  scope: KeptScope.whole,
  pass: 1,
);

TakeView _part(int n) => TakeView(
  takeId: 'gravacao-parte-$n',
  kind: 'ensaio',
  scope: KeptScope.parte(n),
  ordinal: n,
  pass: 1,
);

/// The tablet holds parts 1 to 3 under [takes] (a missing file sends the first launch to
/// the room), and the room holds the whole and the same three parts.
Future<_Home> _reopenOverTheWholeSetAside(
  WidgetTester tester, {
  required List<KeptTake> Function(Directory guardadas) takes,
  bool fromTheChoice = false,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final home = Directory.systemTemp.createTempSync('sala-1382-inteiro');
  addTearDown(() => home.deleteSync(recursive: true));
  final guardadas = Directory('${home.path}/guardadas')..createSync();
  final harness = SalaHarness(takesHome: home)
    ..room.passageScenes = _threeScenes
    ..room.openedSessions.add('sessao-antiga')
    ..room.takes.addAll([_theWhole, _part(1), _part(2), _part(3)])
    ..playback.measured = _onePart;
  final held = takes(guardadas);
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: held,
  );
  final pelaEscolha =
      fromTheChoice ||
      held.any(
        (take) =>
            take.scopeId != KeptScope.whole && !File(take.path).existsSync(),
      );
  if (pelaEscolha) {
    harness.emAberto.rows['Ruth/P01/pt'] = row;
  } else {
    await holdTheSession(harness, row);
  }
  final container = (await tester.runAsync(
    () async => harness.container()..read(salaSessionProvider),
  ))!;
  addTearDown(() => container.dispose());
  await tester.pumpWidget(_theHome(container));
  final it = _Home(tester, home, harness, container);
  await it.inRealTime(() async {
    if (pelaEscolha) {
      await it.sala.abrirEscolha();
      await settle();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
    } else {
      await it.sala.openTheRoom();
      await intoTheRecordingHome(it.sala, () => it.read);
    }
    await it._theRowsStand();
  });
  return it;
}

KeptTake _heldPart(Directory guardadas, int n, {bool onDisk = true}) {
  final file = File('${guardadas.path}/ensaio-parte-$n.m4a');
  if (onDisk) file.writeAsBytesSync([1, 2, 3, 4]);
  return KeptTake(
    scopeId: KeptScope.parte(n),
    path: file.path,
    takeId: 'gravacao-parte-$n',
  );
}

List<KeptTake> _partThreeGone(Directory guardadas) => [
  _heldPart(guardadas, 1),
  _heldPart(guardadas, 2),
  _heldPart(guardadas, 3, onDisk: false),
];

void main() {
  KeptTake byHand(int n) =>
      KeptTake(scopeId: KeptScope.parte(n), path: 'parte-$n.m4a');

  test('a joined part the team recorded again by hand names the dot «Gravar o '
      'ensaio de vocês» again', () {
    final state = SalaSessionState(
      theRoomJoinedParts: const {1},
      keptTakes: [byHand(1)],
    );

    expect(state.aPartWasJoined, isFalse);
  });

  test('a part recorded by hand on the tablet beside a part the room joined '
      'names the dot «Abrir o Ensaio Final»', () {
    final state = SalaSessionState(
      theRoomJoinedParts: const {2},
      keptTakes: [byHand(1)],
    );

    expect(state.aPartWasJoined, isTrue);
  });

  test('a joined part only the room lists names the dot «Abrir o Ensaio '
      'Final»', () {
    const state = SalaSessionState(theRoomJoinedParts: {1});

    expect(state.aPartWasJoined, isTrue);
  });

  testWidgets(
    'mid-conversation the dot is faint and opens the Ensaio Final plan',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _atRest(tester);

      expect(_dotOpacity(tester), closeTo(0.22, 0.001));
      expect(_dotIsDeaf(tester), isFalse);
      expect(
        tester.getSemantics(_dot),
        isSemantics(label: _recordEnsaio, hasTapAction: true),
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text('Ensaio Final'), findsOneWidget);
      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_homeLine), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the send-off brightens the dot and the label stays in orange, past the '
    'red microphone and a relaunch',
    (tester) async {
      final (harness, container) = await _atRest(tester, moment: _lastScene);

      await _theNextReplyPlays(tester, harness, container, _sendOff);
      await _theReplyEnds(tester, harness, container);

      expect(_dotOpacity(tester), closeTo(0.85, 0.001));
      expect(_labelWords(tester), 'Ensaio Final · a passagem inteira');
      expect(_labelTint(tester), const Color(0xFFBE4A01));

      final notifier = container.read(salaSessionProvider.notifier);
      notifier.openTheSceneRehearsal();
      await _theAnswerSettles(tester);
      notifier.leaveTheSceneRehearsal();
      await _theAnswerSettles(tester);

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(_labelWords(tester), 'Ensaio Final · a passagem inteira');
      expect(_dotOpacity(tester), closeTo(0.85, 0.001));

      await _relaunchOnTheApp(tester, harness, container);

      expect(_labelWords(tester), 'Ensaio Final · a passagem inteira');
      expect(_labelTint(tester), const Color(0xFFBE4A01));
      expect(_dotOpacity(tester), closeTo(0.85, 0.001));
    },
  );

  testWidgets(
    'while the voice speaks there is no dot, and a tap where it stood cuts nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _atRest(tester);
      await _theNextReplyPlays(tester, harness, container, _midConversation);
      final stops = harness.voice.stops;

      expect(_dotOpacity(tester), 0.0);
      expect(_dotIsDeaf(tester), isTrue);
      expect(find.semantics.byLabel(_recordEnsaio), findsNothing);

      container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.voice.stops, stops, reason: 'o toque calou a voz');
      expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      await _theReplyEnds(tester, harness, container);
      semantics.dispose();
    },
  );

  testWidgets(
    'while the turn\'s microphone listens there is no dot, and a tap where it '
    'stood keeps the take',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _atRest(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(salaSessionProvider).voice, VoiceState.listening);
      final discards = harness.sounds
          .where((sound) => sound == 'recorder:discard')
          .length;

      expect(_dotOpacity(tester), 0.0);
      expect(_dotIsDeaf(tester), isTrue);
      expect(find.semantics.byLabel(_recordEnsaio), findsNothing);

      notifier.openTheEnsaioFinal();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        harness.sounds.where((sound) => sound == 'recorder:discard').length,
        discards,
        reason: 'o toque descartou a fala da equipe',
      );
      expect(container.read(salaSessionProvider).voice, VoiceState.listening);
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      semantics.dispose();
    },
  );

  testWidgets(
    'while the raised hand\'s reply plays the dot stays faint, keeps its name '
    'and takes a touch',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _atRest(
        tester,
        replies: const [_handReply],
      );
      await _theHandReplyPlays(tester, harness, container);

      expect(
        _dotOpacity(tester),
        closeTo(0.22, 0.001),
        reason: 'o ponto sumia enquanto a resposta do facilitador tocava',
      );
      expect(_dotIsDeaf(tester), isFalse);
      expect(
        tester.getSemantics(_dot),
        isSemantics(label: _recordEnsaio, hasTapAction: true),
      );
      harness.voice.finishHeldLine();
      await _theAnswerSettles(tester);
      semantics.dispose();
    },
  );

  testWidgets(
    'a touch on the dot while the raised hand\'s reply plays stops the reply, '
    'leaves it unheard on the hand, and opens the plan',
    (tester) async {
      final (harness, container) = await _atRest(
        tester,
        replies: const [_handReply],
      );
      await _theHandReplyPlays(tester, harness, container);
      final stops = harness.voice.stops;

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(
        harness.voice.stops,
        greaterThan(stops),
        reason: 'a resposta seguia tocando por cima do plano',
      );
      expect(find.text(_planLine), findsOneWidget);
      harness.voice.finishHeldLine();
      await _theAnswerSettles(tester);
      expect(
        harness.inbox.heard,
        isEmpty,
        reason: 'a resposta cortada pelo ponto foi marcada ouvida na mesa',
      );
      expect(
        container.read(salaSessionProvider).hasUnheardReply,
        isTrue,
        reason: 'a resposta cortada saiu da mão',
      );
      expect(container.read(salaSessionProvider).playingReplyId, isNull);
    },
  );

  Future<void> sendANote(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.handTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.conversaTap();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).voice == VoiceState.listening,
    );
    await tester.pump(const Duration(seconds: 2));
    notifier.conversaTap();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'while a sent note goes out the dot stays faint and takes a touch, and the '
    'touch opens the plan with the note still on its way to the facilitator',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      harness.inbox.holdNextQuestion();
      await sendANote(tester, container);
      expect(harness.inbox.questionsSent, isEmpty);

      expect(
        _dotOpacity(tester),
        closeTo(0.22, 0.001),
        reason: 'o ponto sumia depois de cada pergunta enviada',
      );
      expect(_dotIsDeaf(tester), isFalse);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_planLine), findsOneWidget);

      harness.inbox.finishHeldQuestion();
      await _theAnswerSettles(tester);

      expect(
        harness.inbox.questionsSent,
        hasLength(1),
        reason: 'o toque no ponto segurou a pergunta longe do facilitador',
      );
    },
  );

  testWidgets(
    'a touch on the dot while a sent note\'s microphone still closes does '
    'nothing, and the note reaches the facilitator',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      harness.recorder.holdNextStop();
      await sendANote(tester, container);
      expect(harness.inbox.questionsSent, isEmpty);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      harness.recorder.finishStop();
      await _theAnswerSettles(tester);
      expect(
        harness.inbox.questionsSent,
        hasLength(1),
        reason:
            'o toque no ponto enquanto o microfone fechava perdia a pergunta',
      );
    },
  );

  testWidgets(
    'a touch on the dot while a second note records, the first still going '
    'out, throws the second away and opens the plan',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      final notifier = container.read(salaSessionProvider.notifier);
      harness.inbox.holdNextQuestion();
      await sendANote(tester, container);
      notifier.handTap();
      await tester.pump(const Duration(milliseconds: 300));
      notifier.conversaTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).voice == VoiceState.listening,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(container.read(salaSessionProvider).noteMode, isTrue);
      final discards = harness.sounds
          .where((sound) => sound == 'recorder:discard')
          .length;

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason: 'o toque no ponto não fazia nada com a segunda nota gravando',
      );
      expect(
        harness.sounds.where((sound) => sound == 'recorder:discard').length,
        greaterThan(discards),
      );
      harness.inbox.finishHeldQuestion();
      await _theAnswerSettles(tester);
      expect(harness.inbox.questionsSent, hasLength(1));
    },
  );

  testWidgets(
    'an earlier note that reaches the facilitator while a later one\'s '
    'microphone still closes does not free the dot\'s touch, and the later '
    'note still goes out',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      harness.inbox
        ..holdNextQuestion()
        ..holdNextQuestion();
      await sendANote(tester, container);
      harness.recorder.holdNextStop();
      await sendANote(tester, container);
      harness.inbox.finishHeldQuestion();
      await _theAnswerSettles(tester);
      expect(harness.inbox.questionsSent, hasLength(1));

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'a primeira nota, ao chegar, soltava o toque enquanto o microfone '
            'da segunda fechava',
      );
      harness.recorder.finishStop();
      await _theAnswerSettles(tester);
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_planLine), findsOneWidget);
      harness.inbox.finishHeldQuestion();
      await _theAnswerSettles(tester);
      expect(
        harness.inbox.questionsSent,
        hasLength(2),
        reason: 'a segunda nota se perdeu no toque do ponto',
      );
    },
  );

  testWidgets('a note whose sending breaks off brings the dot back', (
    tester,
  ) async {
    final (harness, container) = await _atRest(tester);
    harness.inbox.knotThrows = Exception('a ligação caiu no meio');

    await sendANote(tester, container);
    await _theAnswerSettles(tester);

    expect(_dotOpacity(tester), closeTo(0.22, 0.001));
    expect(_dotIsDeaf(tester), isFalse);
  });

  testWidgets('a Panorama never shows the dot', (tester) async {
    final harness = SalaHarness(watchesWithoutAHalt: true)
      ..room.passages = const [_thePanorama, _thePassage]
      ..room.done = true
      ..room.nextMoment = _sendOff;
    final container = await pumpSala(tester, harness);
    addTearDown(() => closeTheRoom(container));
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.openTheEntry(_thePanorama);
    for (var beat = 0; beat < 100; beat++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_dot, findsNothing, reason: 'o ponto apareceu no Panorama');
    }
    expect(container.read(salaSessionProvider).panoramaSaid, isTrue);
    expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
    closeTheRoom(container);
  });

  testWidgets(
    'a part the room joined names the dot «Abrir o Ensaio Final» and the dot '
    'opens the recording home',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _reopenedOverPartOne(tester, origin: 'cena-1');

      expect(find.bySemanticsLabel(_openEnsaioFinal), findsOneWidget);
      expect(find.semantics.byLabel(_recordEnsaio), findsNothing);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
      expect(
        find.descendant(of: _row(1, _threeScenes), matching: byLabel('Ouvir')),
        findsOneWidget,
        reason: 'a linha 1 não trazia a parte da sala',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a slow part opens the recording home by 6 seconds, with the way out, and '
    'the room\'s part comes in behind its row',
    (tester) async {
      final (harness, _) = await _reopenedOverPartOne(tester, origin: 'cena-1');
      harness.room.clipDelay = const Duration(seconds: 30);

      await _tapTheDot(tester);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_thinking), findsNothing);
      expect(byLabel(_backToPassage), findsOneWidget);

      await tester.pump(const Duration(seconds: 25));
      await _theAnswerSettles(tester);

      expect(
        find.descendant(of: _row(1, _threeScenes), matching: byLabel('Ouvir')),
        findsOneWidget,
        reason: 'a parte da sala não chegou à linha 1',
      );
    },
  );

  testWidgets(
    'a part the room no longer has, recorded again from the dot\'s home, goes '
    'up above the room\'s pass',
    (tester) async {
      final (harness, container) = await _reopenedOnTheConversation(
        tester,
        roomTakes: [_roomPart(1, pass: 1), _roomPart(2, pass: 3)],
        before: (harness) => harness.room.refuseClipOf.add('gravacao-2'),
      );
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_homeLine), findsOneWidget);

      await _recordAgain(tester, container, 2);

      expect(harness.room.takePasses, [4]);
    },
  );

  testWidgets(
    'a part the room holds whose audio cannot be fetched, recorded again from '
    'the dot\'s home, goes up above the room\'s pass',
    (tester) async {
      final (harness, container) = await _reopenedOnTheConversation(
        tester,
        roomTakes: [_roomPart(2, pass: 3)],
      );
      harness.room.failClipWith = const NetworkFailed('sem rede');
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_homeLine), findsOneWidget);
      harness.room.failClipWith = null;

      await _recordAgain(tester, container, 2);

      expect(harness.room.takePasses, [4]);
    },
  );

  testWidgets(
    'with a part waiting in the Outbox the dot\'s home lays in the room\'s '
    'part, and recording it again goes up above the room\'s pass',
    (tester) async {
      final (harness, container) = await _reopenedOnTheConversation(
        tester,
        roomTakes: [_roomPart(2, pass: 3)],
        before: _partOneWaitsInTheOutbox,
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(
        find.descendant(of: _row(2, _threeScenes), matching: byLabel('Ouvir')),
        findsOneWidget,
        reason: 'a linha 2 não trazia a parte da sala',
      );

      await _recordAgain(tester, container, 2);

      expect(harness.room.takePasses.last, 4);
    },
  );

  testWidgets(
    'a take waiting only in the Outbox never decides the dot, the room '
    'listing nothing opens the plan',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: _partOneWaitsInTheOutbox,
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason:
            'a gravação que só estava no tablet abria a casa de gravação, e a '
            'dela abre o plano',
      );
      expect(find.text(_homeLine), findsNothing);
    },
  );

  testWidgets(
    'on the plan a take only on the tablet is offered under her notice, and '
    'a tap sends it',
    (tester) async {
      final (harness, _) = await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: (harness) {
          _partOneWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(
        find.text(_pendingNotice),
        findsOneWidget,
        reason: 'o plano não dizia que uma gravação ficou no tablet',
      );
      expect(
        find.text(_sendSceneOne),
        findsOneWidget,
        reason: 'o plano não oferecia a gravação para enviar',
      );

      harness.room.unreachableTake = null;
      final before = harness.room.takePasses.length;
      await tester.tap(find.text(_sendSceneOne));
      await letTheRehearsalReachTheRoom(tester);
      await _theAnswerSettles(tester);

      expect(
        harness.room.takePasses.length,
        before + 1,
        reason: 'o toque não mandava a gravação para a sala',
      );
    },
  );

  testWidgets(
    'a take sent from the plan\'s notice, once the room has it, opens the '
    'recording home instead of leaving the plan up',
    (tester) async {
      final (harness, _) = await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: (harness) {
          _partOneWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_planLine), findsOneWidget);

      await tester.tap(find.text(_sendSceneOne));
      await letTheRehearsalReachTheRoom(tester);
      await _theAnswerSettles(tester);
      expect(
        find.text(_planLine),
        findsOneWidget,
        reason: 'um envio que não chegou à sala tirava o plano da tela',
      );

      harness.room.unreachableTake = null;
      await tester.tap(find.text(_sendSceneOne));
      await letTheRehearsalReachTheRoom(tester);
      await _theAnswerSettles(tester);

      expect(
        find.text(_homeLine),
        findsOneWidget,
        reason:
            'a gravação chegava à sala e o plano continuava na tela, e o dela '
            'passa para a casa de gravação',
      );
      expect(find.text(_planLine), findsNothing);
    },
  );

  testWidgets(
    'on the grain choice a take only on the tablet is offered under her '
    'notice too',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        scenes: const [],
        before: (harness) {
          _partOneWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text('A passagem inteira'), findsOneWidget);
      expect(find.text('Cena por cena'), findsOneWidget);
      expect(
        find.text(_pendingNotice),
        findsOneWidget,
        reason:
            'a escolha do jeito de gravar não dizia que uma gravação '
            'ficou no tablet',
      );
      expect(find.text(_sendSceneOne), findsOneWidget);
    },
  );

  testWidgets(
    'on the grain choice a whole-passage take only on the tablet is offered '
    'too, named by the passage',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        scenes: const [],
        before: (harness) {
          _theWholeWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_pendingNotice), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'sem grão na sala, a gravação da passagem inteira ficava no tablet '
            'sem ser oferecida',
      );
    },
  );

  testWidgets(
    'on the grain choice a whole-passage take and a scene take both left on the '
    'tablet are offered each by its own name',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        scenes: const [],
        before: (harness) {
          _partOneWaitsInTheOutbox(harness);
          _theWholeWaitsInTheOutbox(harness);
          harness.room.takeAnswersFirst.addAll(
            List.filled(50, const NetworkFailed('sem rede')),
          );
          harness.playback.measured = const Duration(seconds: 48);
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_how), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'ao lado da cena 1, a gravação da passagem inteira não era '
            'oferecida',
      );
      expect(find.text(_sendSceneOne), findsOneWidget);
    },
  );

  testWidgets(
    'a whole-passage take sent from the grain choice reaches the room as the '
    'whole, not as a scene',
    (tester) async {
      final (harness, _) = await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        scenes: const [],
        before: (harness) {
          _theWholeWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      harness.room.unreachableTake = null;
      await tester.tap(find.text('A passagem inteira · 0:48 — enviar agora'));
      await letTheRehearsalReachTheRoom(tester);
      await _theAnswerSettles(tester);

      expect(
        [for (final take in harness.room.takesReceivedWhole) take.scope],
        [KeptScope.whole],
        reason:
            'o «enviar agora» da passagem inteira não mandava nada para a sala',
      );
      expect(find.text(_pendingNotice), findsNothing);
    },
  );

  testWidgets(
    'a scene take sent from the grain choice opens the home of the grain the '
    'room now holds, scene by scene, not one nobody chose',
    (tester) async {
      final (harness, _) = await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        scenes: const [],
        before: (harness) {
          _partOneWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_how), findsOneWidget);

      harness.room.unreachableTake = null;
      await tester.tap(find.text(_sendSceneOne));
      await letTheRehearsalReachTheRoom(tester);
      await _theAnswerSettles(tester);
      await _theAnswerSettles(tester);

      expect(
        find.text(_how),
        findsNothing,
        reason:
            'a gravação mandada da escolha chegava à sala e a pergunta '
            'continuava na tela, e a dela passa para a casa da cena',
      );
      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text('A passagem inteira'), findsNothing);
    },
  );

  testWidgets(
    'a whole-passage take on the tablet is offered on the whole-passage home '
    'under her notice, named by the passage',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: (harness) {
          final waiting = Directory.systemTemp.createTempSync('sala-1861-home');
          addTearDown(() => waiting.deleteSync(recursive: true));
          final audio = File('${waiting.path}/ensaio-inteiro.m4a')
            ..writeAsBytesSync([1, 2, 3, 4]);
          harness.room
            ..grain = Grain.whole
            ..unreachableTake = 'ensaio/${KeptScope.whole}';
          harness.playback.measured = const Duration(seconds: 48);
          (harness.takes as FakeTakeQueue).rows.add(
            PendingTake(
              id: 'na-fila-inteira',
              path: audio.path,
              sessionId: 'sessao-antiga',
              kind: 'ensaio',
              scope: KeptScope.whole,
              passNumber: 1,
            ),
          );
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_pendingNotice), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'a casa da passagem inteira não oferecia a gravação que ficou '
            'no tablet',
      );
    },
  );

  testWidgets(
    'on the plan of a passage the room names no grain for, a whole-passage take '
    'on the tablet is offered too',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: (harness) {
          _theWholeWaitsInTheOutbox(harness);
          harness.playback.measured = const Duration(seconds: 48);
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_pendingNotice), findsOneWidget);
      expect(
        find.text('A passagem inteira · 0:48 — enviar agora'),
        findsOneWidget,
        reason:
            'sem grão na sala, o plano deixava a gravação da passagem inteira '
            'no tablet sem oferecer',
      );
    },
  );

  testWidgets(
    'a whole-passage take on the tablet is never offered on the plan of a '
    'passage recorded scene by scene',
    (tester) async {
      await _reopenedOnTheConversation(
        tester,
        roomTakes: const [],
        before: (harness) {
          final waiting = Directory.systemTemp.createTempSync(
            'sala-1861-whole',
          );
          addTearDown(() => waiting.deleteSync(recursive: true));
          final audio = File('${waiting.path}/ensaio-inteiro.m4a')
            ..writeAsBytesSync([1, 2, 3, 4]);
          harness.room
            ..grain = Grain.scene
            ..unreachableTake = 'ensaio/${KeptScope.whole}';
          (harness.takes as FakeTakeQueue).rows.add(
            PendingTake(
              id: 'na-fila-inteira',
              path: audio.path,
              sessionId: 'sessao-antiga',
              kind: 'ensaio',
              scope: KeptScope.whole,
              passNumber: 1,
            ),
          );
        },
      );

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(
        find.text(_pendingNotice),
        findsNothing,
        reason:
            'a gravação da passagem inteira aparecia num plano cena por cena, '
            'e a sala a recusaria',
      );
    },
  );

  testWidgets('a plan read that takes 6 seconds opens the grain choice', (
    tester,
  ) async {
    final (harness, container) = await _atRest(tester);
    harness.room.holdNextSceneList();

    await _tapTheDot(tester);
    await tester.pump(const Duration(milliseconds: 5800));

    expect(find.text(_thinking), findsOneWidget);
    expect(find.text(_how), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(_how), findsOneWidget);
    expect(find.text(_thinking), findsNothing);

    harness.room.finishHeldSceneList();
    await _theAnswerSettles(tester);

    expect(find.text(_how), findsOneWidget);
    expect(find.text(_planLine), findsNothing);
    expect(thePersonSign, findsNothing);
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });

  testWidgets(
    'a passage with a hand-recorded part opens the recording home, never the plan',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _reopenedOverPartOne(tester, origin: null);

      expect(find.bySemanticsLabel(_recordEnsaio), findsOneWidget);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
      semantics.dispose();
    },
  );

  group('a whole recording set aside', () {
    testWidgets(
      'is not fetched again on a second relaunch, and the parts stand',
      (tester) async {
        final it = await _reopenOverTheWholeSetAside(
          tester,
          takes: _partThreeGone,
        );
        final store = it.harness.emAberto;
        await it.relaunchIt();
        it.expectThreeRecordedRows();
        final kept = store.rows['Ruth/P01/pt']!;
        expect(kept.wholeHeldByTheRoom, ['gravacao-inteira']);
        expect([
          for (final take in kept.takes) take.scopeId,
        ], isNot(contains(KeptScope.whole)));
        final reads = it.takeReads;
        final clips = it.room.clipsFetched.length;

        await it.relaunchOnTheConversation();

        expect(it.takeReads, reads, reason: 'a sala foi lida de novo');
        await it.inRealTime(() async {
          it.sala.openTheEnsaioFinal();
          await it._theRowsStand();
        });
        expect(it.room.clipsFetched.length, clips);
        it.expectThreeRecordedRows();
      },
    );

    testWidgets(
      'kept by a resume point the earlier app wrote is not fetched on a relaunch',
      (tester) async {
        final it = await _reopenOverTheWholeSetAside(
          tester,
          takes: (guardadas) => [
            _heldPart(guardadas, 1),
            _heldPart(guardadas, 2),
            _heldPart(guardadas, 3),
            KeptTake(
              scopeId: KeptScope.whole,
              path: '${guardadas.path}/passagem-inteira-gravacao-inteira',
              takeId: 'gravacao-inteira',
            ),
          ],
          fromTheChoice: true,
        );

        expect(it.takeReads, 0, reason: 'a sala foi lida');
        expect(it.room.clipsFetched, isEmpty);
        expect(it.read.wholeHeldByTheRoom, ['gravacao-inteira']);
        it.expectThreeRecordedRows();
      },
    );

    testWidgets(
      'leaves a row waiting in the Outbox unsent after a relaunch, and '
      'recording it again lets that row go at the tap and sends the new take '
      'alone on its keep',
      (tester) async {
        final it = await _reopenOverTheWholeSetAside(
          tester,
          takes: _partThreeGone,
        );
        it.room.unreachableTake = 'ensaio/${KeptScope.parte(2)}';
        await it.recordAndKeep(2);

        await it.relaunchIt();

        expect(
          it.onRow(2, find.text('Cena 2 · 0:48 — enviar agora')),
          findsOneWidget,
        );
        expect(it.onRow(2, byLabel('Gravar')), findsNothing);

        it.room.unreachableTake = null;
        await it.inRealTime(() async {
          it.sala.gravarACena(2);
          await waitFor(
            'a cena 2 gravar',
            () => it.read.ensaio == EnsaioStatus.recording,
          );
          it.sala.gravarACena(2);
          await waitFor(
            'a gravação da cena 2 esperar o visto',
            () => it.read.ensaio == EnsaioStatus.recorded,
          );
          it.sala.takeKeep();
          await waitFor('a cena 2 subir', () => it.passesOfPart(2).contains(3));
          await settle(const Duration(milliseconds: 300));
        });

        final passes = it.passesOfPart(2);
        expect(passes, contains(3));
        expect(
          passes.toSet(),
          hasLength(passes.length),
          reason: 'duas gravações da cena 2 subiram na mesma passada: $passes',
        );
      },
    );
  });

  group('what was told over a whole recording set aside', () {
    SegmentView told(String segment, String take) => SegmentView(
      segmentId: segment,
      takeId: take,
      startsMs: 0,
      endsMs: 10000,
    );

    Future<Sala> openTheTellingBack(
      SalaHarness harness,
      ProviderContainer container,
    ) async {
      final it = Sala(harness, container);
      await it.sala.abrirEscolha();
      await settle();
      unawaited(it.sala.goConversa(book: 'Ruth', pericope: 'P01'));
      await waitFor(
        'a tradução reabrir tocando',
        () => harness.playback.played.isNotEmpty,
      );
      return it;
    }

    Future<void> drawTheTellingBack(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: RetroView()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('stays out of the telling-back after a second relaunch', (
      tester,
    ) async {
      final home = Directory.systemTemp.createTempSync('sala-1382-traducao');
      addTearDown(() => home.deleteSync(recursive: true));
      final harness = SalaHarness(takesHome: home)
        ..playback.measured = const Duration(seconds: 10);
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          for (final n in [1, 2])
            KeptTake(
              scopeId: KeptScope.parte(n),
              path: '${home.path}/gone-$n.m4a',
              takeId: 'gravacao-parte-$n',
            ),
        ],
      );
      harness.room
        ..passageScenes = _threeScenes.sublist(0, 2)
        ..retroSoFar = BackTranslationProgress(
          segments: [
            told('trecho-inteiro', 'gravacao-inteira'),
            told('trecho-1', 'gravacao-parte-1'),
            told('trecho-2', 'gravacao-parte-2'),
          ],
        )
        ..takes.addAll([_theWhole, _part(1), _part(2)]);
      final launched = (await tester.runAsync(() async {
        final launched = harness.container();
        await openTheTellingBack(harness, launched);
        return launched;
      }))!;
      addTearDown(launched.dispose);

      final clips = harness.room.clipsFetched.length;
      final next = (await tester.runAsync(() async {
        final (again, next) = await relaunch(harness, launched);
        again.playback.measured = const Duration(seconds: 10);
        await openTheTellingBack(again, next);
        return next;
      }))!;
      await drawTheTellingBack(tester, next);

      expect(next.read(salaSessionProvider).stage, SalaStage.retro);
      await tester.ensureVisible(find.text('recomeçar a tradução'));
      await tester.pump();
      await tester.tap(find.text('recomeçar a tradução'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('toque de novo para apagar as 2 frases traduzidas'),
        findsOneWidget,
        reason: 'o que foi contado sobre o inteiro voltou à tradução',
      );
      await tester.pump(const Duration(seconds: 10));
      expect(
        harness.room.clipsFetched,
        hasLength(clips),
        reason: 'as partes foram buscadas de novo',
      );
    });
  });

  testWidgets(
    '«Gravar cena por cena» on the plan opens the recording home in one tap, '
    'and the plan is never where a relaunch lands',
    (tester) async {
      final (harness, container) = await _atRest(tester);
      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      expect(find.text(_planLine), findsOneWidget);

      final again = await _relaunchOnTheApp(tester, harness, container);

      expect(again.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(find.text(_planLine), findsNothing);
      expect(_dot, findsOneWidget);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);
      await tester.tap(find.text(_sceneByScene));
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);

      await _relaunchOnTheApp(tester, harness, again);

      expect(find.text(_homeLine), findsOneWidget);
    },
  );

  testWidgets(
    'a passage the room answers with no scenes opens the grain choice',
    (tester) async {
      await _atRest(tester, scenes: const []);

      await _tapTheDot(tester);
      await _theAnswerSettles(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
      expect(find.text(_thinking), findsNothing);
    },
  );

  testWidgets('a takes read that fails opens the grain choice with no sign', (
    tester,
  ) async {
    final (harness, container) = await _atRest(tester);
    harness.room.failTakesWith = const NetworkFailed('sem rede');

    await _tapTheDot(tester);
    await _theAnswerSettles(tester);

    expect(find.text(_how), findsOneWidget);
    expect(find.text(_planLine), findsNothing);
    expect(thePersonSign, findsNothing);
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });

  testWidgets('an English room names the dot and the plan in her English', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, _) = await _atRest(
      tester,
      lingua: 'en',
      scenes: _threeScenesEn,
    );
    expect(find.bySemanticsLabel(_recordEnsaioEn), findsOneWidget);
    harness.room.holdNextSceneList();

    await _tapTheDot(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('thinking…'), findsOneWidget);

    harness.room.finishHeldSceneList();
    await _theAnswerSettles(tester);

    expect(find.text('Final Rehearsal'), findsOneWidget);
    expect(
      find.text('These are the scene rehearsals you sent me.'),
      findsOneWidget,
    );
    expect(find.text('Record scene by scene instead'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an English room names the dot after a join in her English', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _reopenedOverPartOne(
      tester,
      origin: 'cena-1',
      lingua: 'en',
      scenes: _threeScenesEn,
    );

    expect(find.bySemanticsLabel(_openEnsaioFinalEn), findsOneWidget);
    semantics.dispose();
  });
}
