import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, relaunch;

const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _planLineEn = 'These are the scene rehearsals you sent me.';
const _homeLineEn =
    'Record, listen back, and record again as many times as you need.';
const _join = 'juntar as cenas e ouvir';
const _joinEn = 'join the scenes and listen';
const _cannotEnter = 'este ensaio não pode entrar — ensaiem esta cena de novo';
const _retry = 'não deu para juntar esta cena — toquem para tentar de novo';
const _retryEn = 'this scene could not be joined — tap to try again';
const _tick = '✓';
const _enviarAGravacao = 'Enviar a gravação';

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
        'Gravar o ensaio de vocês',
        'Abrir o Ensaio Final',
        'Record your rehearsal',
        'Open the Final Rehearsal',
      }.contains(widget.properties.label),
);

Uint8List _bytesOf(int n) =>
    aWavTake(samples: [for (var i = 0; i < 40; i++) n * 100 + i]);

String _fingerprintOf(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

String _idOf(String sessionId, int n) => '$sessionId-ensaio-$n';

SceneRehearsalRecord _rehearsal(String sessionId, int n) =>
    SceneRehearsalRecord(
      rehearsalId: _idOf(sessionId, n),
      sessionId: sessionId,
      n: n,
      scene: 'S$n',
      recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
      sentAt: '2026-10-22T10:0$n:00+00:00',
      durationMs: 6000,
      frases: const [
        SceneFrase(fraseId: 'frase-a', startsMs: 0, endsMs: 3000),
        SceneFrase(fraseId: 'frase-b', startsMs: 3000, endsMs: 6000),
      ],
      verified: true,
      sha256: _fingerprintOf(_bytesOf(n)),
    );

/// A tablet at rest on the Conversation over three scenes, on a real Outbox and a real
/// disk, with one sent rehearsal of each scene in the room.
class _Room {
  final WidgetTester tester;
  SalaHarness harness;
  ProviderContainer container;

  _Room(this.tester, this.harness, this.container);

  FakeRoom get room => harness.room;

  String get sessionId => container.read(salaSessionProvider).sessionId!;

  String idOf(int n) => _idOf(sessionId, n);

  List<String> get partsReceived => [
    for (final take in room.takesReceivedWhole)
      if (take.kind == 'ensaio') take.scope,
  ];

  /// Lets the disk answer what the tablet asked of it, then [ahead] of the room's clock.
  Future<void> beat([Duration ahead = Duration.zero]) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(ahead);
  }

  Future<void> until(String what, bool Function() done) async {
    final waited = Stopwatch()..start();
    for (
      var vez = 0;
      !done() && (vez < 200 || waited.elapsed < const Duration(seconds: 30));
      vez++
    ) {
      await beat(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: what);
  }

  Future<void> wait(Duration span) async {
    for (var passed = Duration.zero; passed < span;) {
      final step = span - passed < const Duration(milliseconds: 100)
          ? span - passed
          : const Duration(milliseconds: 100);
      await beat(step);
      passed += step;
    }
  }

  Future<void> settle() async {
    for (var vez = 0; vez < 15; vez++) {
      await beat(const Duration(milliseconds: 100));
    }
  }

  Future<void> heldOnTheTablet(int n, [List<int>? bytes]) => tester.runAsync(
    () => harness.recorder.keepBytes(
      Uint8List.fromList(bytes ?? _bytesOf(n)),
      'cena-${idOf(n)}',
    ),
  );

  /// A take the team recorded by hand for scene [n], kept in the Outbox and never let
  /// through to the room.
  Future<void> aHandTakeHeld(int n) async {
    room.unreachableTake = 'ensaio/${KeptScope.parte(n)}';
    final audio = File('${harness.takesHome.path}/a-mao-$n.m4a')
      ..writeAsBytesSync([1, 2, 3, 4]);
    await tester.runAsync(
      () => harness.takes.enqueue(
        audio,
        sessionId: sessionId,
        kind: 'ensaio',
        scope: KeptScope.parte(n),
        passNumber: 1,
        chunkIndex: n,
      ),
    );
    unawaited(container.read(salaSessionProvider.notifier).refreshUnsent());
    await settle();
  }

  Future<void> aHandTakeGivenUp(int n) async {
    await aHandTakeHeld(n);
    await tester.runAsync(() async {
      while (!(await harness.takes.entries()).any(
        (row) => row.scope == KeptScope.parte(n) && row.exhausted,
      )) {
        await harness.takes.flush();
      }
    });
    unawaited(container.read(salaSessionProvider.notifier).refreshUnsent());
    await settle();
  }

  Finder get sendNow => find.ancestor(
    of: find.textContaining('enviar agora'),
    matching: find.byType(TextButton),
  );

  Finder sendNowOf(int n) => find.ancestor(
    of: find.textContaining('Cena $n · '),
    matching: find.byType(TextButton),
  );

  /// Every part a join wrote, landed in the room or still in the Outbox.
  Future<Set<String>> scopesJoined() async => {
    for (final take in room.takesReceivedWhole)
      if (take.origin != null) take.scope,
    for (final row in (await tester.runAsync(harness.takes.entries))!)
      if (row.origin != null) row.scope,
  };

  void seed([Iterable<int> scenes = const [1, 2, 3]]) {
    for (final n in scenes) {
      room.sceneRehearsals.add(_rehearsal(sessionId, n));
      room.sceneAudioOf[idOf(n)] = _bytesOf(n);
    }
  }

  Future<void> openThePlan() async {
    await tester.tap(_dot);
    await until(
      'o plano ou a casa abrir',
      () => [
        _planLine,
        _homeLine,
        _planLineEn,
        _homeLineEn,
      ].any((line) => find.text(line).evaluate().isNotEmpty),
    );
    await settle();
  }

  Future<void> tapJoin([String label = _join]) async {
    await tester.ensureVisible(byLabel(label));
    await tester.pump();
    await tester.tap(byLabel(label));
    await beat();
  }

  Finder row(int n, [List<Scene> scenes = _threeScenes]) => byLabel(
    '${identical(scenes, _threeScenesEn) ? 'Scene' : 'Cena'} $n — '
    '${scenes[n - 1].title}',
  );

  Finder onRow(int n, Finder target, [List<Scene> scenes = _threeScenes]) =>
      find.descendant(of: row(n, scenes), matching: target);

  /// The held scope's own request reached the room, not only asked to be held.
  bool get theHeldTakeArrived => _arrived;
  bool _arrived = false;

  void holdTheTake(String scope) {
    _arrived = false;
    room.holdNextTake(scope);
    unawaited(room.untilTakeHeld().then((_) => _arrived = true));
  }

  bool ticked(int n) => onRow(n, find.text(_tick)).evaluate().isNotEmpty;

  bool showsTheHome() => find.text(_homeLine).evaluate().isNotEmpty;

  /// The team walked back to the Conversation before the tablet was closed.
  void leftOnTheConversation() {
    final rows = harness.emAberto.rows;
    final key = rows.keys.single;
    final at = rows[key]!;
    rows[key] = ResumePoint(
      sessionId: at.sessionId,
      stage: SalaStage.conversa,
      takes: at.takes,
      savedAt: at.savedAt,
      language: at.language,
      passesToGoAbove: at.passesToGoAbove,
      wholeHeldByTheRoom: at.wholeHeldByTheRoom,
    );
  }

  Future<void> toTheRecordingHome() async {
    container.read(salaSessionProvider.notifier).goEnsaio();
    await until(
      'as cenas chegarem',
      () => container.read(salaSessionProvider).sceneRows.length == 3,
    );
    await settle();
  }

  Future<void> relaunchOnTheConversation() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    var stopped = false;
    unawaited(harness.takes.writingEnds().then((_) => stopped = true));
    await until('a vida antiga parar de escrever', () => stopped);
    late SalaHarness again;
    late ProviderContainer next;
    await tester.runAsync(() async {
      (again, next) = await relaunch(harness, container);
      next.read(salaSessionProvider);
    });
    harness = again;
    container = next;
    await tester.pumpWidget(
      UncontrolledProviderScope(container: next, child: const SalaApp()),
    );
    await _toTheConversation(this);
  }
}

