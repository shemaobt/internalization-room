import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart'
    show
        byLabel,
        holdTheSession,
        intoTheBackTranslation,
        offTheRows,
        thePersonSign,
        voiceOverFocusLeaves;

const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _homeLineEn =
    'Record, listen back, and record again as many times as you need.';
const _bringBack = 'trazer de volta as traduções do ensaio desta cena';
const _bringBackArmed =
    'toquem de novo: as traduções do ensaio voltam; as que vocês fizeram aqui '
    'para esta cena ficam guardadas';
const _failed = 'não deu para juntar esta cena — toquem para tentar de novo';
const _cannotEnter = 'este ensaio não pode entrar — ensaiem esta cena de novo';
const _bringBackEn = 'bring back this scene rehearsal\'s translations';
const _bringBackArmedEn =
    'tap again: the rehearsal\'s translations come back; the ones you made '
    'here for this scene are kept';
const _failedEn = 'this scene could not be joined — tap to try again';
const _cannotEnterEn =
    'this rehearsal cannot be used — rehearse this scene again';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _ouvir = 'Ouvir';
const _gravarDeNovo = 'Gravar de novo';
const _tentarDeNovo = 'Tentar enviar de novo';
const _enviarAGravacao = 'Enviar a gravação';
const _conferir = 'ouvir e conferir o Ensaio Final';
const _heldFailed = 'não deu para guardar a frase — tentar de novo';

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
    );

List<SegmentView> _theRehearsalsFrases(int n) => [
  SegmentView(
    segmentId: 'laid-$n-a',
    takeId: 'gravacao-junta-$n',
    startsMs: 0,
    endsMs: 3000,
    frase: 2 * n - 1,
  ),
  SegmentView(
    segmentId: 'laid-$n-b',
    takeId: 'gravacao-junta-$n',
    startsMs: 3000,
    endsMs: 6000,
    frase: 2 * n,
  ),
];

class _Home {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;
  final List<Scene> scenes;

  _Home(this.tester, this.harness, this.container, this.scenes);

  FakeRoom get room => harness.room;

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  String get sessionId => container.read(salaSessionProvider).sessionId!;

  bool get english => identical(scenes, _threeScenesEn);

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

  void joinedInTheRoom(String sessionId) {
    for (final n in [1, 2, 3]) {
      room.sceneRehearsals.add(_rehearsal(sessionId, n));
      room.sceneAudioOf[_idOf(sessionId, n)] = _bytesOf(n);
      room.takes.add(
        TakeView(
          takeId: 'gravacao-junta-$n',
          kind: 'ensaio',
          scope: KeptScope.parte(n),
          ordinal: n,
          pass: 1,
          origin: _idOf(sessionId, n),
        ),
      );
      room.takeAudio['gravacao-junta-$n'] = _bytesOf(n);
    }
  }

  bool get showsTheHome =>
      find.text(english ? _homeLineEn : _homeLine).evaluate().isNotEmpty;

  Future<void> openTheHome() async {
    await tester.tap(_dot);
    await until('a casa de gravação abrir', () => showsTheHome);
    await settle();
  }

  Finder row(int n) =>
      byLabel('${english ? 'Scene' : 'Cena'} $n — ${scenes[n - 1].title}');

  Finder onRow(int n, Finder target) =>
      find.descendant(of: row(n), matching: target);

  Finder control(int n, String label) =>
      byLabel('$label — ${english ? 'Scene' : 'Cena'} $n');

  Future<void> tapThe(Finder target) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target, warnIfMissed: false);
    await beat();
  }
}

