import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

const _session = 'sessao-1';
const _articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);
const _listen =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para '
    'ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de '
    'vocês.';
const _sentRow =
    'ouvir o ensaio da cena 1 — cena 2, 14:05, 3 · frases traduzidas, enviado';
const _rowOnScreen =
    'Ensaio da cena 2, 14:10, 0 · frases traduzidas, não enviado';

final _redMicrophone = byLabel('ensaio da cena');
final _terminei = byLabel('terminei');

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
  String? scene,
  DateTime? recordedAt,
  String? sentAt,
  String? afterRestart,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: sessionId == _session
      ? 'ensaio-da-cena-$n'
      : '$sessionId-ensaio-da-cena-$n',
  sessionId: sessionId,
  n: n,
  scene: scene,
  recordedAt: recordedAt,
  sentAt: sentAt,
  afterRestart: afterRestart,
  frases: frases,
);

final _sentOne = _rehearsal(
  scene: 'S2',
  recordedAt: DateTime(2026, 10, 15, 14, 5),
  sentAt: '2026-10-15T14:20:00+00:00',
  frases: [
    _frase('f3', 9000, 15000),
    _frase('f0', 0, 3500, replacedBy: 'f1'),
    _frase('f2', 4000, 9000),
    _frase('f1', 0, 4000),
  ],
);
final _unsentTwo = _rehearsal(n: 2, recordedAt: DateTime(2026, 10, 15, 14, 10));
final _ofAnotherSession = _rehearsal(
  sessionId: 'sessao-2',
  recordedAt: DateTime(2026, 10, 15, 13, 0),
);

String _fraseAudioOf(String rehearsalId, String fraseId) =>
    '/api/internalization-room/sessions/$_session/scene-rehearsals/'
    '$rehearsalId/frases/$fraseId/audio';