Future<void> _toTheConversation(_Room it) async {
  final notifier = it.container.read(salaSessionProvider.notifier);
  await it.settle();
  unawaited(notifier.abrirEscolha());
  await it.settle();
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await it.until(
    'a conversa abrir',
    () =>
        it.container.read(salaSessionProvider).voice == VoiceState.invite &&
        !it.container.read(salaSessionProvider).awaitingTheGuide,
  );
  await it.wait(const Duration(milliseconds: 1500));
}

Future<_Room> _atRest(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final home = aTempHome('sala-1385-junta');
  final harness = SalaHarness(lingua: lingua, takesHome: home)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes;
  final container = (await tester.runAsync(
    () async => harness.container()..read(salaSessionProvider),
  ))!;
  final it = _Room(tester, harness, container);
  addTearDown(() => it.container.dispose());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await _toTheConversation(it);
  return it;
}

/// The join's end, at a state that lasts: the Back-translation it opens when every scene
/// has its part, the recording home when one has none.
Future<void> _theJoinEnds(_Room it) => it.until('a junta terminar', () {
  final estado = it.container.read(salaSessionProvider);
  return estado.joining == null &&
      (estado.stage == SalaStage.retro ||
          it.showsTheHome() && !estado.everySceneHasItsPart);
});

void main() {
  testWidgets(
    'three joinable scenes join one at a time into three parts that are their '
    'rehearsals\' bytes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      expect(find.text(_planLine), findsOneWidget);

      for (final n in [1, 2, 3]) {
        it.room.holdNextTake('parte-$n');
        if (n == 1) await it.tapJoin();
        await it.until(
          'a parte $n chegar à porta',
          () =>
              find.text('juntando a cena $n de 3…').evaluate().isNotEmpty &&
              it.room.holdTakeScope == 'parte-$n',
        );
        expect(it.ticked(n), isFalse, reason: 'a linha $n antes de chegar');
        it.room.finishHeldTake();
        if (n < 3) {
          await it.until('a linha $n ganhar o visto', () => it.ticked(n));
        }
      }
      await _theJoinEnds(it);
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until('a casa voltar', () => it.showsTheHome());

      expect(
        [
          for (final take in it.room.takesReceivedWhole)
            (take.scope, take.chunkIndex),
        ],
        [('parte-1', 1), ('parte-2', 2), ('parte-3', 3)],
      );
      for (final (i, take) in it.room.takesReceivedWhole.indexed) {
        final n = i + 1;
        expect(take.origin, it.idOf(n), reason: 'a origem da parte $n');
        expect(take.bytes, _bytesOf(n), reason: 'os bytes da parte $n');
        expect(take.sha256, _fingerprintOf(_bytesOf(n)));
      }
      expect(find.text('Ensaio Final'), findsWidgets);
      for (final n in [1, 2, 3]) {
        expect(it.onRow(n, byLabel('Ouvir')), findsOneWidget);
      }
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a scene whose file is not on this tablet is downloaded first, then sent '
    'as the same bytes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.heldOnTheTablet(3);
      await it.openThePlan();
      final before = it.room.clipsFetched.length;

      await it.tapJoin();
      await _theJoinEnds(it);

      expect(
        it.room.clipsFetched
            .skip(before)
            .where((url) => url.contains('/scene-rehearsals/')),
        [endsWith('/scene-rehearsals/${it.idOf(2)}/audio')],
      );
      expect(it.room.takesReceivedWhole[1].bytes, _bytesOf(2));
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a file on this tablet that is not the rehearsal\'s bytes is never sent',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1, _bytesOf(9));
      await it.heldOnTheTablet(2);
      await it.heldOnTheTablet(3);
      await it.openThePlan();
      final before = it.room.clipsFetched.length;

      await it.tapJoin();
      await _theJoinEnds(it);

      expect(
        it.room.clipsFetched.skip(before),
        contains(endsWith('/scene-rehearsals/${it.idOf(1)}/audio')),
      );
      expect(it.room.takesReceivedWhole.first.scope, 'parte-1');
      expect(it.room.takesReceivedWhole.first.bytes, _bytesOf(1));
      expect(
        it.room.takesReceivedWhole.map((take) => take.bytes),
        isNot(contains(_bytesOf(9))),
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a rehearsal whose recording is gone says so and the others join',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.heldOnTheTablet(3);
      it.room.rehearsalsGone.add(it.idOf(2));
      it.room.sceneAudioOf.remove(it.idOf(2));
      await it.openThePlan();
      it.room.holdNextTake('parte-3');

      await it.tapJoin();
      await it.until(
        'a parte 3 chegar à porta',
        () => it.room.holdTakeScope == 'parte-3',
      );
      await it.until(
        'a linha 2 dizer que não pode entrar',
        () => it.onRow(2, find.text(_cannotEnter)).evaluate().isNotEmpty,
      );
      expect(it.ticked(1), isTrue);
      it.room.finishHeldTake();
      await _theJoinEnds(it);

      expect(it.partsReceived, ['parte-1', 'parte-3']);
      expect(it.onRow(1, byLabel('Ouvir')), findsOneWidget);
      expect(it.onRow(2, byLabel('Ouvir')), findsNothing);
      expect(it.onRow(3, byLabel('Ouvir')), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a join the room refuses as no rehearsal of the passage says so and goes on',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      it.room.refuseTake = 'ensaio/parte-2';
      it.room.refuseTakeCode = 'UNKNOWN_REFERENCE';
      it.room.holdNextTake('parte-3');

      await it.tapJoin();
      await it.until(
        'a parte 3 chegar à porta',
        () => it.room.holdTakeScope == 'parte-3',
      );
      await it.until(
        'a linha 2 dizer que não pode entrar',
        () => it.onRow(2, find.text(_cannotEnter)).evaluate().isNotEmpty,
      );
      it.room.finishHeldTake();
      await _theJoinEnds(it);

      expect(it.partsReceived, ['parte-1', 'parte-3']);
      semantics.dispose();
    },
  );

  testWidgets(
    'a "wait" from the room for 60 s is retried quietly and the scene joins '
    'with no message',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      it.room.unreachableTake = 'ensaio/parte-2';
      it.room.holdNextTake('parte-3');

      await it.tapJoin();
      await it.until('a linha 1 ganhar o visto', () => it.ticked(1));
      for (var second = 0; second < 60; second++) {
        await it.wait(const Duration(seconds: 1));
        expect(find.text(_retry), findsNothing, reason: 'aos ${second + 1} s');
      }
      it.room.unreachableTake = null;
      for (var second = 0; second < 10 && !it.ticked(2); second++) {
        await it.wait(const Duration(seconds: 1));
        expect(find.text(_retry), findsNothing);
      }
      final waited = Stopwatch()..start();
      while (!it.ticked(2) && waited.elapsed < const Duration(seconds: 30)) {
        await it.beat();
      }

      expect(it.ticked(2), isTrue);
      it.room.finishHeldTake();
      await _theJoinEnds(it);
      expect(it.partsReceived, ['parte-1', 'parte-2', 'parte-3']);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a scene with no answer for 70 s says to try again, and a tap tries only '
    'that scene and then the rest',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      it.holdTheTake('parte-2');

      await it.tapJoin();
      await it.until(
        'a parte 2 chegar à porta',
        () => it.theHeldTakeArrived && it.ticked(1),
      );
      await it.wait(const Duration(seconds: 69));
      expect(find.text(_retry), findsNothing, reason: 'aos 69 s');
      await it.wait(const Duration(seconds: 1));
      await it.settle();

      expect(it.onRow(2, find.text(_retry)), findsOneWidget);
      expect(it.ticked(1), isTrue);
      expect(it.partsReceived, isNot(contains('parte-3')));

      it.room.finishHeldTake();
      await it.settle();
      await tester.tap(it.onRow(2, find.text(_retry)));
      await _theJoinEnds(it);

      expect(
        it.partsReceived.where((scope) => scope == 'parte-1'),
        hasLength(1),
      );
      expect(it.partsReceived, contains('parte-3'));
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a drop after two scenes reopens the plan with two ticks, and «juntar» '
    'joins the third alone',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.heldOnTheTablet(2);
      await it.openThePlan();
      it.room.holdNextClip();

      await it.tapJoin();
      await it.until('a linha 2 ganhar o visto', () => it.ticked(2));
      await it.relaunchOnTheConversation();
      it.room.finishHeldClip();

      expect(
        find.text(_planLine),
        findsNothing,
        reason: 'a volta é à conversa',
      );
      await it.openThePlan();
      expect(find.text(_planLine), findsOneWidget);
      expect(it.ticked(1), isTrue);
      expect(it.ticked(2), isTrue);
      expect(it.ticked(3), isFalse);
      final before = it.partsReceived.length;

      await it.tapJoin();
      await _theJoinEnds(it);

      expect(it.partsReceived.skip(before), ['parte-3']);
      expect(it.partsReceived.where((s) => s == 'parte-1'), hasLength(1));
      expect(it.partsReceived.where((s) => s == 'parte-2'), hasLength(1));
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a join row that failed on the network sends nothing after the app is '
    "reopened, and only its scene row's enviar agora sends it, with its origin "
    'and fingerprint',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      it.room.unreachableTake = 'ensaio/parte-2';

      await it.tapJoin();
      await it.until('a linha 1 ganhar o visto', () => it.ticked(1));
      await it.wait(const Duration(seconds: 95));
      await it.until(
        'a linha 2 pedir outra tentativa',
        () => it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
      );
      it.room.unreachableTake = null;
      final asked = it.room.takesAsked.length;
      await it.relaunchOnTheConversation();
      await it.wait(const Duration(minutes: 2));

      expect(it.room.takesAsked.skip(asked), isEmpty);

      await it.toTheRecordingHome();
      final send = it.onRow(2, find.textContaining('enviar agora'));
      expect(send, findsOneWidget);
      await tester.tap(send);
      await it.until(
        'a parte 2 chegar pelo toque',
        () => it.partsReceived.contains('parte-2'),
      );

      expect(
        it.room.takesReceivedWhole.where((take) => take.scope == 'parte-2'),
        isNotEmpty,
      );
      for (final part2 in it.room.takesReceivedWhole.where(
        (take) => take.scope == 'parte-2',
      )) {
        expect(part2.origin, it.idOf(2));
        expect(part2.sha256, _fingerprintOf(_bytesOf(2)));
        expect(part2.bytes, _bytesOf(2));
      }
      expect(
        it.room.takes.where((take) => take.ordinal == 2),
        hasLength(1),
        reason: 'a mesma junta enviada duas vezes é uma take só',
      );
      semantics.dispose();
    },
  );

  group('«juntar» twice writes nothing new', () {
    testWidgets('after a whole join the dot opens the recording home', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      await it.tapJoin();
      await _theJoinEnds(it);
      await it.settle();
      final sent = it.partsReceived.length;
      it.leftOnTheConversation();
      await it.relaunchOnTheConversation();

      await it.openThePlan();

      expect(it.showsTheHome(), isTrue);
      expect(find.text(_planLine), findsNothing);
      expect(it.partsReceived, hasLength(sent));
      semantics.dispose();
    });

    testWidgets(
      'a part the room already holds joined is ticked and not sent again',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await _atRest(tester);
        it.seed();
        it.room.takes.add(
          TakeView(
            takeId: 'gravacao-junta-2',
            kind: 'ensaio',
            scope: KeptScope.parte(2),
            ordinal: 2,
            pass: 1,
            origin: it.idOf(2),
          ),
        );
        it.room.takeAudio['gravacao-junta-2'] = _bytesOf(2);

        await it.openThePlan();
        expect(find.text(_planLine), findsOneWidget);
        expect(it.ticked(2), isTrue);
        await it.tapJoin();
        await _theJoinEnds(it);
        await it.settle();

        expect(it.partsReceived, ['parte-1', 'parte-3']);
        expect(
          it.room.clipsFetched,
          contains(endsWith('/takes/gravacao-junta-2/audio')),
        );
        semantics.dispose();
      },
    );
  });

  testWidgets('two tablets joining the same rehearsal leave one part', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    it.seed();
    await it.openThePlan();
    it.room.takes.add(
      TakeView(
        takeId: 'gravacao-outro-tablet',
        kind: 'ensaio',
        scope: KeptScope.parte(2),
        ordinal: 2,
        pass: 1,
        origin: it.idOf(2),
      ),
    );
    it.room.takeAudio['gravacao-outro-tablet'] = _bytesOf(2);

    await it.tapJoin();
    await _theJoinEnds(it);

    expect(
      it.room.takes.where((take) => take.ordinal == 2).map((t) => t.takeId),
      ['gravacao-outro-tablet'],
    );
    closeTheRoom(it.container);
    semantics.dispose();
  });

  testWidgets(
    'a join the room answers with a take that is not the part claims nothing '
    'and opens the recording home, in a room that answers any take holding '
    'those bytes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.room.joinsTheLiveTake = false;
      it.seed();
      await it.openThePlan();
      it.room.takes.addAll([
        TakeView(
          takeId: 'gravacao-junta-antiga',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 1,
          origin: it.idOf(2),
        ),
        TakeView(
          takeId: 'gravacao-a-mao',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 2,
        ),
      ]);
      it.room.takeAudio['gravacao-junta-antiga'] = _bytesOf(2);
      it.room.takeAudio['gravacao-a-mao'] = _bytesOf(7);
      it.room.holdNextTake('parte-2');

      await it.tapJoin();
      await it.until(
        'a parte 2 chegar à porta',
        () => it.room.holdTakeScope == 'parte-2',
      );
      it.room.finishHeldTake();
      var ticked = false;
      for (var vez = 0; vez < 200 && !it.showsTheHome(); vez++) {
        ticked = ticked || it.ticked(2);
        await it.beat(const Duration(milliseconds: 20));
      }
      await _theJoinEnds(it);

      expect(ticked, isFalse);
      expect(it.partsReceived, ['parte-1', 'parte-2']);
      expect(
        it.room.takes.where((take) => take.ordinal == 2).map((t) => t.takeId),
        ['gravacao-junta-antiga', 'gravacao-a-mao'],
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a join row names the take the room lists as its part when the row is '
    'written, and none over an empty scene',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.takes.add(
        TakeView(
          takeId: 'gravacao-de-outro-tablet',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 1,
          origin: 'ensaio-de-outro-tablet',
        ),
      );
      it.room.takeAudio['gravacao-de-outro-tablet'] = _bytesOf(8);

      await it.tapJoin();
      await _theJoinEnds(it);

      expect(
        {
          for (final take in it.room.takesReceivedWhole)
            take.scope: take.overTake,
        },
        {
          'parte-1': null,
          'parte-2': 'gravacao-de-outro-tablet',
          'parte-3': null,
        },
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a join the room turns away because another take landed on the part '
    'claims nothing, opens the recording home and is never sent again',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.unreachableTake = 'ensaio/parte-2';
      int triesOf2() => it.room.calls.where((c) => c == 'sendTake').length;

      await it.tapJoin();
      await it.until('a linha 1 ganhar o visto', () => it.ticked(1));
      await it.wait(const Duration(seconds: 6));
      it.room.takes.add(
        TakeView(
          takeId: 'gravacao-a-mao',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 2,
        ),
      );
      it.room.takeAudio['gravacao-a-mao'] = _bytesOf(7);
      it.room.unreachableTake = null;
      var ticked = false;
      for (var vez = 0; vez < 200 && !it.showsTheHome(); vez++) {
        ticked = ticked || it.ticked(2);
        await it.beat(const Duration(milliseconds: 20));
      }
      await _theJoinEnds(it);
      final tries = triesOf2();
      await it.wait(const Duration(seconds: 30));

      expect(ticked, isFalse);
      expect(find.text(_retry), findsNothing);
      expect(
        it.room.takes.where((take) => take.ordinal == 2).map((t) => t.takeId),
        ['gravacao-a-mao'],
      );
      expect(it.partsReceived, isNot(contains('parte-3')));
      expect(triesOf2(), tries, reason: 'nada é tentado de novo');
      semantics.dispose();
    },
  );

  testWidgets(
    'a scene whose part the room cannot list as the row would be written '
    'writes no row and says to try again, and the tap names the part the '
    'room then lists',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.takes.add(
        TakeView(
          takeId: 'gravacao-a-mao',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 1,
        ),
      );
      it.room.takeAudio['gravacao-a-mao'] = _bytesOf(7);
      it.room.failTakesWith = const NetworkFailed('sem rede');

      await it.tapJoin();
      await it.until(
        'a linha 1 pedir outra tentativa',
        () => it.onRow(1, find.text(_retry)).evaluate().isNotEmpty,
      );
      expect(it.partsReceived, isEmpty);
      expect(it.showsTheHome(), isFalse);

      it.room.failTakesWith = null;
      await tester.tap(it.onRow(1, find.text(_retry)));
      await _theJoinEnds(it);

      expect(
        {
          for (final take in it.room.takesReceivedWhole)
            take.scope: take.overTake,
        },
        {'parte-1': null, 'parte-2': 'gravacao-a-mao', 'parte-3': null},
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  group('a join row the Outbox still held', () {
    Future<_Room> givenUpOnPart2(WidgetTester tester) async {
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      it.holdTheTake('parte-2');
      await it.tapJoin();
      await it.until(
        'a parte 2 chegar à porta',
        () => it.theHeldTakeArrived && it.ticked(1),
      );
      await it.wait(joinAnswerWait);
      await it.until(
        'a linha 2 pedir outra tentativa',
        () => it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
      );
      return it;
    }

    testWidgets(
      'and the room then refused for good is joined again from the start '
      'at the next tap',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await givenUpOnPart2(tester);
        it.room.refuseTake = 'ensaio/parte-2';
        it.room.refuseTakeCode = 'HTTP_500';
        it.room.finishHeldTake();
        await it.settle();
        await tester.tap(it.onRow(2, find.text(_retry)));
        await it.until(
          'a linha 2 pedir outra tentativa de novo',
          () =>
              it.container.read(salaSessionProvider).joining == null &&
              it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
        );
        it.room.refuseTake = null;

        await tester.tap(it.onRow(2, find.text(_retry)));
        await _theJoinEnds(it);

        expect(it.partsReceived, ['parte-1', 'parte-2', 'parte-3']);
        closeTheRoom(it.container);
        semantics.dispose();
      },
    );

    testWidgets(
      'that lands on its own as a take that is not the part claims nothing, in '
      'a room that answers any take holding those bytes',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await givenUpOnPart2(tester);
        it.room.joinsTheLiveTake = false;
        it.room.takes.addAll([
          TakeView(
            takeId: 'gravacao-junta-antiga',
            kind: 'ensaio',
            scope: KeptScope.parte(2),
            ordinal: 2,
            pass: 1,
            origin: it.idOf(2),
          ),
          TakeView(
            takeId: 'gravacao-a-mao',
            kind: 'ensaio',
            scope: KeptScope.parte(2),
            ordinal: 2,
            pass: 2,
          ),
        ]);
        it.room.takeAudio['gravacao-junta-antiga'] = _bytesOf(2);
        it.room.takeAudio['gravacao-a-mao'] = _bytesOf(7);
        it.room.finishHeldTake();
        await it.settle();
        expect(it.ticked(2), isFalse);

        await tester.tap(it.onRow(2, find.text(_retry)));
        var ticked = false;
        for (var vez = 0; vez < 100 && !it.showsTheHome(); vez++) {
          ticked = ticked || it.ticked(2);
          await it.beat(const Duration(milliseconds: 20));
        }

        expect(it.showsTheHome(), isTrue);
        expect(ticked, isFalse);
        expect(it.partsReceived, isNot(contains('parte-3')));
        semantics.dispose();
      },
    );

    testWidgets(
      'gives way to the scene recorded again by hand, and only the hand take '
      'goes up',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await _atRest(tester);
        it.seed();
        await it.openThePlan();
        it.room.unreachableTake = 'ensaio/parte-2';
        await it.tapJoin();
        await it.wait(const Duration(seconds: 100));
        await it.until(
          'a linha 2 pedir outra tentativa',
          () => it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
        );
        final sala = it.container.read(salaSessionProvider.notifier);
        sala.recordSceneByScene();
        await it.settle();

        SalaSessionState read() => it.container.read(salaSessionProvider);
        await it.until('as cenas chegarem', () => read().sceneRows.length == 3);
        sala.gravarACena(2);
        await it.until(
          'a cena 2 gravar',
          () => read().ensaio == EnsaioStatus.recording,
        );
        sala.gravarACena(2);
        await it.until(
          'a gravação esperar o visto',
          () => read().ensaio == EnsaioStatus.recorded,
        );
        sala.takeKeep();
        await it.settle();
        it.room.unreachableTake = null;
        sala.enviarACena(2);
        await it.until(
          'a parte 2 subir',
          () => it.partsReceived.contains('parte-2'),
        );
        await it.settle();

        final part2 = [
          for (final take in it.room.takesReceivedWhole)
            if (take.scope == 'parte-2') take,
        ];
        expect(part2, hasLength(1));
        expect(part2.single.origin, isNull);
        final left = await tester.runAsync(it.harness.takes.pending);
        expect(left!.where((row) => row.origin != null), isEmpty);
        semantics.dispose();
      },
    );
  });

  testWidgets(
    'a join row that landed is ticked even while a slow upload after it is '
    'still sending',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.openThePlan();
      it.holdTheTake('parte-1');

      await it.tapJoin();
      await it.until('a parte 1 chegar à porta', () => it.theHeldTakeArrived);
      final slow = File('${it.harness.takesHome.path}/lenta.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      var queued = false;
      unawaited(
        it.harness.takes
            .enqueue(
              slow,
              sessionId: it.sessionId,
              kind: 'ensaio',
              scope: 'parte-9',
              chunkIndex: 9,
            )
            .then((_) => queued = true),
      );
      await it.until('a gravação lenta entrar na fila', () => queued);
      unawaited(it.harness.takes.flush());
      it.room.finishHeldTake();
      it.holdTheTake('parte-9');
      await it.until(
        'a gravação lenta chegar à porta',
        () => it.theHeldTakeArrived,
      );
      await it.wait(const Duration(seconds: 75));

      expect(it.onRow(1, find.text(_retry)), findsNothing);
      expect(it.ticked(1), isTrue);
      it.room.finishHeldTake();
      await _theJoinEnds(it);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a join left behind by a reopened plan changes nothing of the new join',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.holdNextClip();
      await it.tapJoin();
      await it.until(
        'a primeira junta buscar a cena 1',
        () => it.room.clipsFetched.any(
          (url) => url.endsWith('/scene-rehearsals/${it.idOf(1)}/audio'),
        ),
      );
      final sessionId = it.sessionId;

      it.container.read(salaSessionProvider.notifier).leaveThePassage();
      await it.settle();
      await _toTheConversation(it);
      expect(it.sessionId, sessionId);
      await it.openThePlan();
      await it.tapJoin();
      await it.settle();
      it.holdTheTake('parte-1');
      it.room.finishHeldClip();
      await it.until('a parte 1 chegar à porta', () => it.theHeldTakeArrived);
      await it.settle();

      expect(find.text('juntando a cena 1 de 3…'), findsOneWidget);
      it.room.finishHeldTake();
      await _theJoinEnds(it);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a join left behind by a new link of the tablet changes nothing of the '
    'new join',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.holdNextClip();
      await it.tapJoin();
      await it.until(
        'a primeira junta buscar a cena 1',
        () => it.room.clipsFetched.any(
          (url) => url.endsWith('/scene-rehearsals/${it.idOf(1)}/audio'),
        ),
      );

      it.container.invalidate(salaSessionProvider);
      await it.settle();
      await _toTheConversation(it);
      await it.openThePlan();
      await it.tapJoin();
      await it.settle();
      it.holdTheTake('parte-1');
      it.room.finishHeldClip();
      await it.until('a parte 1 chegar à porta', () => it.theHeldTakeArrived);
      await it.settle();

      expect(find.text('juntando a cena 1 de 3…'), findsOneWidget);
      it.room.finishHeldTake();
      await _theJoinEnds(it);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'an unsent rehearsal the team chose joins as its scene\'s part, with its '
    'own bytes',
    (tester) async {
      final it = await _atRest(tester);
      it.seed([1, 3]);
      final unsent = SceneRehearsalRecord(
        rehearsalId: _idOf(it.sessionId, 2),
        sessionId: it.sessionId,
        n: 2,
        scene: 'S2',
        recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
        durationMs: 6000,
        frases: const [
          SceneFrase(fraseId: 'frase-a', startsMs: 0, endsMs: 6000),
        ],
        verified: true,
        sha256: _fingerprintOf(_bytesOf(2)),
      );
      it.room.sceneRehearsals.add(unsent);
      it.room.sceneAudioOf[unsent.rehearsalId] = _bytesOf(2);
      await it.openThePlan();
      final notifier = it.container.read(salaSessionProvider.notifier);
      notifier.swapTheRehearsal('S2');
      await it.settle();
      notifier.useThisRehearsal(unsent.rehearsalId);
      await it.settle();

      await it.tapJoin();
      await _theJoinEnds(it);

      final part2 = [
        for (final take in it.room.takesReceivedWhole)
          if (take.chunkIndex == 2) take,
      ];
      expect(
        [for (final take in part2) take.origin],
        [it.idOf(2)],
        reason: 'a junta pulava o ensaio não enviado que a equipe escolheu',
      );
      expect(part2.single.bytes, _bytesOf(2));
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'a scene whose waiting join the room then refused for good offers its '
    'other rehearsal again',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      final other = SceneRehearsalRecord(
        rehearsalId: _idOf(it.sessionId, 4),
        sessionId: it.sessionId,
        n: 4,
        scene: 'S2',
        recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
        sentAt: '2026-10-22T09:00:00+00:00',
        durationMs: 6000,
        frases: const [
          SceneFrase(fraseId: 'frase-a', startsMs: 0, endsMs: 6000),
        ],
        verified: true,
        sha256: _fingerprintOf(_bytesOf(4)),
      );
      it.room.sceneRehearsals.add(other);
      it.room.sceneAudioOf[other.rehearsalId] = _bytesOf(4);
      await it.openThePlan();
      it.holdTheTake('parte-2');
      await it.tapJoin();
      await it.until(
        'a parte 2 chegar à porta',
        () => it.theHeldTakeArrived && it.ticked(1),
      );
      await it.wait(joinAnswerWait);
      await it.until(
        'a linha 2 pedir outra tentativa',
        () => it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
      );
      expect(
        it.onRow(2, find.text('trocar o ensaio desta cena')),
        findsNothing,
        reason: 'a junta da cena 2 ainda espera no Outbox',
      );
      it.room.refuseTake = 'ensaio/parte-2';
      it.room.refuseTakeCode = 'HTTP_500';
      it.room.finishHeldTake();
      await it.settle();

      await tester.tap(it.onRow(2, find.text(_retry)));
      await it.until(
        'a junta parar de novo',
        () => it.container.read(salaSessionProvider).joining == null,
      );
      await it.settle();

      expect(
        it.onRow(2, find.text('trocar o ensaio desta cena')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a join row\'s quiet resends last 90 s from its first wait, however long '
    'it queued behind a slow upload',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.openThePlan();
      await tester.runAsync(() async {
        final slow = File('${it.harness.takesHome.path}/lenta.m4a')
          ..writeAsBytesSync([1, 2, 3, 4]);
        await it.harness.takes.enqueue(
          slow,
          sessionId: it.sessionId,
          kind: 'ensaio',
          scope: 'parte-9',
          chunkIndex: 9,
        );
      });
      it.holdTheTake('parte-9');
      it.room.unreachableTake = 'ensaio/parte-1';

      await it.tapJoin();
      await it.until(
        'a gravação lenta chegar à porta',
        () => it.theHeldTakeArrived,
      );
      await it.wait(const Duration(seconds: 100));
      int tries() => it.room.calls.where((call) => call == 'sendTake').length;
      final before = tries();
      it.room.finishHeldTake();
      await it.until(
        'a parte 1 esperar a primeira vez',
        () => tries() > before,
      );
      await it.wait(const Duration(seconds: 60));
      final at60 = tries();
      await it.wait(const Duration(seconds: 20));

      expect(it.onRow(1, find.text(_retry)), findsNothing);
      await it.until(
        'a parte 1 ser enviada de novo depois dos 60 s',
        () => tries() > at60,
      );
      await it.wait(const Duration(seconds: 20));
      await it.until(
        'a linha 1 pedir outra tentativa',
        () => it.onRow(1, find.text(_retry)).evaluate().isNotEmpty,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a join row behind a slow upload is not given up before its own request '
    'goes out',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.openThePlan();
      await tester.runAsync(() async {
        final slow = File('${it.harness.takesHome.path}/lenta.m4a')
          ..writeAsBytesSync([1, 2, 3, 4]);
        await it.harness.takes.enqueue(
          slow,
          sessionId: it.sessionId,
          kind: 'ensaio',
          scope: 'parte-9',
          chunkIndex: 9,
        );
      });
      it.room.holdNextTake('parte-9');

      await it.tapJoin();
      await it.until(
        'a gravação lenta chegar à porta',
        () => it.room.holdTakeScope == 'parte-9',
      );
      await it.wait(const Duration(seconds: 100));

      expect(it.onRow(1, find.text(_retry)), findsNothing);
      it.room.finishHeldTake();
      await it.until('a linha 1 ganhar o visto', () => it.ticked(1));
      semantics.dispose();
    },
  );

  testWidgets(
    'a joined part goes up above the highest pass the room holds for it when '
    'its row is written',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.takes.add(
        TakeView(
          takeId: 'gravacao-de-outro-tablet',
          kind: 'ensaio',
          scope: KeptScope.parte(2),
          ordinal: 2,
          pass: 3,
          origin: 'ensaio-de-outro-tablet',
        ),
      );
      it.room.takeAudio['gravacao-de-outro-tablet'] = _bytesOf(8);

      await it.tapJoin();
      await _theJoinEnds(it);

      final at = it.room.takesReceived.indexWhere((t) => t.scope == 'parte-2');
      expect(it.room.takePasses[at], 4);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a scene with an unsent hand-recorded take leaves the dot on the plan, '
    'not the recording home, and the take is not sent by it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      final sala = it.container.read(salaSessionProvider.notifier);
      it.room.unreachableTake = 'ensaio/parte-1';
      await tester.runAsync(() async {
        sala.goEnsaio();
        await waitFor(
          'as cenas chegarem',
          () => it.container.read(salaSessionProvider).sceneRows.length == 3,
        );
        sala.gravarACena(1);
        await waitFor(
          'a cena 1 gravar',
          () =>
              it.container.read(salaSessionProvider).ensaio ==
              EnsaioStatus.recording,
        );
        sala.gravarACena(1);
        await waitFor(
          'a gravação esperar o visto',
          () =>
              it.container.read(salaSessionProvider).ensaio ==
              EnsaioStatus.recorded,
        );
        sala.takeKeep();
        await waitFor(
          'a gravação à mão chegar ao Outbox',
          () async => (await it.harness.takes.pending()).any(
            (row) => row.scope == 'parte-1',
          ),
          limit: const Duration(seconds: 30),
        );
      });
      it.leftOnTheConversation();
      await it.relaunchOnTheConversation();
      final sent = it.partsReceived.length;

      await it.openThePlan();

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason:
            'a gravação à mão que não chegou à sala abria a casa de gravação, '
            'e a dela abre o plano',
      );
      expect(it.showsTheHome(), isFalse);
      expect(it.partsReceived, hasLength(sent));
      semantics.dispose();
    },
  );

  testWidgets(
    'a join row the room refuses over an approved draft stops on that row',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.openThePlan();
      it.room.refuseTake = 'ensaio/parte-2';
      it.room.refuseTakeCode = 'DRAFT_APPROVED';

      await it.tapJoin();
      await it.until(
        'a linha 2 pedir outra tentativa',
        () => it.onRow(2, find.text(_retry)).evaluate().isNotEmpty,
      );
      await it.settle();

      expect(it.partsReceived, ['parte-1']);
      expect(find.text(_planLine), findsOneWidget);
      final left = await tester.runAsync(it.harness.takes.pending);
      expect(
        left!.where((row) => row.scope == 'parte-2'),
        isEmpty,
        reason: 'uma linha recusada de vez não volta a subir sozinha',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'every joined part starts unheard, even after its rehearsal was played on '
    'the plan',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.openThePlan();
      await tester.tap(
        it.onRow(
          1,
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('Ouvir — ') ?? false),
          ),
        ),
      );
      await it.settle();
      expect(it.harness.playback.played.last, contains('cena-${it.idOf(1)}'));
      await it.wait(const Duration(seconds: 10));

      await it.tapJoin();
      await _theJoinEnds(it);
      await it.settle();

      final kept = it.harness.emAberto.rows.values.last.takes;
      expect(kept, hasLength(3));
      for (final take in kept) {
        expect(take.path, isNot(contains('cena-')));
        expect(take.origin, isNotNull);
      }
      it.container.read(salaSessionProvider.notifier).theAppWentAway();
      await it.settle();
      expect(
        [
          for (final report in it.room.listeningReports)
            for (final part in report)
              if ((part['played_ranges'] as List).isNotEmpty) part,
        ],
        isEmpty,
        reason: 'a escuta do ensaio no plano não conta para a parte',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'the Recording time a join row sends is the moment of the try that lands, '
    'not the rehearsal\'s and not the row\'s writing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await tester.runAsync(() async {
        final held = await it.harness.recorder.heldAs('cena-${it.idOf(1)}');
        File(held!).setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)),
        );
      });
      await it.openThePlan();
      it.room.unreachableTake = 'ensaio/parte-1';
      final tapped = clock.now();

      await it.tapJoin();
      await it.wait(const Duration(seconds: 2));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)),
      );
      it.room.unreachableTake = null;
      await it.wait(const Duration(seconds: 8));
      await it.until('a linha 1 ganhar o visto', () => it.ticked(1));

      final sent = it.room.takesReceivedWhole.first.recordedAt!;
      expect(sent.difference(tapped).inSeconds, lessThan(30));
      expect(
        sent.difference(tapped),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
        reason: 'a tentativa que chegou foi depois da escrita da linha',
      );
      await _theJoinEnds(it);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets('an English room shows the join in her English', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester, lingua: 'en', scenes: _threeScenesEn);
    it.seed();
    await it.openThePlan();
    it.holdTheTake('parte-1');

    await it.tapJoin(_joinEn);
    await it.until('a parte 1 chegar à porta', () => it.theHeldTakeArrived);
    expect(find.text('joining scene 1 of 3…'), findsOneWidget);
    await it.wait(const Duration(seconds: 70));
    await it.settle();

    expect(it.onRow(1, find.text(_retryEn), _threeScenesEn), findsOneWidget);
    it.room.finishHeldTake();
    await it.settle();
    semantics.dispose();
  });

  testWidgets(
    'on a plan the room records whole, «juntar» never writes a part over a '
    'scene whose hand take the tablet still holds',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.room.grain = Grain.whole;
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.aHandTakeHeld(1);
      await it.openThePlan();
      expect(find.text(_planLine), findsOneWidget);

      await it.tapJoin();
      await it.until('a junta parar', () {
        final estado = it.container.read(salaSessionProvider);
        return estado.joining == null && estado.joinRows.isNotEmpty;
      });

      expect(
        await it.scopesJoined(),
        isNot(contains('parte-1')),
        reason:
            'a junta escrevia a parte 1 por cima da gravação à mão que o tablet '
            'ainda não tinha enviado',
      );
      expect(it.container.read(salaSessionProvider).joinRows, contains(2));
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'with every joinable scene\'s hand take still on the tablet, «juntar» on '
    'the plan is closed and the plan stays',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.room.grain = Grain.whole;
      it.seed([1]);
      await it.heldOnTheTablet(1);
      await it.aHandTakeHeld(1);
      await it.openThePlan();
      expect(find.text(_planLine), findsOneWidget);
      expect(
        tester
            .widget<RoundActionButton>(
              find.ancestor(
                of: byLabel(_join),
                matching: find.byType(RoundActionButton),
              ),
            )
            .mood,
        ButtonMood.dimmed,
        reason: 'o «juntar» acenava sem nenhuma cena que pudesse juntar',
      );

      it.container.read(salaSessionProvider.notifier).joinTheScenes();
      await it.settle();

      expect(
        find.text(_planLine),
        findsOneWidget,
        reason:
            'o «juntar» não tinha nada a juntar e mesmo assim tirava a equipe do '
            'plano para a casa da gravação',
      );
      expect(it.container.read(salaSessionProvider).joinRows, isEmpty);
      expect(await it.scopesJoined(), isEmpty);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets('a scene recording asked while a join runs opens no microphone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    it.seed();
    for (final n in [1, 2, 3]) {
      await it.heldOnTheTablet(n);
    }
    await it.toTheRecordingHome();
    it.container.read(salaSessionProvider.notifier).leaveTheRecording();
    await it.settle();
    await it.openThePlan();
    it.holdTheTake('parte-1');
    await it.tapJoin();
    await it.until(
      'a junta da cena 1 chegar à porta',
      () =>
          it.theHeldTakeArrived &&
          it.container.read(salaSessionProvider).joining == 1,
    );

    it.container.read(salaSessionProvider.notifier).gravarACena(1);
    await it.settle();

    expect(
      it.container.read(salaSessionProvider).ensaio,
      EnsaioStatus.idle,
      reason:
          'a gravação da cena abria o microfone no meio da junta, e a tomada '
          'ia parar debaixo da parte que a sala estava juntando',
    );
    expect(it.harness.recorder.captures, 0);

    it.room.finishHeldTake();
    await _theJoinEnds(it);
    closeTheRoom(it.container);
    semantics.dispose();
  });

  testWidgets('a keep asked while a join runs keeps nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    it.seed();
    for (final n in [1, 2, 3]) {
      await it.heldOnTheTablet(n);
    }
    await it.toTheRecordingHome();
    final notifier = it.container.read(salaSessionProvider.notifier);
    notifier.leaveTheRecording();
    await it.settle();
    await it.openThePlan();
    notifier.gravarACena(1);
    await it.until(
      'a gravação da cena 1 começar',
      () =>
          it.container.read(salaSessionProvider).ensaio ==
          EnsaioStatus.recording,
    );
    notifier.gravarACena(1);
    await it.until(
      'a gravação da cena 1 terminar',
      () =>
          it.container.read(salaSessionProvider).ensaio ==
          EnsaioStatus.recorded,
    );
    it.holdTheTake('parte-1');
    notifier.joinTheScenes();
    await it.until(
      'a junta da cena 1 chegar à porta',
      () =>
          it.theHeldTakeArrived &&
          it.container.read(salaSessionProvider).joining == 1,
    );

    notifier.takeKeep();
    await it.settle();

    expect(
      it.container.read(salaSessionProvider).ensaio,
      EnsaioStatus.recorded,
      reason:
          'o guardar no meio da junta levava a tomada, e a parte da mão entrava '
          'na fila por cima da parte que a sala estava juntando',
    );
    final entries = (await tester.runAsync(it.harness.takes.entries))!;
    expect([
      for (final row in entries)
        if (row.origin == null) row.scope,
    ], isEmpty);

    it.room.finishHeldTake();
    await _theJoinEnds(it);
    closeTheRoom(it.container);
    semantics.dispose();
  });

  testWidgets(
    'a scene microphone open when a join starts still closes at its stop',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2, 3]) {
        await it.heldOnTheTablet(n);
      }
      await it.toTheRecordingHome();
      final notifier = it.container.read(salaSessionProvider.notifier);
      notifier.leaveTheRecording();
      await it.settle();
      await it.openThePlan();
      notifier.gravarACena(1);
      await it.until(
        'a gravação da cena 1 começar',
        () =>
            it.container.read(salaSessionProvider).ensaio ==
            EnsaioStatus.recording,
      );
      it.holdTheTake('parte-1');
      notifier.joinTheScenes();
      await it.until(
        'a junta da cena 1 chegar à porta',
        () =>
            it.theHeldTakeArrived &&
            it.container.read(salaSessionProvider).joining == 1,
      );

      notifier.gravarACena(1);
      await it.until(
        'a gravação da cena 1 terminar',
        () =>
            it.container.read(salaSessionProvider).ensaio !=
            EnsaioStatus.recording,
      );

      expect(
        it.container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recorded,
        reason:
            'a trava da junta ficava à frente do toque que fecha o microfone, e '
            'uma gravação aberta quando a junta começava não tinha como parar',
      );

      it.room.finishHeldTake();
      await _theJoinEnds(it);
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    "while a join runs, the notice's «enviar agora» of a take still on the "
    'tablet rests, and a tap sends nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2]) {
        await it.heldOnTheTablet(n);
      }
      await it.aHandTakeGivenUp(3);
      await it.openThePlan();
      expect(find.text(_planLine), findsOneWidget);
      expect(it.sendNow, findsOneWidget);
      it.room.unreachableTake = null;
      it.holdTheTake('parte-1');

      await it.tapJoin();
      await it.until('a parte 1 ficar presa na sala', () => it.room.takeHeld);
      final asked = it.room.takesAsked.length;

      expect(
        tester.widget<TextButton>(it.sendNow).onPressed,
        isNull,
        reason: 'o «enviar agora» ficava aceso no meio da junta',
      );
      expect(
        tester
            .getSemantics(byLabel(_enviarAGravacao))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
        reason: 'o VoiceOver lia o botão como vivo no meio da junta',
      );
      await tester.tap(it.sendNow, warnIfMissed: false);
      await it.beat();
      expect(it.room.takesAsked.skip(asked), isEmpty);

      it.room.finishHeldTake();
      await _theJoinEnds(it);
      expect(
        it.room.takesAsked.skip(asked),
        isNot(contains('ensaio/parte-3')),
        reason: 'o toque no meio da junta mandava a parte 3 depois dela',
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    "a scene's enviar agora asked of the notifier while a join runs is refused, "
    'and the part never goes up after the join',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      for (final n in [1, 2]) {
        await it.heldOnTheTablet(n);
      }
      await it.aHandTakeGivenUp(3);
      await it.openThePlan();
      expect(it.sendNow, findsOneWidget);
      it.room.unreachableTake = null;
      it.holdTheTake('parte-1');

      await it.tapJoin();
      await it.until('a parte 1 ficar presa na sala', () => it.room.takeHeld);
      final asked = it.room.takesAsked.length;

      it.container.read(salaSessionProvider.notifier).enviarACena(3);
      await it.beat();
      it.room.finishHeldTake();
      await _theJoinEnds(it);
      await it.wait(const Duration(seconds: 5));

      expect(
        it.room.takesAsked.skip(asked),
        isNot(contains('ensaio/parte-3')),
        reason:
            'o enviarACena no meio da junta punha a parte 3 de novo na fila, e '
            'ela subia logo depois da junta',
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    "while one scene's take goes up from the notice, the other scene's «enviar "
    'agora» rests, and is offered again once it landed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.seed();
      await it.heldOnTheTablet(1);
      await it.aHandTakeGivenUp(2);
      await it.aHandTakeGivenUp(3);
      await it.openThePlan();
      expect(it.sendNowOf(2), findsOneWidget);
      expect(it.sendNowOf(3), findsOneWidget);
      it.room.unreachableTake = null;
      it.holdTheTake('parte-2');

      await tester.tap(it.sendNowOf(2));
      await it.until('a parte 2 ficar presa na sala', () => it.room.takeHeld);

      expect(
        tester.widget<TextButton>(it.sendNowOf(3)).onPressed,
        isNull,
        reason:
            'o «enviar agora» da cena 3 ficava aceso enquanto a cena 2 subia',
      );

      it.room.finishHeldTake();
      await it.until(
        'a parte 2 chegar',
        () => it.partsReceived.contains('parte-2'),
      );
      await it.until(
        'o «enviar agora» da cena 3 voltar',
        () =>
            it.sendNowOf(3).evaluate().isNotEmpty &&
            tester.widget<TextButton>(it.sendNowOf(3)).onPressed != null,
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );
}
