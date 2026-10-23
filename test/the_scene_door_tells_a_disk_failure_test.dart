import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart' show articulation;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';
const _diskWord = 'não deu para guardar o ensaio da cena neste computador';
const _listen =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para '
    'ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de '
    'vocês.';
const _sentRow =
    'ouvir o ensaio da cena 1 — cena 2, 14:05, 3 · frases traduzidas, enviado';

final _redMicrophone = byLabel('ensaio da cena');
final _circleAtRest = byLabel('Gravar o ensaio da cena');
final _circleRecording = byLabel(
  'gravem o ensaio da cena na língua materna; toquem para parar',
);
final _theDiskWord = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.contains(_diskWord) ?? false),
);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? scene,
  DateTime? recordedAt,
  String? sentAt,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  scene: scene,
  recordedAt: recordedAt,
  sentAt: sentAt,
  frases: frases,
);

final _sentOne = _rehearsal(
  scene: 'S2',
  recordedAt: DateTime(2026, 10, 15, 14, 5),
  sentAt: '2026-10-15T14:20:00+00:00',
  frases: const [
    SceneFrase(fraseId: 'f3', startsMs: 9000, endsMs: 15000),
    SceneFrase(fraseId: 'f0', startsMs: 0, endsMs: 3500, replacedBy: 'f1'),
    SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 9000),
    SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
  ],
);
final _unsentTwo = _rehearsal(n: 2, recordedAt: DateTime(2026, 10, 15, 14, 10));

String _takeOf(int n) => '/ensaio-da-cena-$n/audio';

const _fraseThree =
    '/api/internalization-room/sessions/$_session/scene-rehearsals/'
    'ensaio-da-cena-1/frases/f3/audio';

bool Function(SalaSessionState) _showing(int n, SceneStep step) =>
    (state) =>
        state.scene.rehearsal?.n == n &&
        state.scene.step == step &&
        !state.scene.waiting;

/// What the room had said and asked before the disk failed.
final class _Before {
  final int lines;
  final int persons;

  _Before(SalaHarness harness)
    : lines =
          harness.voice.assets.length +
          harness.voice.played.length +
          harness.voice.fixedLines.length,
      persons = harness.room.personsAsked;
}

void _expectNoLineNoPerson(
  SalaHarness harness,
  ProviderContainer container,
  _Before before,
) {
  expect(_Before(harness).lines, before.lines, reason: 'nenhuma fala');
  expect(container.read(salaSessionProvider).needsPerson, isFalse);
  expect(
    harness.room.personsAsked,
    before.persons,
    reason: 'nenhuma pessoa chamada',
  );
  expect(container.read(salaSessionProvider).stage, SalaStage.cena);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _fetched(SalaHarness harness, String url) =>
    harness.room.clipsFetched.any((asked) => asked.contains(url));

/// The scene screen over a session at rest in Articulação, open once [when] holds, its
/// room listing [rehearsals].
Future<(SalaHarness, ProviderContainer)> _theScreenShows(
  WidgetTester tester,
  List<SceneRehearsalRecord> rehearsals, {
  required bool Function(SalaSessionState state) when,
  SalaHarness? given,
  void Function(SalaHarness harness)? beforeTheTap,
}) async {
  final harness = (given ?? SalaHarness(filaEmMemoria: true))
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room
    ..sceneRehearsals.addAll(rehearsals)
    ..sceneAudio = Uint8List.fromList([1, 2, 3]);
  harness.playback.measured = const Duration(seconds: 20);
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  beforeTheTap?.call(harness);
  await tester.tap(_redMicrophone);
  await _pumpUntil(tester, () => when(container.read(salaSessionProvider)));
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer, _Before)> _aRowUnderADiskFailure(
  WidgetTester tester,
) async {
  final (harness, container) = await _theScreenShows(tester, [
    _sentOne,
    _unsentTwo,
  ], when: _showing(2, SceneStep.translate));
  final before = _Before(harness);
  harness.recorder.keepBytesFails = true;

  await tester.tap(byLabel(_sentRow));
  await _pumpUntil(tester, () => _fetched(harness, _takeOf(1)));
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container, before);
}

