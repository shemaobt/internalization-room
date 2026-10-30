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
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_final_plan_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/listen_glyph.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show byLabel, relaunch, thePersonSign, voiceOverFocusLeaves;

const _recordEnsaio = 'Gravar o ensaio de vocês';
const _recordEnsaioEn = 'Record your rehearsal';

const _diskWord = 'não deu para guardar o ensaio da cena neste computador';
const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _thinking = 'pensando…';
const _sceneByScene = 'Gravar cena por cena';
const _missing = 'falta o ensaio desta cena';
const _cannotEnter = 'este ensaio não pode entrar — ensaiem esta cena de novo';
const _partial = 'tradução incompleta';
const _swap = 'trocar o ensaio desta cena';
const _join = 'juntar as cenas e ouvir';
const _how = 'Como vocês querem gravar?';
const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _sceneByScenePick = 'Cena por cena';
const _elsewhere =
    'Os ensaios desta passagem foram gravados com o aplicativo na outra '
    'língua. Voltem para aquela língua para abrir o Ensaio Final.';
const _elsewhereEn =
    'This passage\'s rehearsals were recorded with the app in the other '
    'language. Switch back to that language to open the Final Rehearsal.';

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

final _recordedAt = DateTime.utc(2026, 10, 22, 13, 7);

String _clock(DateTime at) {
  final local = at.toLocal();
  return '${'${local.hour}'.padLeft(2, '0')}:'
      '${'${local.minute}'.padLeft(2, '0')}';
}

String _sentAt(String hhmm) => '2026-10-22T$hhmm:00+00:00';

List<SceneFrase> _tiling(int durationMs, int k) => [
  for (var i = 0; i < k; i++)
    SceneFrase(
      fraseId: 'frase-$i',
      startsMs: durationMs * i ~/ k,
      endsMs: durationMs * (i + 1) ~/ k,
    ),
];

SceneRehearsalRecord _rehearsal(
  String sessionId, {
  required int n,
  required String? scene,
  String? sentAt = '2026-10-22T10:00:00+00:00',
  int durationMs = 7000,
  int k = 2,
  List<SceneFrase>? frases,
  String contentType = 'audio/wav',
  bool verified = true,
}) => SceneRehearsalRecord(
  rehearsalId: '$sessionId-ensaio-$n',
  sessionId: sessionId,
  n: n,
  scene: scene,
  recordedAt: _recordedAt,
  sentAt: sentAt,
  durationMs: durationMs,
  frases: frases ?? _tiling(durationMs, k),
  contentType: contentType,
  verified: verified,
);

List<SceneRehearsalRecord> _oneEach(String sessionId) => [
  _rehearsal(sessionId, n: 1, scene: 'S1', durationMs: 6600, k: 2),
  _rehearsal(sessionId, n: 2, scene: 'S2', durationMs: 12000, k: 3),
  _rehearsal(sessionId, n: 3, scene: 'S3', durationMs: 65000, k: 1),
];

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {_recordEnsaio, _recordEnsaioEn}.contains(widget.properties.label),
);

Finder _row(int n, [List<Scene> scenes = _threeScenes]) =>
    byLabel('${_sceneWord(scenes)} $n — ${scenes[n - 1].title}');

String _sceneWord(List<Scene> scenes) =>
    identical(scenes, _threeScenesEn) ? 'Scene' : 'Cena';

Finder _onRow(int n, Finder target, [List<Scene> scenes = _threeScenes]) =>
    find.descendant(of: _row(n, scenes), matching: target);

Finder _playOn(int n, [List<Scene> scenes = _threeScenes]) => _onRow(
  n,
  find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label?.startsWith(
              identical(scenes, _threeScenesEn) ? 'Listen — ' : 'Ouvir — ',
            ) ??
            false),
  ),
  scenes,
);

String _facts(int n, String dur, int k) =>
    'ensaio $n · ${_clock(_recordedAt)} · $dur · $k frases';

Finder _paintedOn(Finder control) => find.descendant(
  of: control,
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ListenGlyphPainter,
  ),
);

ListenGlyph _glyphOn(WidgetTester tester, Finder control) =>
    (tester.widget<CustomPaint>(_paintedOn(control)).painter!
            as ListenGlyphPainter)
        .glyph;

Tristate _pressedAt(WidgetTester tester, Finder control) =>
    tester.getSemantics(control).getSemanticsData().flagsCollection.isSelected;