Future<void> _toTheConversation(_Home it) async {
  await it.settle();
  unawaited(it.notifier.abrirEscolha());
  await it.settle();
  unawaited(it.notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await it.until(
    'a conversa abrir',
    () =>
        it.container.read(salaSessionProvider).voice == VoiceState.invite &&
        !it.container.read(salaSessionProvider).awaitingTheGuide,
  );
  await it.wait(const Duration(milliseconds: 1500));
}

SalaHarness _aHarness(String lingua, List<Scene> scenes) {
  final home = Directory.systemTemp.createTempSync('sala-1405-traz');
  return SalaHarness(lingua: lingua, takesHome: home)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes;
}

Future<_Home> _mount(
  WidgetTester tester,
  SalaHarness harness,
  List<Scene> scenes,
) async {
  tester.view
    ..physicalSize = const Size(820, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = (await tester.runAsync(
    () async => harness.container()..read(salaSessionProvider),
  ))!;
  final it = _Home(tester, harness, container, scenes);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return it;
}

Future<_Home> _onTheConversation(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  List<int>? offered,
}) async {
  final harness = _aHarness(lingua, scenes);
  if (offered != null) {
    harness.room.retroSoFar = BackTranslationProgress(bringBack: offered);
  }
  final it = await _mount(tester, harness, scenes);
  await _toTheConversation(it);
  it.joinedInTheRoom(it.sessionId);
  return it;
}

Future<_Home> _onTheHome(
  WidgetTester tester, {
  List<int> bringBack = const [2],
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
}) async {
  final it = await _onTheConversation(tester, lingua: lingua, scenes: scenes);
  it.room.retroSoFar = BackTranslationProgress(bringBack: bringBack);
  await it.openTheHome();
  return it;
}

Future<_Home> _inTheBackTranslation(
  WidgetTester tester, {
  String? heldSentence,
}) async {
  const sessionId = 'sessao-antiga';
  final harness = _aHarness('pt', _threeScenes);
  final folder = Directory.systemTemp.createTempSync('sala-1405-retro');
  addTearDown(() => folder.deleteSync(recursive: true));
  if (heldSentence != null) {
    await tester.runAsync(
      () => harness.takes.enqueue(
        File('${folder.path}/frase.wav')..writeAsBytesSync(_bytesOf(9)),
        sessionId: sessionId,
        kind: 'frase',
        scope: heldSentence,
      ),
    );
  }
  final row = ResumePoint(
    sessionId: sessionId,
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2, 3])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${folder.path}/p$n.wav',
          )..writeAsBytesSync(_bytesOf(n))).path,
          takeId: 'gravacao-junta-$n',
          origin: _idOf(sessionId, n),
        ),
    ],
  );
  await holdTheSession(harness, row);
  harness.room.retroSoFar = BackTranslationProgress(
    segments: [
      for (final n in [1, 2, 3]) ..._theRehearsalsFrases(n),
    ],
  );
  final it = await _mount(tester, harness, _threeScenes);
  it.joinedInTheRoom(sessionId);
  await intoTheBackTranslation(
    it.notifier,
    () => it.container.read(salaSessionProvider),
    step: it.beat,
  );
  await it.until(
    'a tradução voltar',
    () =>
        it.container.read(salaSessionProvider).stage == SalaStage.retro &&
        it.container.read(salaSessionProvider).btTrechos.length == 6,
  );
  await it.settle();
  return it;
}

Future<void> _bringBackTwice(_Home it, int n) async {
  await it.tapThe(it.control(n, _bringBack));
  await it.wait(const Duration(milliseconds: 700));
  await it.tapThe(it.control(n, _bringBackArmed));
  await it.beat();
}