Future<(SalaHarness, ProviderContainer, _Before)> _aReopenUnderADiskFailure(
  WidgetTester tester,
) async {
  final (harness, container) = await _theScreenShows(
    tester,
    [_unsentTwo],
    when: (state) => state.sceneRehearsals.isNotEmpty,
    beforeTheTap: (harness) => harness.recorder.keepBytesFails = true,
  );
  final before = _Before(harness);
  await _pumpUntil(tester, () => _fetched(harness, _takeOf(2)));
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container, before);
}

final _fraseThreeControl = byLabel('ouvir a minha tradução da frase 3');

Future<(SalaHarness, ProviderContainer, _Before)> _aFraseUnderADiskFailure(
  WidgetTester tester,
) async {
  final (harness, container) = await _theScreenShows(tester, [
    _sentOne,
  ], when: (state) => state.sceneRehearsals.isNotEmpty);
  await tester.tap(byLabel(_sentRow));
  await _pumpUntil(
    tester,
    () => _showing(1, SceneStep.sent)(container.read(salaSessionProvider)),
  );
  await tester.pump(const Duration(milliseconds: 500));
  final before = _Before(harness);
  harness.recorder.keepBytesFails = true;

  await tester.tap(_fraseThreeControl);
  await _pumpUntil(tester, () => _fetched(harness, _fraseThree));
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container, before);
}