void _seed(SalaHarness harness, List<SceneRehearsalRecord> rehearsals) {
  harness.room
    ..sceneRehearsals.addAll(rehearsals)
    ..sceneAudio = Uint8List.fromList([1, 2, 3]);
  harness.playback.measured = const Duration(seconds: 20);
}

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
  SalaHarness? given,
}) async {
  final harness = given ?? SalaHarness()
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = _articulation;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _theScreenShows(
  WidgetTester tester,
  List<SceneRehearsalRecord> rehearsals, {
  required bool Function(SalaSessionState state) when,
}) async {
  final harness = SalaHarness();
  _seed(harness, rehearsals);
  final (_, container) = await _inArticulation(tester, given: harness);
  await tester.tap(_redMicrophone);
  await _pumpUntil(tester, () => when(container.read(salaSessionProvider)));
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

bool? _enabled(WidgetTester tester, Finder control) =>
    tester.widget<Semantics>(control).properties.enabled;

final class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;
}

Future<_Room> _atRest(
  List<SceneRehearsalRecord> rehearsals, [
  SalaHarness? given,
]) async {
  final harness = given ?? SalaHarness();
  harness.room.nextMoment = _articulation;
  _seed(harness, rehearsals);
  final container = harness.container();
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await room.sala.goConversa();
  await waitFor(
    'a sala abrir a conversa e se calar',
    () =>
        room.state.sessionId != null &&
        room.state.stage == SalaStage.conversa &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  return room;
}

Future<void> _theScreenOpens(
  _Room room, {
  required bool Function(SceneScreen scene) on,
}) async {
  room.sala.openTheSceneRehearsal();
  await waitFor(
    'a tela do ensaio da cena abrir',
    () => room.state.stage == SalaStage.cena && on(room.state.scene),
  );
  await settle();
}

bool _onTheRecordStep(SceneScreen scene) => scene.step == SceneStep.record;

bool Function(SceneScreen) _showing(int n, SceneStep step) =>
    (scene) => scene.rehearsal?.n == n && scene.step == step && !scene.waiting;

Future<_Room> _inListenModeOf(
  SceneRehearsalRecord sent,
  SceneRehearsalRecord unsent,
) async {
  final room = await _atRest([sent, unsent]);
  await _theScreenOpens(room, on: _showing(unsent.n, SceneStep.translate));
  await _theRowOpens(room, sent.n, SceneStep.sent);
  return room;
}

Future<void> _theRowOpens(_Room room, int n, SceneStep step) async {
  room.sala.openTheListedSceneRehearsal('ensaio-da-cena-$n');
  await waitFor(
    'o ensaio da cena $n abrir',
    () => _showing(n, step)(room.state.scene),
  );
}

Future<void> _recordAndStop(_Room room) async {
  room.sala.sceneTap();
  await waitFor(
    'o microfone da cena abrir',
    () => switch (room.state.channel) {
      Microphone(owner: MicOwner.scene) => true,
      _ => false,
    },
  );
  room.sala.sceneTap();
}

List<(int, bool, int)> _rows(_Room room) => [
  for (final row in room.state.sceneRehearsals)
    (row.n, row.unsent, row.translatedFrases),
];

void main() {
  testWidgets(
    'the scene rehearsal\'s screen lists this session\'s rehearsals, each with '
    'its number, scene, time, frases and sent state',
    (tester) async {
      await _theScreenShows(tester, [
        _unsentTwo,
        _ofAnotherSession,
        _sentOne,
      ], when: (state) => state.scene.rehearsal?.n == 2);

      final list = byLabel('ensaios da cena desta sessão');
      expect(list, findsOneWidget);
      final rows = find.descendant(
        of: list,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.button == true,
        ),
      );
      expect(
        [
          for (final row in tester.widgetList<Semantics>(rows))
            row.properties.label,
        ],
        [_sentRow, _rowOnScreen],
      );
    },
  );

  test('the rows read in the order of their numbers', () async {
    final room = await _atRest([
      _rehearsal(n: 2, sentAt: '2026-10-15T14:20:00+00:00'),
      _rehearsal(n: 3),
      _rehearsal(sentAt: '2026-10-15T14:00:00+00:00'),
    ]);
    await _theScreenOpens(room, on: _showing(3, SceneStep.translate));

    expect(_rows(room).map((row) => row.$1), [1, 2, 3]);
  });

  testWidgets('the row on screen cannot be tapped', (tester) async {
    final (harness, container) = await _theScreenShows(tester, [
      _sentOne,
      _unsentTwo,
    ], when: (state) => state.scene.rehearsal?.n == 2);
    final measured = harness.playback.measurements.length;
    final step = container.read(salaSessionProvider).scene.step;
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.playTheSceneRehearsal();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_enabled(tester, byLabel(_rowOnScreen)), isFalse);
    notifier.openTheListedSceneRehearsal('ensaio-da-cena-2');
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).channel, isA<PartPlaying>());
    expect(container.read(salaSessionProvider).scene.step, step);
    expect(container.read(salaSessionProvider).scene.rehearsal?.n, 2);
    expect(harness.playback.measurements, hasLength(measured));
  });

  test('an unsent row resumes at the frase where the team stopped', () async {
    final room = await _atRest([
      _rehearsal(frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 9000)]),
      _rehearsal(n: 2),
    ]);
    await _theScreenOpens(room, on: _showing(2, SceneStep.translate));

    await _theRowOpens(room, 1, SceneStep.translate);
    await settle();
    expect(room.harness.playback.played, isEmpty);

    room.sala.playTheSceneRehearsal();
    await waitFor(
      'o ensaio da cena tocar',
      () => room.harness.playback.played.isNotEmpty,
    );
    expect(
      room.harness.playback.playedFrom.last,
      const Duration(milliseconds: 9000),
    );
  });

  test(
    'a row whose take cannot be fetched leaves the screen as it was',
    () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      room.harness.room.failClipWith = const Refused('UNREADABLE');

      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await waitFor(
        'o take do ensaio 1 ser pedido',
        () => room.harness.room.clipsFetched.any(
          (url) => url.contains('/ensaio-da-cena-1/audio'),
        ),
      );
      await settle();

      expect(_showing(2, SceneStep.translate)(room.state.scene), isTrue);
    },
  );

  test(
    'a rehearsal whose reopen could not fetch its take opens from its row',
    () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      room.harness.room.failClipWith = const Refused('UNREADABLE');
      room.sala.openTheSceneRehearsal();
      await waitFor(
        'o take do ensaio 2 ser pedido',
        () => room.harness.room.clipsFetched.isNotEmpty,
      );
      await settle();
      room.harness.room.failClipWith = null;

      await _theRowOpens(room, 2, SceneStep.translate);
    },
  );

  testWidgets(
    'a sent row opens listen mode with her line, the strip, play, a bar and a '
    'speaker per frase, and no circle, recomeçar or terminei',
    (tester) async {
      final (_, container) = await _theScreenShows(tester, [
        _sentOne,
        _unsentTwo,
      ], when: (state) => state.scene.rehearsal?.n == 2);

      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 1500));

      expect(byLabel(_listen), findsOneWidget);
      expect(byLabel('Tocar ou pausar a gravação'), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(byLabel('frase $n'), findsOneWidget);
        expect(byLabel('ouvir a minha tradução da frase $n'), findsOneWidget);
      }
      expect(byLabel('frase 4'), findsNothing);
      expect(byLabel('ouvir a minha tradução da frase 4'), findsNothing);
      expect(byLabel('gravar o ensaio da cena de novo'), findsOneWidget);
      expect(byLabel('Gravar o ensaio da cena'), findsNothing);
      expect(byLabel('recomeçar a tradução'), findsNothing);
      expect(_terminei, findsNothing);
      expect(byLabel('traduzir o ensaio da cena'), findsNothing);
    },
  );

  test(
    'a frase bar in listen mode replays that frase\'s stretch of the recording',
    () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      await _theRowOpens(room, 1, SceneStep.sent);

      room.sala.playTheFrase('f2');
      await waitFor(
        'a frase tocar',
        () => room.harness.playback.ranges.isNotEmpty,
      );

      expect(room.harness.playback.ranges.last, '4000-9000');
      expect(room.harness.playback.played.last, room.state.scene.take);
    },
  );

  group('a speaker in listen mode plays that frase\'s translation from the '
      'frase audio door', () {
    Future<_Room> inListenMode() async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      await _theRowOpens(room, 1, SceneStep.sent);
      return room;
    }

    int fetchesOfF2(_Room room) => room.harness.room.clipsFetched
        .where((url) => url == _fraseAudioOf('ensaio-da-cena-1', 'f2'))
        .length;

    test('the frase\'s own audio plays, not the take', () async {
      final room = await inListenMode();

      room.sala.hearTheFraseTranslation('f2');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.isNotEmpty,
      );

      expect(fetchesOfF2(room), 1);
      expect(room.harness.playback.played.last, isNot(room.state.scene.take));
    });

    test('a second tap downloads nothing more', () async {
      final room = await inListenMode();
      room.sala.hearTheFraseTranslation('f2');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.isNotEmpty,
      );

      room.sala.hearTheFraseTranslation('f2');
      await waitFor(
        'a tradução da frase tocar de novo',
        () => room.harness.playback.played.length >= 2,
      );

      expect(fetchesOfF2(room), 1);
    });

    test('a double tap before the download lands fetches once', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..hearTheFraseTranslation('f2');
      await settle();
      room.harness.room.finishHeldClip();
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.isNotEmpty,
      );
      await settle();

      expect(fetchesOfF2(room), 1);
    });
  });

  test(
    'the play control in listen mode plays the recording from its start',
    () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      await _theRowOpens(room, 1, SceneStep.sent);

      room.sala.playTheSceneRehearsal();
      await waitFor('o ensaio tocar', () => room.state.channel is PartPlaying);
      expect(room.harness.playback.playedFrom.last, Duration.zero);

      room.sala.playTheSceneRehearsal();
      await waitFor('o ensaio calar', () => room.state.channel is! PartPlaying);
    },
  );

  group('a scene rehearsed again keeps the sent one and records the next '
      'number', () {
    test('from the red microphone after a sent rehearsal', () async {
      final room = await _atRest([_sentOne]);
      await _theScreenOpens(room, on: _onTheRecordStep);
      await waitFor('a lista chegar', () => _rows(room).isNotEmpty);
      expect(_rows(room), [(1, false, 3)]);

      await _recordAndStop(room);
      await waitFor(
        'o ensaio 2 ser guardado',
        () => room.state.scene.rehearsal?.n == 2,
      );

      expect(_rows(room), [(1, false, 3), (2, true, 0)]);
    });

    test('from listen mode', () async {
      final room = await _atRest([_sentOne]);
      await _theScreenOpens(room, on: _onTheRecordStep);
      await waitFor('a lista chegar', () => _rows(room).isNotEmpty);
      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await waitFor(
        'o ensaio 1 abrir para ouvir',
        () => _showing(1, SceneStep.sent)(room.state.scene),
      );

      room.sala.recordTheSceneAgain();
      await _recordAndStop(room);
      await waitFor(
        'o ensaio 2 ser guardado',
        () => room.state.scene.rehearsal?.n == 2 && !room.state.scene.waiting,
      );

      expect(_rows(room), [(1, false, 3), (2, true, 0)]);
    });
  });

  testWidgets(
    'the bars and speakers in listen mode follow the frases\' order in the take',
    (tester) async {
      final (harness, container) = await _theScreenShows(tester, [
        _sentOne,
      ], when: (state) => state.sceneRehearsals.isNotEmpty);
      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(byLabel('frase 2'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(harness.playback.ranges.last, '4000-9000');

      await tester.tap(byLabel('ouvir a minha tradução da frase 3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        harness.room.clipsFetched.last,
        _fraseAudioOf('ensaio-da-cena-1', 'f3'),
      );
    },
  );

  test('a row reads the time the take was recorded on this tablet\'s clock', () {
    final recorded = DateTime.utc(2026, 10, 15, 17, 5);
    final here = recorded.toLocal();
    final hhmm =
        '${'${here.hour}'.padLeft(2, '0')}:${'${here.minute}'.padLeft(2, '0')}';

    expect(
      sceneRehearsalRowLabelFor(
        _rehearsal(n: 2, recordedAt: recorded),
        'pt',
        onScreen: true,
      ),
      'Ensaio da cena 2, $hhmm, 0 · frases traduzidas, não enviado',
    );
  });

  group('nothing plays while the screen waits', () {
    Future<_Room> inListenMode() async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      await _theRowOpens(room, 1, SceneStep.sent);
      return room;
    }

    test('on a speaker\'s download, neither play nor a bar sounds', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..playTheSceneRehearsal()
        ..playTheFrase('f1');
      await settle();
      expect(room.harness.playback.played, isEmpty);
      room.harness.room.finishHeldClip();
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.isNotEmpty,
      );
      await settle();

      expect(room.harness.playback.played, hasLength(1));
      expect(room.harness.playback.ranges, isEmpty);
    });

    test('on a row opening, no bar sounds', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..openTheListedSceneRehearsal('ensaio-da-cena-2')
        ..playTheFrase('f1');
      await settle();

      expect(room.harness.playback.ranges, isEmpty);
      room.harness.room.finishHeldClip();
      await settle();
    });

    testWidgets('play and the bars are drawn dimmed', (tester) async {
      final (harness, container) = await _theScreenShows(tester, [
        _sentOne,
      ], when: (state) => state.sceneRehearsals.isNotEmpty);
      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 500));
      harness.room.holdNextClip();

      await tester.tap(byLabel('ouvir a minha tradução da frase 2'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_enabled(tester, byLabel('Tocar ou pausar a gravação')), isFalse);
      expect(_enabled(tester, byLabel('frase 1')), isFalse);
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('a late answer never moves the scene screen', () {
    test(
      'the row being reopened is fetched once, however soon it is tapped',
      () async {
        final room = await _atRest([_sentOne, _unsentTwo]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await waitFor('a lista chegar', () => _rows(room).length == 2);

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-2');
        await settle();
        room.harness.room.finishHeldClip();
        await waitFor(
          'o ensaio 2 abrir',
          () => _showing(2, SceneStep.translate)(room.state.scene),
        );
        await settle();

        expect(
          room.harness.room.clipsFetched.where(
            (url) => url.endsWith('/ensaio-da-cena-2/audio'),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'a speaker download that lands after «gravar de novo» plays nothing',
      () async {
        final room = await _inListenModeOf(_sentOne, _unsentTwo);
        room.harness.room.holdNextClip();

        room.sala.hearTheFraseTranslation('f2');
        await settle();
        room.sala.recordTheSceneAgain();
        await settle();
        room.harness.room.finishHeldClip();
        await settle(const Duration(milliseconds: 400));

        expect(room.harness.playback.played, isEmpty);
        expect(room.state.scene.step, SceneStep.record);
      },
    );

    test(
      'the reopen\'s take download that lands after a row was opened',
      () async {
        final room = await _atRest([_sentOne, _unsentTwo]);
        room.harness.room.holdNextClip();
        room.sala.openTheSceneRehearsal();
        await waitFor('a lista chegar', () => _rows(room).length == 2);

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        final shown = <bool>[];
        room.container.listen(
          salaSessionProvider,
          (_, next) => shown.add(_showing(2, SceneStep.translate)(next.scene)),
        );
        await settle();
        room.harness.room.finishHeldClip();
        await waitFor(
          'o ensaio 1 abrir para ouvir',
          () => _showing(1, SceneStep.sent)(room.state.scene),
        );
        await settle(const Duration(milliseconds: 400));

        expect(shown, isNot(contains(true)));
        expect(_showing(1, SceneStep.sent)(room.state.scene), isTrue);
      },
    );

    test(
      'a speaker download that lands after the way back plays nothing',
      () async {
        final room = await _atRest([_sentOne, _unsentTwo]);
        await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
        await _theRowOpens(room, 1, SceneStep.sent);
        room.harness.room.holdNextClip();
        final played = room.harness.playback.played.length;

        room.sala.hearTheFraseTranslation('f2');
        await settle();
        room.sala.leaveTheSceneRehearsal();
        await settle();
        room.harness.room.finishHeldClip();
        await settle(const Duration(milliseconds: 400));

        expect(room.harness.playback.played, hasLength(played));
        expect(room.state.scene.rehearsal, isNull);
      },
    );
  });

  group('no row opens while the scene microphone is open or a call is in the '
      'air', () {
    testWidgets('the record circle open', (tester) async {
      final (harness, container) = await _theScreenShows(tester, [
        _sentOne,
      ], when: (state) => state.sceneRehearsals.isNotEmpty);
      final notifier = container.read(salaSessionProvider.notifier);
      final fetched = harness.room.clipsFetched.length;
      notifier.sceneTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is Microphone,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(_enabled(tester, byLabel(_sentRow)), isFalse);
      notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(salaSessionProvider).scene.step, SceneStep.record);
      expect(container.read(salaSessionProvider).channel, isA<Microphone>());
      expect(harness.room.clipsFetched, hasLength(fetched));
      notifier.leaveTheSceneRehearsal();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('recomeçar in the air', (tester) async {
      final (harness, container) = await _theScreenShows(tester, [
        _sentOne,
        _rehearsal(n: 2, frases: [_frase('f1', 0, 24000)]),
      ], when: (state) => state.scene.step == SceneStep.placesUnknown);
      harness.room.holdNextRestart();
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.restartTheSceneTranslation();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_enabled(tester, byLabel(_sentRow)), isFalse);
      notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(salaSessionProvider).scene.rehearsal?.n, 2);

      harness.room.finishHeldRestart();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('every way out clears the scene rehearsal\'s list', () {
    void expectCleared(_Room room) {
      expect(room.state.sceneRehearsals, isEmpty);
      expect(room.state.scene.step, SceneStep.record);
    }

    test('after the way back', () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      room.sala.leaveTheSceneRehearsal();
      await waitFor(
        'a conversa voltar',
        () => room.state.stage == SalaStage.conversa,
      );

      expectCleared(room);
    });

    test(
      'after a gone session met at the list a refused speaker reads',
      () async {
        final room = await _atRest([_sentOne, _unsentTwo]);
        await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
        await _theRowOpens(room, 1, SceneStep.sent);
        room.harness.room.forgetTheSession(_session);

        room.sala.hearTheFraseTranslation('f2');
        await waitFor(
          'a escolha abrir',
          () => room.state.stage == SalaStage.escolha,
        );

        expectCleared(room);
      },
    );
  });
}