Tristate _enabledAt(WidgetTester tester, String label) => tester
    .getSemantics(byLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isEnabled;

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

Future<(SalaHarness, ProviderContainer)> _atRest(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  Duration? playbackCeiling,
}) async {
  final harness =
      SalaHarness(
          lingua: lingua,
          filaEmMemoria: true,
          playbackCeiling: playbackCeiling,
        )
        ..room.passages = const [_thePassage]
        ..room.nextMoment = _midConversation
        ..room.passageScenes = scenes;
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

/// A room at rest on the Conversation whose listing holds what [seed] lays for this
/// session's id.
Future<(SalaHarness, ProviderContainer)> _seeded(
  WidgetTester tester,
  List<SceneRehearsalRecord> Function(String session) seed, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
  Duration? playbackCeiling,
}) async {
  final (harness, container) = await _atRest(
    tester,
    lingua: lingua,
    scenes: scenes,
    playbackCeiling: playbackCeiling,
  );
  harness.room.sceneRehearsals.addAll(
    seed(container.read(salaSessionProvider).sessionId!),
  );
  return (harness, container);
}

Future<void> _theAnswerSettles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openThePlan(WidgetTester tester) async {
  await tester.tap(_dot);
  await tester.pump(const Duration(milliseconds: 100));
  await _theAnswerSettles(tester);
}

Future<void> _tapSwapOn(WidgetTester tester, int n) async {
  await tester.tap(_onRow(n, find.text(_swap)));
  await _theAnswerSettles(tester);
}

Future<void> _useTheRehearsal(WidgetTester tester, int n) async {
  final useThis = byLabel('usar este — ${_facts(n, '0:07', 2)} · enviado');
  await tester.ensureVisible(useThis);
  await tester.tap(useThis);
  await _theAnswerSettles(tester);
}