void main() {
  testWidgets(
    'a disk failure under a listed row\'s take shows the disk word, speaks no line and '
    'calls nobody',
    (tester) async {
      final (harness, container, before) = await _aRowUnderADiskFailure(tester);

      expect(
        _showing(2, SceneStep.translate)(container.read(salaSessionProvider)),
        isTrue,
      );
      expect(_theDiskWord, findsOneWidget);
      _expectNoLineNoPerson(harness, container, before);
    },
  );

  testWidgets(
    'a reopened scene rehearsal whose take the disk cannot keep shows the disk word '
    'on the record step',
    (tester) async {
      final (harness, container, before) = await _aReopenUnderADiskFailure(
        tester,
      );

      expect(
        find.ancestor(of: _circleAtRest, matching: _theDiskWord),
        findsOneWidget,
      );
      expect(container.read(salaSessionProvider).scene.waiting, isFalse);
      _expectNoLineNoPerson(harness, container, before);
    },
  );

  testWidgets(
    'a disk failure under a frase\'s clip shows the word where her line stands',
    (tester) async {
      final (harness, container, before) = await _aFraseUnderADiskFailure(
        tester,
      );

      expect(byLabel('$_listen — $_diskWord'), findsOneWidget);
      _expectNoLineNoPerson(harness, container, before);
    },
  );

  group('the disk word goes', () {
    testWidgets('when the team taps the row again and its take lands', (
      tester,
    ) async {
      final (harness, container, _) = await _aRowUnderADiskFailure(tester);
      expect(_theDiskWord, findsOneWidget);
      final fetches = harness.room.clipsFetched.length;
      harness.recorder.keepBytesFails = false;

      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => _showing(1, SceneStep.sent)(container.read(salaSessionProvider)),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(harness.room.clipsFetched.length, greaterThan(fetches));
      expect(_theDiskWord, findsNothing);
    });

    testWidgets('when the team records a new take and the room keeps it', (
      tester,
    ) async {
      final (harness, container, _) = await _aReopenUnderADiskFailure(tester);
      expect(_theDiskWord, findsOneWidget);
      harness.recorder.keepBytesFails = false;

      await tester.tap(_circleAtRest);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_circleRecording);
      await _pumpUntil(
        tester,
        () =>
            container.read(salaSessionProvider).scene.step ==
            SceneStep.translate,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(salaSessionProvider).scene.step,
        SceneStep.translate,
      );
      expect(_theDiskWord, findsNothing);
    });

    testWidgets('at the team\'s next gesture on the translate step', (
      tester,
    ) async {
      await _aRowUnderADiskFailure(tester);
      expect(_theDiskWord, findsOneWidget);

      await tester.tap(byLabel('traduzir o ensaio da cena'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(_theDiskWord, findsNothing);
    });

    testWidgets('when the team plays a frase again once the disk keeps it', (
      tester,
    ) async {
      final (harness, _, _) = await _aFraseUnderADiskFailure(tester);
      expect(byLabel('$_listen — $_diskWord'), findsOneWidget);
      final fetches = harness.room.clipsFetched.length;
      harness.recorder.keepBytesFails = false;

      await tester.tap(_fraseThreeControl);
      await _pumpUntil(
        tester,
        () => harness.room.clipsFetched.length > fetches,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(_theDiskWord, findsNothing);
    });
  });

  testWidgets(
    'a take too short to keep after a failed reopen does not bring the disk word back',
    (tester) async {
      final (harness, container, _) = await _aReopenUnderADiskFailure(tester);
      expect(_theDiskWord, findsOneWidget);
      harness.recorder.rehearsalSpeaks = Uint8List(799);

      await tester.tap(_circleAtRest);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_circleRecording);
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! Microphone,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).scene.step, SceneStep.record);
      expect(_theDiskWord, findsNothing);
    },
  );

  testWidgets(
    'a disk failure under a reopen the team left lands on no other rehearsal',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      File(
        '${harness.recorder.home.path}/cena-ensaio-da-cena-1.wav',
      ).writeAsBytesSync([1, 2, 3]);
      final (_, container) = await _theScreenShows(
        tester,
        [_sentOne, _unsentTwo],
        when: (state) =>
            _fetched(harness, _takeOf(2)) && state.scenes is! ScenesAwaited,
        given: harness,
        beforeTheTap: (harness) {
          harness.room.holdNextClip();
          harness.recorder.keepBytesFails = true;
        },
      );

      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => _showing(1, SceneStep.sent)(container.read(salaSessionProvider)),
      );
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        _showing(1, SceneStep.sent)(container.read(salaSessionProvider)),
        isTrue,
      );
      expect(_theDiskWord, findsNothing);
    },
  );

  testWidgets('a new take being kept after a Disk failure is not told as one', (
    tester,
  ) async {
    final (harness, container, _) = await _aReopenUnderADiskFailure(tester);
    expect(_theDiskWord, findsOneWidget);
    harness.recorder.keepBytesFails = false;

    await tester.tap(_circleAtRest);
    await tester.pump(const Duration(milliseconds: 500));
    harness.room.holdNextKeep();
    addTearDown(harness.room.finishHeldKeep);
    await tester.tap(_circleRecording);
    await _pumpUntil(tester, () => harness.room.scenesKept.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).scene.keep, isA<Keeping>());
    expect(_theDiskWord, findsNothing);
  });

  testWidgets('the scene screen tells no network failure', (tester) async {
    final (harness, container) = await _theScreenShows(tester, [
      _sentOne,
      _unsentTwo,
    ], when: _showing(2, SceneStep.translate));
    harness.room.failClipWith = const NetworkFailed('sem rede');

    await tester.tap(byLabel(_sentRow));
    await _pumpUntil(tester, () => _fetched(harness, _takeOf(1)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      _showing(2, SceneStep.translate)(container.read(salaSessionProvider)),
      isTrue,
    );
    expect(_theDiskWord, findsNothing);
  });

  testWidgets('two fetches of one take at once play the take and say nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final (_, container) = await _theScreenShows(
      tester,
      [_unsentTwo],
      when: (state) {
        if (!_fetched(harness, _takeOf(2))) return false;
        return state.scenes is! ScenesAwaited;
      },
      given: harness,
      beforeTheTap: (harness) => harness.room.holdNextClip(),
    );
    final before = _Before(harness);

    container
        .read(salaSessionProvider.notifier)
        .openTheListedSceneRehearsal('ensaio-da-cena-2');
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.finishHeldClip();
    await _pumpUntil(
      tester,
      () =>
          _showing(2, SceneStep.translate)(container.read(salaSessionProvider)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      _showing(2, SceneStep.translate)(container.read(salaSessionProvider)),
      isTrue,
    );
    expect(_theDiskWord, findsNothing);
    _expectNoLineNoPerson(harness, container, before);
  });
}