void main() {
  testWidgets(
    'after a restart in the Back-translation, back on the recording home, the '
    'joined scene\'s row offers «trazer de volta as traduções do ensaio desta '
    'cena»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester);
      final restart = byLabel('recomeçar a tradução');
      await it.tapThe(restart);
      await it.wait(const Duration(milliseconds: 700));
      await it.tapThe(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').startsWith('toquem de novo'),
        ),
      );
      await it.until(
        'a sala recomeçar',
        () => it.room.restartsAsked.isNotEmpty,
      );
      await it.settle();
      it.room.retroSoFar = const BackTranslationProgress(bringBack: [2]);

      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();

      expect(it.onRow(2, it.control(2, _bringBack)), findsOneWidget);
      expect(it.control(1, _bringBack), findsNothing);
      expect(it.control(3, _bringBack), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'a sentence held on the tablet in the scene brought back is never sent onto '
    'its rehearsal\'s frases',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester, heldSentence: 'laid-2-a');
      expect(byLabel(_heldFailed), findsOneWidget);
      final laid = [
        for (final n in [1, 2, 3]) ..._theRehearsalsFrases(n),
      ];
      it.room.segments
        ..clear()
        ..addAll(laid);
      it.room.retroSoFar = BackTranslationProgress(
        segments: laid,
        bringBack: const [2],
      );

      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      await _bringBackTwice(it, 2);
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      await it.tapThe(byLabel(_conferir));
      await it.until(
        'a tradução abrir',
        () => it.container.read(salaSessionProvider).stage == SalaStage.retro,
      );
      await it.settle();

      expect(byLabel(_heldFailed), findsNothing);
      expect(it.room.sentencesSent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'a sentence held on the tablet in another scene stays held after a '
    'bring-back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester, heldSentence: 'laid-1-a');
      expect(byLabel(_heldFailed), findsOneWidget);
      final laid = [
        for (final n in [1, 2, 3]) ..._theRehearsalsFrases(n),
      ];
      it.room.segments
        ..clear()
        ..addAll(laid);
      it.room.retroSoFar = BackTranslationProgress(
        segments: laid,
        bringBack: const [2],
      );

      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      await _bringBackTwice(it, 2);
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      await it.tapThe(byLabel(_conferir));
      await it.until(
        'a tradução abrir',
        () => it.container.read(salaSessionProvider).stage == SalaStage.retro,
      );
      await it.settle();

      expect(byLabel(_heldFailed), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a sentence held in the scene brought back is let go even after the room '
    'renumbered the frases, by its stretch and not by its old number',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester, heldSentence: 'laid-2-a');
      expect(byLabel(_heldFailed), findsOneWidget);
      final laid = [
        for (final (antes, frase) in [
          for (final n in [2, 3]) ..._theRehearsalsFrases(n),
        ].indexed)
          SegmentView(
            segmentId: frase.segmentId,
            takeId: frase.takeId,
            startsMs: frase.startsMs,
            endsMs: frase.endsMs,
            frase: antes + 1,
          ),
      ];
      it.room.segments
        ..clear()
        ..addAll(laid);
      it.room.retroSoFar = BackTranslationProgress(segments: laid);
      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      it.notifier.startRetro();
      await it.until(
        'a sala renumerar as frases',
        () => it.container.read(salaSessionProvider).btTrechos.length == 4,
      );
      await it.settle();
      expect(byLabel(_heldFailed), findsOneWidget);
      it.room.retroSoFar = BackTranslationProgress(
        segments: laid,
        bringBack: const [2],
      );

      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      await _bringBackTwice(it, 2);
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      await it.tapThe(byLabel(_conferir));
      await it.until(
        'a tradução abrir',
        () => it.container.read(salaSessionProvider).stage == SalaStage.retro,
      );
      await it.settle();

      expect(
        byLabel(_heldFailed),
        findsNothing,
        reason:
            'a frase guardada da cena trazida de volta ficava, porque o '
            'número dela já era de outra cena',
      );
      expect(it.room.sentencesSent, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'a scene brought back asks the room what is left, so a return out of its '
    'reach says the stretch the room names now, not nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester);
      final laid = [
        for (final n in [1, 2, 3]) ..._theRehearsalsFrases(n),
      ];
      it.room.segments
        ..clear()
        ..addAll(laid);
      it.room.retroSoFar = BackTranslationProgress(
        segments: laid,
        bringBack: const [2],
      );
      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      it.room
        ..listeningUnheardTakeIds = const []
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = const [
          UntranslatedPart(
            takeId: 'gravacao-junta-2',
            scene: 2,
            from: Duration(milliseconds: 3000),
          ),
        ];
      await _bringBackTwice(it, 2);
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      it.room.reachable = false;
      final linhas = it.harness.voice.fixedLines.length;

      await it.tapThe(byLabel(_conferir));
      await it.until(
        'a tradução abrir',
        () => it.container.read(salaSessionProvider).stage == SalaStage.retro,
      );
      await it.settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N2', 'pt')],
        reason:
            'a cena trazida de volta não perguntava nada à sala, e a volta sem '
            'rede ficava calada sobre o trecho que a sala contava sem tradução',
      );
      expect(
        it.harness.playback.played.last,
        it.container.read(salaSessionProvider).partes[1].path,
      );
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(milliseconds: 3000),
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets(
    'a bring-back the room made whose answer was lost still asks the room what '
    'is left, so a return out of its reach says the stretch it names now',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _inTheBackTranslation(tester);
      final laid = [
        for (final n in [1, 2, 3]) ..._theRehearsalsFrases(n),
      ];
      it.room.segments
        ..clear()
        ..addAll(laid);
      it.room.retroSoFar = BackTranslationProgress(
        segments: laid,
        bringBack: const [2],
      );
      it.notifier.goEnsaio();
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();
      it.room
        ..listeningUnheardTakeIds = const []
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = const [
          UntranslatedPart(
            takeId: 'gravacao-junta-2',
            scene: 2,
            from: Duration(milliseconds: 3000),
          ),
        ];
      it.room.failBringBackWith = const NetworkFailed('a resposta se perdeu');

      await it.tapThe(it.control(2, _bringBack));
      await it.wait(const Duration(milliseconds: 700));
      it.room.retroSoFar = BackTranslationProgress(segments: laid);
      await it.tapThe(it.control(2, _bringBackArmed));
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      expect(it.control(2, _bringBack), findsNothing);
      it.room.reachable = false;
      final linhas = it.harness.voice.fixedLines.length;

      await it.tapThe(byLabel(_conferir));
      await it.until(
        'a tradução abrir',
        () => it.container.read(salaSessionProvider).stage == SalaStage.retro,
      );
      await it.settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N2', 'pt')],
        reason:
            'a cena que a sala trouxe de volta com a resposta perdida não '
            'perguntava nada à sala, e a volta sem rede ficava calada sobre o '
            'trecho que ela contava sem tradução',
      );
      expect(
        it.harness.playback.played.last,
        it.container.read(salaSessionProvider).partes[1].path,
      );
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(milliseconds: 3000),
      );
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets('two taps bring the rehearsal\'s translations back', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester);

    await it.tapThe(it.control(2, _bringBack));
    expect(it.onRow(2, it.control(2, _bringBackArmed)), findsOneWidget);
    expect(it.room.bringBacksAsked, isEmpty);
    await it.wait(const Duration(milliseconds: 700));
    await it.tapThe(it.control(2, _bringBackArmed));
    await it.settle();

    expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
    expect(it.control(2, _bringBack), findsNothing);
    expect(it.control(2, _bringBackArmed), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'a joined scene whose translations never came is offered the bring-back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheConversation(tester);
      await it.settle();
      it.room.retroSoFar = const BackTranslationProgress(bringBack: [3]);

      await it.openTheHome();

      expect(it.onRow(3, it.control(3, _bringBack)), findsOneWidget);
      expect(it.control(2, _bringBack), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'a single tap and nothing for 7 seconds sends nothing and the control rests '
    'again',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);

      await it.tapThe(it.control(2, _bringBack));
      await it.wait(const Duration(milliseconds: 5900));
      expect(it.control(2, _bringBackArmed), findsOneWidget);
      await it.wait(const Duration(milliseconds: 200));
      expect(it.control(2, _bringBackArmed), findsNothing);
      expect(it.control(2, _bringBack), findsOneWidget);

      await it.tapThe(it.control(2, _bringBack));
      expect(it.control(2, _bringBackArmed), findsOneWidget);
      expect(it.room.bringBacksAsked, isEmpty);
      await it.wait(const Duration(seconds: 7));
      semantics.dispose();
    },
  );

  testWidgets('a second tap before 0.6 seconds counts for nothing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester);

    await it.tapThe(it.control(2, _bringBack));
    await it.wait(const Duration(milliseconds: 300));
    await it.tapThe(it.control(2, _bringBackArmed));
    await it.settle();

    expect(it.room.bringBacksAsked, isEmpty);
    expect(it.control(2, _bringBackArmed), findsOneWidget);
    await it.wait(const Duration(seconds: 7));
    semantics.dispose();
  });

  testWidgets('VoiceOver focus leaving the armed bring-back disarms it, and '
      'the next tap only arms', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester);

    await it.tapThe(it.control(2, _bringBack));
    await it.wait(const Duration(seconds: 1));
    expect(it.control(2, _bringBackArmed), findsOneWidget);

    voiceOverFocusLeaves(tester, it.control(2, _bringBackArmed));
    await it.wait(const Duration(milliseconds: 100));

    expect(
      it.control(2, _bringBack),
      findsOneWidget,
      reason: 'o trazer de volta seguia armado depois que o foco saiu dele',
    );
    expect(it.control(2, _bringBackArmed), findsNothing);

    await it.tapThe(it.control(2, _bringBack));
    await it.settle();

    expect(it.control(2, _bringBackArmed), findsOneWidget);
    expect(
      it.room.bringBacksAsked,
      isEmpty,
      reason: 'o toque seguinte trazia de volta em vez de só armar',
    );
    await it.wait(const Duration(seconds: 7));
    semantics.dispose();
  });

  testWidgets('another gesture between the two taps disarms it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester);

    await it.tapThe(it.control(2, _bringBack));
    await it.tapThe(it.onRow(1, byLabel(_ouvir)));
    expect(it.control(2, _bringBack), findsOneWidget);
    await it.wait(const Duration(seconds: 1));
    await it.tapThe(it.control(2, _bringBack));
    await it.settle();

    expect(it.room.bringBacksAsked, isEmpty);
    expect(it.control(2, _bringBackArmed), findsOneWidget);
    await it.wait(const Duration(seconds: 7));
    semantics.dispose();
  });

  testWidgets(
    'while it is bringing back, nothing on the recording home starts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.unreachableTake = 'ensaio/parte-1';
      await tester.runAsync(() async {
        it.notifier.gravarACena(1);
        await waitFor(
          'a cena 1 gravar',
          () =>
              it.container.read(salaSessionProvider).ensaio ==
              EnsaioStatus.recording,
        );
        it.notifier.gravarACena(1);
        await waitFor(
          'a gravação esperar o visto',
          () =>
              it.container.read(salaSessionProvider).ensaio ==
              EnsaioStatus.recorded,
        );
        it.notifier.takeKeep();
      });
      await it.until(
        'a cena 1 ficar sem enviar',
        () => it.onRow(1, byLabel(_tentarDeNovo)).evaluate().isNotEmpty,
      );
      await it.settle();
      final captures = it.harness.recorder.captures;
      final played = it.harness.playback.played.length;
      final retry = it.onRow(1, byLabel(_tentarDeNovo));
      it.room.holdBringBack();

      await _bringBackTwice(it, 2);
      expect(it.room.bringBacksAsked, hasLength(1));
      await it.tapThe(it.onRow(1, byLabel(_gravarDeNovo)));
      await it.tapThe(offTheRows(_ouvir));
      await it.settle();

      expect(it.harness.recorder.captures, captures);
      expect(it.harness.playback.played, hasLength(played));
      await tester.ensureVisible(retry);
      await tester.pump();
      expect(retry.hitTestable(), findsNothing);
      for (final control in [
        it.onRow(1, byLabel(_gravarDeNovo)),
        offTheRows(_ouvir),
        byLabel(_enviarAGravacao),
        byLabel(_conferir),
        retry,
      ]) {
        expect(
          tester.getSemantics(control).flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: '$control',
        );
      }

      it.room.finishHeldBringBack();
      await it.settle();
      await tester.ensureVisible(retry);
      await tester.pump();
      expect(retry.hitTestable(), findsOneWidget);
      await it.tapThe(offTheRows(_ouvir));
      await it.until(
        'o ensaio tocar de novo',
        () => it.harness.playback.played.length > played,
      );
      it.room.unreachableTake = null;
      semantics.dispose();
    },
  );

  testWidgets(
    'a Session read sent before the bring-back and landing after it does not '
    'offer it again',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheConversation(tester, offered: [2]);
      it.room.holdTheNextRead();
      await tester.tap(_dot);
      await it.until('a casa de gravação abrir', () => it.showsTheHome);
      await it.settle();

      await _bringBackTwice(it, 2);
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      it.room.answerHeldRead(0);
      await it.settle();

      expect(it.control(2, _bringBack), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'a bring-back the room made whose answer was lost leaves no note and no '
    'control',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.failBringBackWith = const NetworkFailed('a resposta se perdeu');

      await it.tapThe(it.control(2, _bringBack));
      await it.wait(const Duration(milliseconds: 700));
      it.room.retroSoFar = BackTranslationProgress(
        segments: _theRehearsalsFrases(2),
      );
      await it.tapThe(it.control(2, _bringBackArmed));
      await it.settle();

      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      expect(it.control(2, _bringBack), findsNothing);
      expect(find.text(_failed), findsNothing);
      expect(thePersonSign, findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'a bring-back the room says can never come back tells the team to '
    'rehearse the scene again, not to tap again',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.failBringBackWith = const Refused(RefusalCode.nothingToBringBack);

      await _bringBackTwice(it, 2);
      await it.settle();

      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      expect(
        it.onRow(2, find.text(_cannotEnter)),
        findsOneWidget,
        reason:
            'a recusa que nunca muda virava «toquem para tentar de novo», e a '
            'equipe tocava em vão',
      );
      expect(find.text(_failed), findsNothing);
      expect(thePersonSign, findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the rehearse-again line stays on its row after the room stops offering '
    'the bring-back, as hers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.failBringBackWith = const Refused(RefusalCode.nothingToBringBack);

      await it.tapThe(it.control(2, _bringBack));
      await it.wait(const Duration(milliseconds: 700));
      it.room.retroSoFar = const BackTranslationProgress();
      await it.tapThe(it.control(2, _bringBackArmed));
      await it.settle();

      expect(it.control(2, _bringBack), findsNothing);
      expect(
        it.onRow(2, find.text(_cannotEnter)),
        findsOneWidget,
        reason:
            'a nova leitura da sessão já não oferecia a parte e apagava o '
            'aviso: a linha sumia junto com o botão',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a bring-back lost on the network still asks for another tap, not for '
    'another rehearsal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.failBringBackWith = const NetworkFailed('a rede caiu');

      await _bringBackTwice(it, 2);
      await it.settle();

      expect(
        it.onRow(2, find.text(_failed)),
        findsOneWidget,
        reason: 'uma falha de passagem não pede para ensaiar a cena de novo',
      );
      expect(find.text(_cannotEnter), findsNothing);
      expect(it.control(2, _bringBack), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a refusal the tablet does not know as final still asks for another tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheHome(tester);
      it.room.failBringBackWith = const Refused(RefusalCode.unreadable);

      await _bringBackTwice(it, 2);
      await it.settle();

      expect(
        it.onRow(2, find.text(_failed)),
        findsOneWidget,
        reason: 'só a recusa que diz que nada volta é para ensaiar de novo',
      );
      expect(find.text(_cannotEnter), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('a bring-back that can never come back says nothing out loud', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester);
    it.room.failBringBackWith = const Refused(RefusalCode.nothingToBringBack);

    await it.tapThe(it.control(2, _bringBack));
    await it.wait(const Duration(milliseconds: 700));
    final played = [...it.harness.voice.played];
    final fixedLines = [...it.harness.voice.fixedLines];
    await it.tapThe(it.control(2, _bringBackArmed));
    await it.settle();

    expect(it.onRow(2, find.text(_cannotEnter)), findsOneWidget);
    expect(it.harness.voice.played, played);
    expect(
      it.harness.voice.fixedLines,
      fixedLines,
      reason: 'a linha da recusa é escrita, nunca falada',
    );
    semantics.dispose();
  });

  testWidgets(
    'over an approved draft the bring-back keeps its own armed text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _onTheConversation(tester);
      it.room.approvedDraft = const ApprovedDraft(version: 1);
      it.room.retroSoFar = const BackTranslationProgress(bringBack: [2]);
      await it.openTheHome();

      await it.tapThe(it.control(2, _bringBack));

      expect(it.control(2, _bringBackArmed), findsOneWidget);
      expect(find.text(_reopenArmed), findsNothing);
      await it.wait(const Duration(milliseconds: 700));
      await it.tapThe(it.control(2, _bringBackArmed));
      await it.settle();
      expect(it.room.bringBacksAsked, [(it.sessionId, 2)]);
      semantics.dispose();
    },
  );

  testWidgets('an English room shows the bring-back in her English', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _onTheHome(tester, lingua: 'en', scenes: _threeScenesEn);
    it.room.failBringBackWith = const Refused(RefusalCode.nothingToBringBack);

    expect(it.control(2, _bringBackEn), findsOneWidget);
    await it.tapThe(it.control(2, _bringBackEn));
    expect(it.control(2, _bringBackArmedEn), findsOneWidget);
    await it.wait(const Duration(milliseconds: 700));
    await it.tapThe(it.control(2, _bringBackArmedEn));
    await it.settle();

    expect(
      it.onRow(2, find.text(_cannotEnterEn)),
      findsOneWidget,
      reason: 'a sala em inglês também mandava tocar de novo o que nunca entra',
    );
    expect(find.text(_failedEn), findsNothing);
    semantics.dispose();
  });
}