Future<ProviderContainer> _relaunchOnTheConversation(
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

void main() {
  testWidgets(
    'on the plan over an approved draft, VoiceOver focus leaving the armed '
    'whole switch reads «gravar a passagem inteira de uma vez» again, and the '
    'next tap only arms',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(tester, _oneEach);
      harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _relaunchOnTheConversation(tester, harness, container);
      await _openThePlan(tester);
      expect(find.text(_planLine), findsOneWidget);
      await tester.ensureVisible(find.text(_wholeAtOnce));
      await tester.tap(find.text(_wholeAtOnce));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_reopenArmed), findsOneWidget);

      voiceOverFocusLeaves(tester, byLabel(_reopenArmed));
      await _theAnswerSettles(tester);

      expect(
        find.text(_wholeAtOnce),
        findsOneWidget,
        reason: 'no plano o botão seguia armado depois que o foco saiu dele',
      );
      expect(find.text(_reopenArmed), findsNothing);

      await tester.tap(find.text(_wholeAtOnce));
      await _theAnswerSettles(tester);

      expect(find.text(_reopenArmed), findsOneWidget);
      expect(
        harness.room.grainSwitches,
        isEmpty,
        reason: 'o toque seguinte trocava o grão em vez de só armar',
      );
      await tester.pump(const Duration(seconds: 8));
      semantics.dispose();
    },
  );

  group('1. three scenes with one sent rehearsal each', () {
    testWidgets('show three rows with their facts and play', (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);

      await _openThePlan(tester);

      expect(find.text(_planLine), findsOneWidget);
      for (final (n, dur, k) in [
        (1, '0:07', 2),
        (2, '0:12', 3),
        (3, '1:05', 1),
      ]) {
        expect(_row(n), findsOneWidget, reason: 'a linha $n faltou');
        expect(_onRow(n, find.text('Cena $n')), findsOneWidget);
        expect(_onRow(n, find.text(_threeScenes[n - 1].title)), findsOneWidget);
        expect(_onRow(n, find.text(_facts(n, dur, k))), findsOneWidget);
        expect(_playOn(n), findsOneWidget, reason: 'a linha $n não toca');
      }

      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);

      expect(
        harness.room.clipsFetched,
        contains(
          endsWith(
            '/sessions/$sessionId/scene-rehearsals/$sessionId-ensaio-1/audio',
          ),
        ),
      );
      expect(harness.playback.played.last, contains('$sessionId-ensaio-1'));
      semantics.dispose();
    });

    testWidgets(
      'a second tap on play while its clip is fetched hears nothing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(tester, _oneEach);
        await _openThePlan(tester);
        final before = harness.playback.played.length;
        harness.room.holdNextClip();

        await tester.tap(_playOn(1));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(_playOn(1));
        await tester.pump(const Duration(milliseconds: 100));
        harness.room.finishHeldClip();
        await _theAnswerSettles(tester);

        expect(harness.playback.played.length, before);
        semantics.dispose();
      },
    );

    testWidgets('the last row whose play was tapped is the one heard', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      File(
        '${harness.recorder.home.path}/cena-$sessionId-ensaio-2.wav',
      ).writeAsBytesSync([1, 2, 3, 4]);
      harness.room.holdNextClip();

      await tester.tap(_playOn(1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_playOn(2));
      await tester.pump(const Duration(milliseconds: 100));
      harness.room.finishHeldClip();
      await _theAnswerSettles(tester);

      expect(harness.playback.played.last, contains('$sessionId-ensaio-2'));
      expect(
        harness.playback.played.where((p) => p.contains('$sessionId-ensaio-1')),
        isEmpty,
      );
      semantics.dispose();
    });

    testWidgets(
      'a clip still looked for on the tablet when the plan closes never '
      'plays',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(tester, _oneEach);
        await _openThePlan(tester);
        final sessionId = harness.room.sceneRehearsals.first.sessionId;
        File(
          '${harness.recorder.home.path}/cena-$sessionId-ensaio-1.wav',
        ).writeAsBytesSync([1, 2, 3, 4]);
        final before = harness.playback.played.length;
        harness.recorder.holdNextLookup();

        await tester.tap(_playOn(1));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.ensureVisible(find.text(_sceneByScene));
        await tester.tap(find.text(_sceneByScene));
        await tester.pump(const Duration(milliseconds: 100));
        harness.recorder.finishHeldLookup();
        await _theAnswerSettles(tester);

        expect(find.text(_homeLine), findsOneWidget);
        expect(
          harness.playback.played
              .skip(before)
              .where((p) => p.contains('$sessionId-ensaio-1')),
          isEmpty,
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'a play whose clip did not come leaves the next tap to play it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(tester, _oneEach);
        await _openThePlan(tester);
        final sessionId = harness.room.sceneRehearsals.first.sessionId;
        harness.room.sceneAudio = Uint8List(0);

        await tester.tap(_playOn(1));
        await _theAnswerSettles(tester);
        harness.room.sceneAudio = null;
        await tester.tap(_playOn(1));
        await _theAnswerSettles(tester);

        expect(harness.playback.played.last, contains('$sessionId-ensaio-1'));
        semantics.dispose();
      },
    );

    testWidgets(
      'a play whose clip the disk cannot keep hears nothing, calls nobody, and '
      'leaves the next tap to play it',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, container) = await _seeded(tester, _oneEach);
        await _openThePlan(tester);
        final sessionId = harness.room.sceneRehearsals.first.sessionId;
        final before = harness.playback.played.length;
        final persons = harness.room.personsAsked;
        harness.recorder.keepBytesFails = true;

        await tester.tap(_playOn(1));
        await _theAnswerSettles(tester);

        expect(harness.playback.played.length, before);
        expect(container.read(salaSessionProvider).needsPerson, isFalse);
        expect(harness.room.personsAsked, persons);
        expect(find.text(_planLine), findsOneWidget);
        expect(byLabel(_diskWord), findsOneWidget);

        harness.recorder.keepBytesFails = false;
        await tester.tap(_playOn(1));
        await _theAnswerSettles(tester);

        expect(byLabel(_diskWord), findsNothing);
        expect(harness.playback.played.last, contains('$sessionId-ensaio-1'));
        semantics.dispose();
      },
    );

    testWidgets('one row, another, then the first again, all slow, plays the '
        'first once', (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);
      final sessionId = harness.room.sceneRehearsals.first.sessionId;
      final before = harness.playback.played.length;
      harness.room.holdNextClip();

      for (final n in [1, 2, 1]) {
        await tester.tap(_playOn(n));
        await tester.pump(const Duration(milliseconds: 100));
      }
      harness.room.finishHeldClip();
      await _theAnswerSettles(tester);

      final heard = harness.playback.played.skip(before);
      expect(
        heard.where((p) => p.contains('$sessionId-ensaio-1')),
        hasLength(1),
      );
      expect(heard.where((p) => p.contains('$sessionId-ensaio-2')), isEmpty);
      semantics.dispose();
    });

    testWidgets(
      '«trocar» while a clip is fetched opens the sheet and plays nothing',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(
          tester,
          (s) => [
            _rehearsal(s, n: 1, scene: 'S2', sentAt: _sentAt('10:00')),
            _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:05')),
          ],
        );
        await _openThePlan(tester);
        final sessionId = harness.room.sceneRehearsals.first.sessionId;
        harness.room.holdNextClip();

        await tester.tap(_playOn(2));
        await tester.pump(const Duration(milliseconds: 100));
        await _tapSwapOn(tester, 2);
        harness.room.finishHeldClip();
        await _theAnswerSettles(tester);

        expect(
          harness.playback.played.where(
            (p) => p.contains('$sessionId-ensaio-2'),
          ),
          isEmpty,
        );
        semantics.dispose();
      },
    );
  });

  group('2. a scene with two sent rehearsals', () {
    testWidgets('defaults to the one the voice received last', (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:05')),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(2, '0:07', 2))), findsOneWidget);
      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsNothing);
    });

    testWidgets('defaults to the one received last, not the newest', (
      tester,
    ) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:05')),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:01')),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(2, '0:07', 2))), findsOneWidget);
      expect(_onRow(2, find.text(_facts(3, '0:07', 2))), findsNothing);
    });
  });

  testWidgets('3. an unsent rehearsal is never the default', (tester) async {
    await _seeded(
      tester,
      (s) => [
        _rehearsal(s, n: 1, scene: 'S1'),
        _rehearsal(s, n: 2, scene: 'S1', sentAt: null),
      ],
    );

    await _openThePlan(tester);

    expect(_onRow(1, find.text(_facts(1, '0:07', 2))), findsOneWidget);
    expect(_onRow(1, find.text(_facts(2, '0:07', 2))), findsNothing);
  });

  testWidgets('3. a sent time that does not read is never the default either', (
    tester,
  ) async {
    await _seeded(
      tester,
      (s) => [
        _rehearsal(s, n: 1, scene: 'S1'),
        _rehearsal(s, n: 2, scene: 'S1', sentAt: 'ontem'),
      ],
    );

    await _openThePlan(tester);

    expect(_onRow(1, find.text(_facts(1, '0:07', 2))), findsOneWidget);
    expect(_onRow(1, find.text(_facts(2, '0:07', 2))), findsNothing);
  });

  group('4. a scene with no rehearsal says it is missing', () {
    testWidgets('and «juntar» still opens on the other scenes', (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(tester, (s) => _oneEach(s).take(2).toList());

      await _openThePlan(tester);

      expect(_onRow(3, find.text(_missing)), findsOneWidget);
      expect(_playOn(3), findsNothing);
      expect(_onRow(3, find.text(_swap)), findsNothing);
      expect(byLabel(_join), findsOneWidget);
      expect(_enabledAt(tester, _join), Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('when its only rehearsal has no translated frase', (
      tester,
    ) async {
      await _seeded(
        tester,
        (s) => [
          ..._oneEach(s).take(2),
          _rehearsal(s, n: 3, scene: 'S3', frases: const []),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(3, find.text(_missing)), findsOneWidget);
      expect(_playOn(3), findsNothing);
      expect(_onRow(3, find.text(_swap)), findsNothing);
    });
  });

  group('5. a rehearsal with an untranslated stretch', () {
    testWidgets('says «tradução incompleta» and stays the default', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(
            s,
            n: 1,
            scene: 'S1',
            durationMs: 11000,
            frases: const [
              SceneFrase(fraseId: 'a', startsMs: 0, endsMs: 5000),
              SceneFrase(fraseId: 'b', startsMs: 5000, endsMs: 8000),
            ],
          ),
          ..._oneEach(s).skip(1),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(1, find.text(_partial)), findsOneWidget);
      expect(_onRow(1, find.text(_facts(1, '0:11', 2))), findsOneWidget);
      expect(_enabledAt(tester, _join), Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('under half a second is no stretch', (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(
            s,
            n: 1,
            scene: 'S1',
            durationMs: 11000,
            frases: const [
              SceneFrase(fraseId: 'a', startsMs: 0, endsMs: 5000),
              SceneFrase(fraseId: 'b', startsMs: 5000, endsMs: 10600),
            ],
          ),
          ..._oneEach(s).skip(1),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(1, find.text(_facts(1, '0:11', 2))), findsOneWidget);
      expect(find.text(_partial), findsNothing);
    });
  });

  testWidgets(
    '6. «trocar o ensaio desta cena» opens the sheet, and its «usar este» '
    'moves scene 2 to rehearsal 1',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: null),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:05')),
          _rehearsal(s, n: 4, scene: 'S1'),
          _rehearsal(s, n: 5, scene: 'S3'),
        ],
      );

      await _openThePlan(tester);
      expect(_onRow(2, find.text(_facts(3, '0:07', 2))), findsOneWidget);
      expect(_onRow(1, find.text(_swap)), findsNothing);
      expect(_onRow(3, find.text(_swap)), findsNothing);

      await _tapSwapOn(tester, 2);
      expect(find.text(_planLine), findsNothing);
      await _useTheRehearsal(tester, 1);

      expect(find.text(_planLine), findsOneWidget);
      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsOneWidget);
      expect(_onRow(2, find.text(_facts(3, '0:07', 2))), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    '6. a row with one joinable rehearsal beside an unsent one offers «trocar», '
    'and still holds the sent one',
    (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S2'),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: null),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsOneWidget);
      expect(
        _onRow(2, find.text(_swap)),
        findsOneWidget,
        reason: 'o ensaio não enviado ao lado do enviado não abria a troca',
      );
    },
  );

  testWidgets(
    '6. a row holding a sent rehearsal beside one that is no WAV offers '
    '«trocar», as hers',
    (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S2'),
          _rehearsal(s, n: 2, scene: 'S2', contentType: 'audio/mp4'),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsOneWidget);
      expect(
        _onRow(2, find.text(_swap)),
        findsOneWidget,
        reason: 'a troca pedia um segundo ensaio que pudesse entrar',
      );
    },
  );

  group('7. «juntar as cenas e ouvir»', () {
    testWidgets('opens once one scene holds a joinable rehearsal', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1'),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: null),
        ],
      );

      await _openThePlan(tester);

      expect(byLabel(_join), findsOneWidget);
      expect(_enabledAt(tester, _join), Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('stays closed while no scene holds a joinable rehearsal', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1', sentAt: null),
          _rehearsal(s, n: 2, scene: 'S2', contentType: 'audio/mp4'),
        ],
      );

      await _openThePlan(tester);

      expect(byLabel(_join), findsOneWidget);
      expect(_enabledAt(tester, _join), Tristate.isFalse);
      semantics.dispose();
    });
  });

  group('8. a rehearsal that cannot be joined says so, and «juntar» still '
      'opens on the other scenes', () {
    for (final (why, rehearsal) in [
      (
        'audio/mp4',
        (String s) =>
            _rehearsal(s, n: 2, scene: 'S2', contentType: 'audio/mp4'),
      ),
      (
        'not verified',
        (String s) => _rehearsal(s, n: 2, scene: 'S2', verified: false),
      ),
      (
        'unsent and audio/mp4',
        (String s) => _rehearsal(
          s,
          n: 2,
          scene: 'S2',
          sentAt: null,
          contentType: 'audio/mp4',
        ),
      ),
      (
        'unsent and not verified',
        (String s) =>
            _rehearsal(s, n: 2, scene: 'S2', sentAt: null, verified: false),
      ),
    ]) {
      testWidgets('when it is $why', (tester) async {
        final semantics = tester.ensureSemantics();
        await _seeded(
          tester,
          (s) => [
            _rehearsal(s, n: 1, scene: 'S1'),
            rehearsal(s),
            _rehearsal(s, n: 3, scene: 'S3'),
          ],
        );

        await _openThePlan(tester);

        expect(_onRow(2, find.text(_cannotEnter)), findsOneWidget);
        expect(_onRow(2, find.text(_missing)), findsNothing);
        expect(_playOn(2), findsNothing);
        expect(_enabledAt(tester, _join), Tristate.isTrue);
        semantics.dispose();
      });
    }
  });

  testWidgets(
    '8. a row whose only rehearsal cannot enter still offers «trocar», as hers',
    (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1'),
          _rehearsal(s, n: 2, scene: 'S2', contentType: 'audio/mp4'),
          _rehearsal(s, n: 3, scene: 'S3'),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_cannotEnter)), findsOneWidget);
      expect(
        _onRow(2, find.text(_swap)),
        findsOneWidget,
        reason: 'sem nada escolhido, a dela abre a troca para o que existe',
      );
    },
  );

  group('8. a scene with no sent rehearsal but an unsent one says it is '
      'missing and offers «trocar», not that it cannot enter', () {
    for (final (why, others) in [
      ('when it is the only one', (String s) => <SceneRehearsalRecord>[]),
      (
        'beside one that cannot enter',
        (String s) => [
          _rehearsal(s, n: 4, scene: 'S2', contentType: 'audio/mp4'),
        ],
      ),
    ]) {
      testWidgets(why, (tester) async {
        await _seeded(
          tester,
          (s) => [
            _rehearsal(s, n: 1, scene: 'S1'),
            _rehearsal(s, n: 2, scene: 'S2', sentAt: null),
            _rehearsal(s, n: 3, scene: 'S3'),
            ...others(s),
          ],
        );

        await _openThePlan(tester);

        expect(
          _onRow(2, find.text(_missing)),
          findsOneWidget,
          reason: 'a cena com um ensaio não enviado dizia que não podia entrar',
        );
        expect(_onRow(2, find.text(_cannotEnter)), findsNothing);
        expect(
          _onRow(2, find.text(_swap)),
          findsOneWidget,
          reason: 'o ensaio não enviado não tinha como ser escolhido',
        );
        expect(_playOn(2), findsNothing);
      });
    }
  });

  group('9. rehearsals recorded in the other language', () {
    testWidgets('open the grain choice under her line, and «Cena por cena» the '
        'recording home under it', (tester) async {
      final (_, container) = await _seeded(
        tester,
        (_) => [_rehearsal('outra-sessao', n: 1, scene: 'S1')],
      );

      await _openThePlan(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_elsewhere), findsOneWidget);
      expect(find.text(_planLine), findsNothing);
      expect(find.text(_homeLine), findsNothing);

      await tester.tap(find.text(_sceneByScenePick));
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_elsewhere), findsOneWidget);

      final notifier = container.read(salaSessionProvider.notifier);
      notifier.gravarACena(1);
      await _theAnswerSettles(tester);
      notifier.gravarACena(1);
      await _theAnswerSettles(tester);
      notifier.takeKeep();
      await _theAnswerSettles(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_elsewhere), findsNothing);
    });

    testWidgets('an unsent one there opens the all-oral plan, with no line', (
      tester,
    ) async {
      await _seeded(
        tester,
        (_) => [_rehearsal('outra-sessao', n: 1, scene: 'S1', sentAt: null)],
      );

      await _openThePlan(tester);

      expect(find.text(_planLine), findsOneWidget);
      expect(find.text(_missing), findsNWidgets(3));
      expect(find.text(_elsewhere), findsNothing);
    });
  });

  testWidgets('10. a passage worked fully by voice gets the all-oral plan', (
    tester,
  ) async {
    await _seeded(tester, (_) => const []);

    await _openThePlan(tester);

    expect(find.text(_planLine), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(_onRow(n, find.text(_missing)), findsOneWidget);
    }
    expect(byLabel(_join), findsNothing);
    expect(find.text(_join), findsNothing);
    expect(find.text(_sceneByScene), findsOneWidget);
  });

  group('11. a rehearsals read over a plan with rows', () {
    testWidgets('that runs out at 6 s opens the grain choice, with no sign', (
      tester,
    ) async {
      final (harness, _) = await _seeded(tester, _oneEach);
      harness.room.holdNextSceneList();

      await tester.tap(_dot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 5800));

      expect(find.text(_thinking), findsOneWidget);
      expect(find.text(_how), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_how), findsOneWidget);

      harness.room.finishHeldSceneList();
      await _theAnswerSettles(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_facts(1, '0:07', 2)), findsNothing);
      expect(thePersonSign, findsNothing);
    });

    testWidgets('that fails opens the grain choice, with no sign', (
      tester,
    ) async {
      final (harness, _) = await _seeded(tester, _oneEach);
      harness.room.sceneListsAnswerFirst.add(const NetworkFailed('sem rede'));

      await _openThePlan(tester);

      expect(find.text(_how), findsOneWidget);
      expect(find.text(_facts(1, '0:07', 2)), findsNothing);
      expect(thePersonSign, findsNothing);
    });
  });

  testWidgets(
    '12. another session\'s rehearsals never enter this session\'s rows',
    (tester) async {
      await _seeded(
        tester,
        (s) => [
          _rehearsal(s, n: 1, scene: 'S1', sentAt: _sentAt('10:00')),
          _rehearsal(
            'outra-sessao',
            n: 4,
            scene: 'S1',
            sentAt: _sentAt('11:00'),
          ),
        ],
      );

      await _openThePlan(tester);

      expect(_onRow(1, find.text(_facts(1, '0:07', 2))), findsOneWidget);
      expect(_onRow(1, find.text(_swap)), findsNothing);
    },
  );

  testWidgets('13. the plan shows only facts, never a word said', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _seeded(tester, _oneEach);

    await _openThePlan(tester);

    final fixed = {
      'Ensaio Final',
      'Voltar para a passagem atual',
      _planLine,
      _sceneByScene,
      'gravar a passagem inteira de uma vez',
      _missing,
      _cannotEnter,
      _partial,
      _swap,
      _join,
      'Ouvir',
      for (final scene in _threeScenes) scene.title,
      for (final n in [1, 2, 3]) ...['Cena $n', '$n'],
    };
    final facts = RegExp(
      r'^ensaio \d+ · \d{2}:\d{2} · \d+:\d{2} · \d+ frases$',
    );
    bool aFact(String said) =>
        fixed.contains(said) ||
        facts.hasMatch(said) ||
        said
            .split(' — ')
            .every((piece) => fixed.contains(piece) || facts.hasMatch(piece));

    final plan = find.byType(EnsaioFinalPlanView);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: plan, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? '');
    final labels = tester
        .widgetList<Semantics>(
          find.descendant(of: plan, matching: find.byType(Semantics)),
        )
        .map((widget) => widget.properties.label)
        .whereType<String>()
        .where((label) => label.isNotEmpty);

    expect(texts, isNotEmpty);
    for (final said in [...texts, ...labels]) {
      expect(aFact(said), isTrue, reason: '«$said» não é um fato do plano');
    }
    semantics.dispose();
  });

  group('14. a choice lasts the visit', () {
    List<SceneRehearsalRecord> twoOnSceneTwo(String s) => [
      _rehearsal(s, n: 1, scene: 'S2', sentAt: _sentAt('10:00')),
      _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:05')),
    ];

    testWidgets('and a new tap of the dot opens the plan on the default', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passages = const [_thePassage]
        ..room.nextMoment = _midConversation
        ..room.passageScenes = _threeScenes
        ..room.openedSessions.add('sessao-antiga')
        ..room.sceneRehearsals.addAll(twoOnSceneTwo('sessao-antiga'));
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);
      Future<void> backOnTheConversation() async {
        harness.emAberto.rows['Ruth/P01/pt'] = const ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.conversa,
          language: 'pt',
        );
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
      }

      await backOnTheConversation();
      await _openThePlan(tester);
      await _tapSwapOn(tester, 2);
      await _useTheRehearsal(tester, 1);
      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsOneWidget);

      await tester.ensureVisible(find.text(_sceneByScene));
      await tester.tap(find.text(_sceneByScene));
      await _theAnswerSettles(tester);
      expect(find.text(_homeLine), findsOneWidget);
      await backOnTheConversation();

      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(2, '0:07', 2))), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('and a relaunch opens the plan on the default again', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(tester, twoOnSceneTwo);
      await _openThePlan(tester);
      await _tapSwapOn(tester, 2);
      await _useTheRehearsal(tester, 1);
      expect(_onRow(2, find.text(_facts(1, '0:07', 2))), findsOneWidget);

      final next = await _relaunchOnTheConversation(tester, harness, container);
      addTearDown(() => closeTheRoom(next));

      expect(_dot, findsOneWidget);
      await _openThePlan(tester);

      expect(_onRow(2, find.text(_facts(2, '0:07', 2))), findsOneWidget);
      semantics.dispose();
    });
  });

  group('15. an English room', () {
    testWidgets('shows the plan in her English', (tester) async {
      final semantics = tester.ensureSemantics();
      await _seeded(
        tester,
        lingua: 'en',
        scenes: _threeScenesEn,
        (s) => [
          _rehearsal(
            s,
            n: 1,
            scene: 'S1',
            durationMs: 11000,
            frases: const [
              SceneFrase(fraseId: 'a', startsMs: 0, endsMs: 5000),
              SceneFrase(fraseId: 'b', startsMs: 5000, endsMs: 8000),
            ],
          ),
          _rehearsal(s, n: 2, scene: 'S2', sentAt: _sentAt('10:00')),
          _rehearsal(s, n: 3, scene: 'S2', sentAt: _sentAt('10:05')),
        ],
      );

      await _openThePlan(tester);

      final clock = _clock(_recordedAt);
      expect(_row(1, _threeScenesEn), findsOneWidget);
      expect(find.text('Scene 1'), findsOneWidget);
      expect(
        _onRow(
          1,
          find.text('rehearsal 1 · $clock · 0:11 · 2 sentences'),
          _threeScenesEn,
        ),
        findsOneWidget,
      );
      expect(_playOn(1, _threeScenesEn), findsOneWidget);
      expect(
        _onRow(1, find.text('translation incomplete'), _threeScenesEn),
        findsOneWidget,
      );
      expect(
        _onRow(
          2,
          find.text('use another rehearsal for this scene'),
          _threeScenesEn,
        ),
        findsOneWidget,
      );
      expect(
        _onRow(3, find.text('this scene has no rehearsal yet'), _threeScenesEn),
        findsOneWidget,
      );
      expect(byLabel('join the scenes and listen'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('and her English line over the home', (tester) async {
      await _seeded(
        tester,
        lingua: 'en',
        scenes: _threeScenesEn,
        (_) => [_rehearsal('outra-sessao', n: 1, scene: 'S1')],
      );

      await _openThePlan(tester);

      expect(find.text(_elsewhereEn), findsOneWidget);
    });
  });

  group('the play of the row that plays shows her pause', () {
    testWidgets('and a second tap stops it and gives the play back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);

      expect(_glyphOn(tester, _playOn(1)), ListenGlyph.play);

      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);

      expect(harness.playback.sounding, isTrue);
      expect(
        _glyphOn(tester, _playOn(1)),
        ListenGlyph.pause,
        reason: 'o ensaio tocava e o botão ainda mostrava tocar',
      );
      expect(_pressedAt(tester, _playOn(1)), Tristate.isTrue);

      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);

      expect(harness.playback.sounding, isFalse);
      expect(_glyphOn(tester, _playOn(1)), ListenGlyph.play);
      expect(_pressedAt(tester, _playOn(1)), Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('and a clip that ends by itself gives the play back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);
      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);
      expect(_glyphOn(tester, _playOn(1)), ListenGlyph.pause);

      harness.playback.finishPlayback();
      await _theAnswerSettles(tester);

      expect(
        _glyphOn(tester, _playOn(1)),
        ListenGlyph.play,
        reason: 'o ensaio acabou e o botão ficou em pausa sobre o silêncio',
      );
      expect(_pressedAt(tester, _playOn(1)), Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets(
      'from the tap, while its clip still comes down from the room, as hers',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, _) = await _seeded(tester, _oneEach);
        await _openThePlan(tester);
        harness.room.holdNextClip();

        await tester.tap(_playOn(1));
        await tester.pump(const Duration(milliseconds: 300));

        expect(harness.playback.sounding, isFalse);
        expect(
          _glyphOn(tester, _playOn(1)),
          ListenGlyph.pause,
          reason: 'o dela marca tocando no toque, antes do áudio carregar',
        );
        expect(_pressedAt(tester, _playOn(1)), Tristate.isTrue);

        harness.room.finishHeldClip();
        await _theAnswerSettles(tester);

        expect(harness.playback.sounding, isTrue);
        expect(_glyphOn(tester, _playOn(1)), ListenGlyph.pause);
        expect(_pressedAt(tester, _playOn(1)), Tristate.isTrue);
        semantics.dispose();
      },
    );

    testWidgets('and only that row, so a tap on another moves it there', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);

      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);
      await tester.tap(_playOn(2));
      await _theAnswerSettles(tester);

      expect(harness.playback.sounding, isTrue);
      expect(_glyphOn(tester, _playOn(2)), ListenGlyph.pause);
      expect(_pressedAt(tester, _playOn(2)), Tristate.isTrue);
      for (final n in [1, 3]) {
        expect(
          _glyphOn(tester, _playOn(n)),
          ListenGlyph.play,
          reason: 'a linha $n mostrava pausa sem tocar',
        );
        expect(_pressedAt(tester, _playOn(n)), Tristate.isFalse);
      }
      semantics.dispose();
    });
  });

  testWidgets(
    'a halt over a row that plays leaves it on the play when the team comes '
    'back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);
      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);
      expect(_glyphOn(tester, _playOn(1)), ListenGlyph.pause);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.haltForABrokenBuild();
      await _theAnswerSettles(tester);
      expect(thePersonSign, findsOneWidget);
      expect(harness.playback.sounding, isFalse);
      notifier.teamTapped();
      await _theAnswerSettles(tester);

      expect(thePersonSign, findsNothing);
      expect(
        _glyphOn(tester, _playOn(1)),
        ListenGlyph.play,
        reason: 'a parada calou o ensaio e a linha voltou em pausa',
      );
      expect(_pressedAt(tester, _playOn(1)), Tristate.isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'a rehearsal whose clip opens only after the ceiling ended it stays '
    'silent, not sounding under the play',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(
        tester,
        _oneEach,
        playbackCeiling: const Duration(seconds: 2),
      );
      await _openThePlan(tester);
      harness.playback.holdNextOpening();
      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);
      expect(_pressedAt(tester, _playOn(1)), Tristate.isTrue);

      await tester.pump(const Duration(seconds: 2));
      harness.playback.finishHeldOpening();
      await _theAnswerSettles(tester);

      expect(_pressedAt(tester, _playOn(1)), Tristate.isFalse);
      expect(
        harness.playback.sounding,
        isFalse,
        reason:
            'o teto terminava a parte sem parar o som, e o clipe que abria '
            'depois tocava inteiro com o botão já de volta em tocar',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a row that plays when the app goes away falls silent and gives its play '
    'back, not sounding behind the tablet',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, _) = await _seeded(tester, _oneEach);
      await _openThePlan(tester);
      await tester.tap(_playOn(1));
      await _theAnswerSettles(tester);
      expect(harness.playback.sounding, isTrue);

      for (final away in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(away);
      }
      await _theAnswerSettles(tester);

      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'o app saía e o ensaio do plano seguia tocando atrás dele',
      );

      for (final back in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(back);
      }
      await _theAnswerSettles(tester);

      expect(harness.playback.sounding, isFalse);
      expect(
        _pressedAt(tester, _playOn(1)),
        Tristate.isFalse,
        reason: 'e a linha voltava ainda em pausa sobre o silêncio',
      );
      semantics.dispose();
    },
  );

  testWidgets('a row of the plan offers its rehearsal as her filled triangle, '
      'not a lucide outline', (tester) async {
    await _seeded(tester, _oneEach);
    await _openThePlan(tester);

    expect(
      find.descendant(of: _playOn(1), matching: find.byType(Icon)),
      findsNothing,
      reason: 'a linha do plano desenhava o play vazado do Lucide',
    );
    expect(
      _paintedOn(_playOn(1)),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [Offset(10, 12), Offset(9, 7), Offset(9, 17)],
        excludes: const [Offset(7, 12), Offset(16, 8), Offset(16, 16)],
      ),
      reason:
          'o play dela é «M8 6l10 6-10 6z» cheio na caixa de 24 '
          '(EnsaioFinalPlan.tsx:24)',
    );
  });

  testWidgets('the row that plays shows her two filled bars, not a lucide '
      'outline', (tester) async {
    await _seeded(tester, _oneEach);
    await _openThePlan(tester);
    await tester.tap(_playOn(1));
    await _theAnswerSettles(tester);

    expect(
      _paintedOn(_playOn(1)),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [
          Offset(8, 12),
          Offset(16, 12),
          Offset(7, 6),
          Offset(17, 18),
        ],
        excludes: const [
          Offset(12, 12),
          Offset(8, 4),
          Offset(16, 20),
          Offset(6.1, 5.1),
          Offset(17.9, 18.9),
        ],
      ),
      reason:
          'a pausa dela são duas barras cheias, 6–10 e 14–18 por 5–19 com '
          'rx 1, na caixa de 24 (EnsaioFinalPlan.tsx:25)',
    );
  });
}
