import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_translate_step.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle, thePersonSign;

const _session = 'sessao-1';
const _articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);
final _v4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const _listen =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para '
    'ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de '
    'vocês.';
const _sending = 'enviando a tradução do ensaio da cena para a voz…';
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
final _unsentTwoWithAFrase = _rehearsal(
  n: 2,
  recordedAt: DateTime(2026, 10, 15, 14, 10),
  frases: [_frase('f1', 0, 4000)],
);
final _ofAnotherSession = _rehearsal(
  sessionId: 'sessao-2',
  recordedAt: DateTime(2026, 10, 15, 13, 0),
);

SceneRehearsalRecord _unsentWithFrases({String? afterRestart}) => _rehearsal(
  recordedAt: DateTime(2026, 10, 15, 14, 5),
  afterRestart: afterRestart,
  frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 9000)],
);

SceneRehearsalRecord _asTheRoomHoldsIt(
  SceneRehearsalRecord rehearsal, {
  String? sentAt,
  String? afterRestart,
}) => SceneRehearsalRecord(
  rehearsalId: rehearsal.rehearsalId,
  sessionId: rehearsal.sessionId,
  n: rehearsal.n,
  scene: rehearsal.scene,
  recordedAt: rehearsal.recordedAt,
  sentAt: sentAt ?? rehearsal.sentAt,
  afterRestart: afterRestart ?? rehearsal.afterRestart,
  frases: rehearsal.frases,
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
  final harness = given ?? SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = _articulation;
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
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _theScreenShows(
  WidgetTester tester,
  List<SceneRehearsalRecord> rehearsals, {
  required bool Function(SalaSessionState state) when,
}) async {
  final harness = SalaHarness(filaEmMemoria: true);
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

  int _repliesAtRest = 0;

  int get _replies =>
      harness.voice.played.where((url) => url == turnoUrl).length;

  void restsNow() => _repliesAtRest = _replies;

  bool get repliedOnTheCanvas =>
      _replies > _repliesAtRest && sala.state.stage == SalaStage.conversa;
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
  await room.sala.goConversa(book: 'Ruth');
  await waitFor(
    'a sala abrir a conversa e se calar',
    () =>
        room.state.sessionId != null &&
        room.state.stage == SalaStage.conversa &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  room.restsNow();
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

Future<void> _theRoomRests(_Room room) => waitFor(
  'a sala descansar',
  () => !room.state.awaitingTheGuide && room.state.machine.inFlight == null,
);

void _expectNoHaltAndNoPerson(_Room room) {
  expect(room.state.halt, isA<NoHalt>());
  expect(room.state.needsPerson, isFalse);
  expect(room.asked('askForAPerson'), 0);
}

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
    'a row that fails to open while the reopen is in the air leaves the reopened row to tap',
    () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      room.harness.room.holdNextClip();
      room.sala.openTheSceneRehearsal();
      await waitFor('a lista chegar', () => _rows(room).length == 2);

      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await settle();
      room.harness.room
        ..failClipWith = const Refused('UNREADABLE')
        ..finishHeldClip();
      await settle(const Duration(milliseconds: 400));
      room.harness.room.failClipWith = null;

      await _theRowOpens(room, 2, SceneStep.translate);
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

    test('a double tap before the download lands plays the translation once, '
        'not twice', () async {
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

      expect(
        room.harness.playback.played,
        hasLength(1),
        reason: 'as duas descidas tocavam, uma atropelando a outra',
      );
    });

    test('another frase\'s speaker during a download plays that frase\'s '
        'translation, never the first one', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..hearTheFraseTranslation('f1');
      await settle();
      room.harness.room.finishHeldClip();
      await waitFor(
        'uma tradução tocar',
        () => room.harness.playback.played.isNotEmpty,
      );
      await settle();

      expect(
        room.harness.playback.played.map((path) => path.split('/').last),
        ['cena-ensaio-da-cena-1-frase-f1.m4a'],
        reason: 'o segundo alto-falante ficava apagado e tocava a frase 2',
      );
    });

    test('a row tapped during a download opens, and the translation that '
        'lands after it never sounds', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..openTheListedSceneRehearsal('ensaio-da-cena-2');
      await settle();
      room.harness.room.finishHeldClip();
      await waitFor(
        'o ensaio da cena 2 abrir',
        () => _showing(2, SceneStep.translate)(room.state.scene),
      );
      await settle();

      expect(
        room.harness.playback.played,
        isEmpty,
        reason: 'a tradução do ensaio de antes tocava no ensaio aberto',
      );
    });

    test('a translation the room cannot hand over says nothing and leaves '
        'the team listening, never on the choice', () async {
      final room = await inListenMode();
      room.harness.room.failClipWith = const SessionGone();

      room.sala.hearTheFraseTranslation('f2');
      await settle();
      await settle();

      expect(
        room.state.stage,
        SalaStage.cena,
        reason: 'uma tradução que não descia encerrava a sessão',
      );
      expect(room.state.sessionId, _session);
      expect(room.state.scene.step, SceneStep.sent);
      expect(room.state.sceneLine, isNull);
      expect(room.state.machine.aHaltWaitsForTheCanvas, isNull);
      _expectNoHaltAndNoPerson(room);
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

  test('play in listen mode after a pause resumes where the take stopped, not '
      'from its start', () async {
    final room = await _inListenModeOf(_sentOne, _unsentTwo);
    room.sala.playTheSceneRehearsal();
    await waitFor(
      'o ensaio abrir',
      () => switch (room.state.channel) {
        PartPlaying(opened: true) => true,
        _ => false,
      },
    );
    room.harness.playback.at = const Duration(seconds: 5);
    room.sala.playTheSceneRehearsal();
    await waitFor('o ensaio calar', () => room.state.channel is! PartPlaying);

    room.sala.playTheSceneRehearsal();
    await waitFor('o ensaio tocar', () => room.state.channel is PartPlaying);

    expect(
      room.harness.playback.playedFrom.last,
      const Duration(seconds: 5),
      reason: 'o play depois da pausa recomeçava o ensaio do zero',
    );
  });

  test('play in listen mode after the take was heard to its end starts it '
      'again from its start, not from its end', () async {
    final room = await _inListenModeOf(_sentOne, _unsentTwo);
    room.sala.playTheSceneRehearsal();
    await waitFor(
      'o ensaio abrir',
      () => switch (room.state.channel) {
        PartPlaying(opened: true) => true,
        _ => false,
      },
    );
    room.harness.playback.at = const Duration(seconds: 15);
    room.harness.playback.finishPlayback();
    await waitFor(
      'o ensaio acabar',
      () => room.state.scene.heard == SceneHeard.toTheEnd,
    );

    room.sala.playTheSceneRehearsal();
    await waitFor('o ensaio tocar', () => room.state.channel is PartPlaying);

    expect(
      room.harness.playback.playedFrom.last,
      Duration.zero,
      reason: 'o play depois do fim tocava do fim e calava na hora',
    );
  });

  test('«gravar de novo» in listen mode while another row opens leaves the '
      'row to open, not a record step', () async {
    final room = await _inListenModeOf(_sentOne, _unsentTwo);
    room.harness.playback.holdNextMeasurement();
    room.sala.openTheListedSceneRehearsal('ensaio-da-cena-2');
    await waitFor('a linha começar a abrir', () => room.state.scene.waiting);

    room.sala.recordTheSceneAgain();
    await settle();
    room.harness.playback.finishHeldMeasurement();
    await waitFor('a tela parar de esperar', () => !room.state.scene.waiting);

    expect(
      _showing(2, SceneStep.translate)(room.state.scene),
      isTrue,
      reason: 'o gravar de novo passava e a linha tocada nunca abria',
    );
  });

  testWidgets('«gravar de novo» in listen mode is drawn off while another row '
      'opens, not lit', (tester) async {
    final (harness, container) = await _theScreenShows(tester, [
      _sentOne,
      _unsentTwo,
    ], when: (state) => state.scene.rehearsal?.n == 2);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
    await _pumpUntil(
      tester,
      () => _showing(1, SceneStep.sent)(
        container.read(salaSessionProvider).scene,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.holdNextMeasurement();

    notifier.openTheListedSceneRehearsal('ensaio-da-cena-2');
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).scene.waiting,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _enabled(tester, byLabel('gravar o ensaio da cena de novo')),
      isFalse,
      reason: 'o gravar de novo ficava aceso enquanto a linha abria',
    );
    harness.playback.finishHeldMeasurement();
    await _pumpUntil(
      tester,
      () => !container.read(salaSessionProvider).scene.waiting,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('«gravar de novo» in listen mode is drawn off while a frase '
      'microphone is open, not lit', (tester) async {
    final container = SalaHarness().container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SceneListenMode(
                scene: SceneScreen(
                  step: SceneStep.sent,
                  rehearsal: _sentOne,
                  take: 'cena-ensaio-da-cena-1.m4a',
                  length: const Duration(seconds: 15),
                ),
                envelope: null,
                channel: const Microphone(MicOwner.frase),
                language: 'pt',
                sending: false,
                line: null,
                stoppedAt: null,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      _enabled(tester, byLabel('gravar o ensaio da cena de novo')),
      isFalse,
      reason: 'o gravar de novo ficava aceso com o microfone da frase aberto',
    );
  });

  test('play in listen mode while the team\'s translation sounds plays the '
      'take, not only a silence', () async {
    final room = await _inListenModeOf(_sentOne, _unsentTwo);
    final take = room.state.scene.take;
    room.sala.hearTheFraseTranslation('f2');
    await waitFor(
      'a tradução da frase tocar',
      () => room.harness.playback.played.isNotEmpty,
    );

    room.sala.playTheSceneRehearsal();
    await settle();

    expect(
      room.harness.playback.played.last,
      take,
      reason: 'o play só calava a tradução e o ensaio não tocava',
    );
    expect(
      room.state.channel,
      isA<PartPlaying>().having((playing) => playing.part.path, 'path', take),
    );
  });

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

  group('terminei is live only with a translated frase, nothing being saved, '
      'and the rehearsal unsent', () {
    testWidgets('translate with no frase: dimmed', (tester) async {
      await _theScreenShows(tester, [
        _unsentTwo,
      ], when: (state) => state.scene.step == SceneStep.translate);

      expect(_enabled(tester, _terminei), isFalse);
    });

    testWidgets('translate with one frase: live', (tester) async {
      await _theScreenShows(tester, [
        _rehearsal(frases: [_frase('f1', 0, 4000)]),
      ], when: (state) => state.scene.step == SceneStep.translate);

      expect(_enabled(tester, _terminei), isTrue);
    });

    testWidgets('places unknown with one frase: live', (tester) async {
      await _theScreenShows(tester, [
        _rehearsal(frases: [_frase('f1', 0, 24000)]),
      ], when: (state) => state.scene.step == SceneStep.placesUnknown);

      expect(_enabled(tester, _terminei), isTrue);
    });

    testWidgets('places unknown while recomeçar is in the air: dimmed', (
      tester,
    ) async {
      final (harness, _) = await _theScreenShows(tester, [
        _rehearsal(frases: [_frase('f1', 0, 24000)]),
      ], when: (state) => state.scene.step == SceneStep.placesUnknown);
      harness.room.holdNextRestart();

      await tester.tap(byLabel('recomeçar a tradução'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(
        byLabel('toque de novo para apagar as 1 frases traduzidas'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(_enabled(tester, _terminei), isFalse);
      harness.room.finishHeldRestart();
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('listen mode: no terminei', (tester) async {
      final (_, container) = await _theScreenShows(tester, [
        _sentOne,
      ], when: (state) => state.sceneRehearsals.isNotEmpty);
      await tester.tap(byLabel(_sentRow));
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 1500));

      expect(byLabel(_listen), findsOneWidget);
      expect(_terminei, findsNothing);
    });
  });

  group('terminei sends the rehearsal by reference with a v4 turn id it minted '
      'and the attempt it closes', () {
    test('closing the attempt its frases follow', () async {
      final room = await _atRest([_unsentWithFrases(afterRestart: 'a1')]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      await _theRoomRests(room);

      final sent = room.harness.room.scenesSent.single;
      expect(sent.rehearsalId, 'ensaio-da-cena-1');
      expect(sent.turnId, matches(_v4));
      expect(sent.closes, 'a1');
      expect(room.harness.room.turnsSent, 0);
      expect(room.harness.room.recordingsSent, isEmpty);
    });

    test('closing nothing before any restart', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );

      expect(room.harness.room.scenesSent.single.closes, isNull);
    });
  });

  testWidgets(
    'terminei keeps the screen open and waits while the send is in the air',
    (tester) async {
      final (harness, container) = await _theScreenShows(tester, [
        _sentOne,
        _unsentTwoWithAFrase,
      ], when: (state) => state.scene.step == SceneStep.translate);
      harness.room.holdNextTurn();

      await tester.tap(_terminei);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).stage, SalaStage.cena);
      expect(
        _enabled(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == _sending &&
                widget.properties.button == true,
          ),
        ),
        isFalse,
      );
      expect(_terminei, findsNothing);
      expect(
        _enabled(
          tester,
          byLabel(
            'Ensaio da cena 2, 14:10, 1 · frases traduzidas, não enviado',
          ),
        ),
        isFalse,
      );
      expect(_enabled(tester, byLabel(_sentRow)), isFalse);
      expect(
        _enabled(tester, byLabel('gravar o ensaio da cena de novo')),
        isFalse,
      );

      harness.room.finishHeldTurn();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  test('terminei closes the screen on the answer and the reply plays on the '
      'session canvas as any reply', () async {
    final room = await _atRest([_unsentWithFrases()]);
    await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
    room.harness.room.holdNextTurn();
    final saidBefore = room.harness.voice.fixedLines.length;

    room.sala.sendTheSceneRehearsal();
    await waitFor('o ensaio ir', () => room.harness.room.scenesSent.isNotEmpty);
    await settle();

    expect(room.state.stage, SalaStage.cena);
    expect(room.state.awaitingTheGuide, isTrue);
    expect(
      room.harness.voice.fixedLines.skip(saidBefore).map((line) => line.$1),
      contains(isIn(instantAckLines)),
    );

    room.harness.room.finishHeldTurn();
    await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);
    expect(room.state.stage, SalaStage.conversa);
    await waitFor(
      'a voz voltar a convidar',
      () => room.state.voice == VoiceState.invite,
    );
  });

  group('the reply of terminei plays beneath the send-off line', () {
    Future<_Room> sentWithTheReplyHeld() async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.holdNextTurn();
      room.harness.room.fixedLine = 'A1';
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      await settle();
      room.harness.voice.holdNextLine();
      room.harness.room.finishHeldTurn();
      return room;
    }

    int timesSaid(_Room room) =>
        room.harness.voice.fixedLines.where((said) => said.$1 == 'A1').length;

    test(
      'it starts at once, while the line still shows on the screen',
      () async {
        final room = await sentWithTheReplyHeld();

        await waitFor('a linha A tocar', () => timesSaid(room) == 1);

        expect(room.state.scene.wentToTheVoice, isTrue);
        expect(room.state.stage, SalaStage.cena);
        room.harness.voice.finishHeldLine();
      },
    );

    test('the screen closing onto the conversation does not cut it', () async {
      final room = await sentWithTheReplyHeld();
      await waitFor('a linha A tocar', () => timesSaid(room) == 1);
      final stopsBefore = room.harness.voice.stops;

      await waitFor(
        'a tela fechar',
        () => room.state.stage == SalaStage.conversa,
      );
      room.harness.voice.finishHeldLine();
      await waitFor(
        'a voz voltar a convidar',
        () => room.state.voice == VoiceState.invite,
      );

      expect(timesSaid(room), 1);
      expect(room.harness.voice.stops, stopsBefore);
      expect(room.state.needsPerson, isFalse);
      expect(room.state.awaitingTheGuide, isFalse);
    });
  });

  test('a terminei the room answered with an A line is the line «Ouvir de '
      'novo» says again on the canvas', () async {
    final room = await _atRest([_unsentWithFrases()]);
    int timesSaid() =>
        room.harness.voice.fixedLines.where((said) => said.$1 == 'A1').length;
    await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
    room.harness.room.fixedLine = 'A1';

    room.sala.sendTheSceneRehearsal();
    await waitFor(
      'a linha A tocar na conversa',
      () =>
          timesSaid() == 1 &&
          room.state.stage == SalaStage.conversa &&
          room.state.voice == VoiceState.invite &&
          !room.state.awaitingTheGuide,
    );
    await settle();
    final playedBefore = room.harness.voice.played.length;

    await room.sala.hearAgain();
    await settle();

    expect(
      timesSaid(),
      2,
      reason:
          'o «Ouvir de novo» depois do terminei devolvia a fala de antes, não '
          'a linha A que a sala disse',
    );
    expect(room.harness.voice.played.skip(playedBefore), isEmpty);
  });

  group('the way back while terminei is in the air', () {
    Future<_Room> leftWhileItSends() async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.holdNextTurn();
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      room.sala.leaveTheSceneRehearsal();
      await settle();
      return room;
    }

    test('returns to the conversation, where the reply plays and «Ouvir de '
        'novo» says it again', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..fixedLine = 'A1'
        ..holdNextTurn();
      room.harness.voice.holdNextLine();
      int timesSaid() =>
          room.harness.voice.fixedLines.where((said) => said.$1 == 'A1').length;
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      final stopsBefore = room.harness.voice.stops;

      room.sala.leaveTheSceneRehearsal();
      await settle();

      expect(room.state.stage, SalaStage.conversa);
      expect(room.state.voice, VoiceState.thinking);
      expect(room.harness.voice.stops, stopsBefore);
      room.harness.voice.finishHeldLine();
      room.harness.room.finishHeldTurn();
      await settle(const Duration(milliseconds: 700));
      expect(timesSaid(), 1, reason: 'a resposta esperou o 1,4 s da tela');
      await waitFor(
        'a voz voltar a convidar',
        () => room.state.voice == VoiceState.invite,
      );
      await settle();
      await room.sala.hearAgain();
      await settle();
      expect(timesSaid(), 2);
      expect(room.harness.room.scenesSent, hasLength(1));
    });

    test(
      'a refusal rests the conversation at the invite and says nothing',
      () async {
        final room = await leftWhileItSends();
        final saidBefore =
            room.harness.voice.fixedLines.length +
            room.harness.voice.assets.length +
            room.harness.voice.played.length;
        room.harness.room.failHeldTurnWith = Refused(RefusalCode.unnamed(422));

        room.harness.room.finishHeldTurn();
        await _theRoomRests(room);
        await settle(const Duration(milliseconds: 400));

        expect(room.state.stage, SalaStage.conversa);
        expect(room.state.voice, VoiceState.invite);
        _expectNoHaltAndNoPerson(room);
        expect(room.repliedOnTheCanvas, isFalse);
        expect(
          room.harness.voice.fixedLines.length +
              room.harness.voice.assets.length +
              room.harness.voice.played.length,
          saidBefore,
        );
      },
    );

    test('an answer with nothing to play calls a person on the conversation, '
        'as hers', () async {
      final room = await leftWhileItSends();
      room.harness.room.answersTurnsWithoutAReply = true;

      room.harness.room.finishHeldTurn();
      await waitFor('o sinal da pessoa', () => room.state.needsPerson);

      expect(room.state.stage, SalaStage.conversa);
      expect(room.state.halt, isA<Blocking>());
      expect(room.state.voice, VoiceState.invite);
      expect(room.repliedOnTheCanvas, isFalse);
    });

    test('a tap during the send-off line leaves the reply to play', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.fixedLine = 'A1';
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'a linha de despedida',
        () => room.state.scene.wentToTheVoice,
      );

      room.sala.leaveTheSceneRehearsal();
      await waitFor(
        'a linha A tocar',
        () =>
            room.harness.voice.fixedLines
                    .where((said) => said.$1 == 'A1')
                    .length ==
                1 &&
            room.state.voice == VoiceState.invite,
      );
    });

    test('the screen does not open again until the send lands, and then reads '
        'it enviado with no terminei', () async {
      final room = await leftWhileItSends();
      final listed = room.asked('sceneRehearsalsOf');

      room.sala.openTheSceneRehearsal();
      await settle();
      expect(room.state.stage, SalaStage.conversa);
      expect(room.asked('sceneRehearsalsOf'), listed);

      room.harness.room.finishHeldTurn();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);
      await waitFor(
        'a voz voltar a convidar',
        () => room.state.voice == VoiceState.invite,
      );
      await _theScreenOpens(room, on: _onTheRecordStep);
      await waitFor('a lista chegar', () => _rows(room).isNotEmpty);

      expect(_rows(room), [(1, false, 2)]);
      expect(room.harness.room.scenesSent, hasLength(1));
    });

    test(
      'a send refused after the way back goes again under its turn id',
      () async {
        final room = await leftWhileItSends();
        room.harness.room.failHeldTurnWith = Refused(RefusalCode.unnamed(422));
        room.harness.room.finishHeldTurn();
        await _theRoomRests(room);
        await settle();
        await _theScreenOpens(room, on: _showing(1, SceneStep.translate));

        room.sala.sendTheSceneRehearsal();
        await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

        expect(room.harness.room.scenesSent, hasLength(2));
        expect(
          room.harness.room.scenesSent.map((send) => send.turnId).toSet(),
          hasLength(1),
        );
      },
    );
  });

  test(
    'the rehearsal terminei sent is listed enviado when the screen opens again',
    () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.sala.sendTheSceneRehearsal();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);
      await waitFor(
        'a voz voltar a convidar',
        () => room.state.voice == VoiceState.invite,
      );

      await _theScreenOpens(room, on: _onTheRecordStep);
      await waitFor('a lista chegar', () => _rows(room).isNotEmpty);

      expect(_rows(room), [(1, false, 2)]);
    },
  );

  test('a double tap on terminei sends once', () async {
    final room = await _atRest([_unsentWithFrases()]);
    await _theScreenOpens(room, on: _showing(1, SceneStep.translate));

    room.sala
      ..sendTheSceneRehearsal()
      ..sendTheSceneRehearsal();
    await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

    expect(room.harness.room.scenesSent, hasLength(1));
  });

  group('a send that meets another tablet\'s send in flight is sent again '
      'under the same turn id', () {
    test('until the room answers', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.sendRefusalsFirst.addAll([
        RefusalCode.sceneRehearsalSending,
        RefusalCode.sceneRehearsalSending,
      ]);

      room.sala.sendTheSceneRehearsal();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

      final sent = room.harness.room.scenesSent;
      expect(sent, hasLength(3));
      expect(sent.map((send) => send.turnId).toSet(), hasLength(1));
    });

    test('three times at most, and then the room rests', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.sendRefusalsFirst.addAll([
        RefusalCode.sceneRehearsalSending,
        RefusalCode.sceneRehearsalSending,
        RefusalCode.sceneRehearsalSending,
      ]);

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o terceiro envio',
        () => room.harness.room.scenesSent.length == 3,
      );
      await _theRoomRests(room);
      await settle();

      expect(room.harness.room.scenesSent, hasLength(3));
      _expectNoHaltAndNoPerson(room);
      expect(room.repliedOnTheCanvas, isFalse);
      expect(room.state.stage, SalaStage.cena);
    });
  });

  group('a refused send keeps the screen and reads the list again once', () {
    test(
      'another tablet\'s send that landed meanwhile reads enviado',
      () async {
        final room = await _atRest([
          _unsentWithFrases(),
        ], SalaHarness(retryBackoff: const [Duration(milliseconds: 400)]));
        await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
        room.harness.room.sendRefusalsFirst.addAll([
          RefusalCode.sceneRehearsalSending,
          RefusalCode.sceneRehearsalSending,
          RefusalCode.sceneRehearsalSending,
        ]);
        final listedBefore = room.asked('sceneRehearsalsOf');

        room.sala.sendTheSceneRehearsal();
        await waitFor(
          'o segundo envio',
          () => room.harness.room.scenesSent.length == 2,
        );
        room.harness.room.sceneRehearsals
          ..[0] = _asTheRoomHoldsIt(
            _unsentWithFrases(),
            sentAt: '2026-10-15T15:00:00+00:00',
          )
          ..add(_rehearsal(n: 2));
        await waitFor(
          'o ensaio ser mostrado enviado',
          () => room.state.scene.step == SceneStep.sent,
        );
        await settle();

        expect(room.asked('sceneRehearsalsOf') - listedBefore, 1);
        expect(_rows(room), [(1, false, 2), (2, true, 0)]);
        expect(room.state.stage, SalaStage.cena);
      },
    );
  });

  test(
    'a send refused as already sent leaves the room at rest as sent',
    () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneRehearsals[0] = _asTheRoomHoldsIt(
          _unsentWithFrases(),
          sentAt: '2026-10-15T15:00:00+00:00',
        );
      final listedBefore = room.asked('sceneRehearsalsOf');

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ser mostrado enviado',
        () => room.state.scene.step == SceneStep.sent,
      );
      await settle(const Duration(milliseconds: 400));

      expect(room.harness.room.scenesSent, hasLength(1));
      expect(room.state.stage, SalaStage.cena);
      expect(room.state.awaitingTheGuide, isFalse);
      _expectNoHaltAndNoPerson(room);
      expect(room.repliedOnTheCanvas, isFalse);
      expect(room.asked('sceneRehearsalsOf') - listedBefore, 1);
    },
  );

  group('a send whose attempt moved on reads the list and is sent again '
      'closing the room\'s attempt', () {
    test('still unsent: sent again, and the reply plays', () async {
      final room = await _atRest([_unsentWithFrases(afterRestart: 'a1')]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.restartOutOfOrder)
        ..sceneRehearsals[0] = _asTheRoomHoldsIt(
          _unsentWithFrases(),
          afterRestart: 'a2',
        );

      room.sala.sendTheSceneRehearsal();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

      final sent = room.harness.room.scenesSent;
      expect(sent.map((send) => send.closes), ['a1', 'a2']);
      expect(sent.map((send) => send.turnId).toSet(), hasLength(1));
    });

    test('already sent: sent once, and the room rests', () async {
      final room = await _atRest([_unsentWithFrases(afterRestart: 'a1')]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.restartOutOfOrder)
        ..sceneRehearsals[0] = _asTheRoomHoldsIt(
          _unsentWithFrases(),
          afterRestart: 'a2',
          sentAt: '2026-10-15T15:00:00+00:00',
        );
      final listedBefore = room.asked('sceneRehearsalsOf');

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ser mostrado enviado',
        () => room.state.scene.step == SceneStep.sent,
      );
      await _theRoomRests(room);
      await settle(const Duration(milliseconds: 400));

      expect(room.harness.room.scenesSent, hasLength(1));
      expect(room.state.stage, SalaStage.cena);
      expect(
        room.asked('sceneRehearsalsOf') - listedBefore,
        2,
        reason: 'uma leitura para reenviar, uma porque o envio foi recusado',
      );
      _expectNoHaltAndNoPerson(room);
      expect(room.repliedOnTheCanvas, isFalse);
    });
  });

  test(
    'a send whose attempt moved on and whose list cannot be read is never looked for',
    () async {
      final room = await _atRest([_unsentWithFrases(afterRestart: 'a1')]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.restartOutOfOrder)
        ..failSceneWith = const NetworkFailed('a rede caiu');

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      await _theRoomRests(room);
      await settle(const Duration(milliseconds: 400));

      expect(room.harness.room.turnIdsLookedAt, isEmpty);
      expect(room.state.needsPerson, isFalse);
      expect(room.harness.room.scenesSent, hasLength(1));
    },
  );

  group('a send that fails at its door follows the house policy', () {
    test('a lost answer is found by the one look and plays', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..turnsLandBeforeTheyFail = true
        ..failHeldTurnWith = const NetworkFailed('a rede caiu');

      room.sala.sendTheSceneRehearsal();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

      expect(
        room.harness.room.turnIdsLookedAt,
        contains(room.harness.room.scenesSent.single.turnId),
      );
      expect(room.state.stage, SalaStage.conversa);
    });

    for (final (what, code) in [
      ('a 422', RefusalCode.unnamed(422)),
      ('a 404', RefusalCode.notFound),
    ]) {
      test('$what leaves the room at rest with no person', () async {
        final room = await _atRest([_unsentWithFrases()]);
        await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
        room.harness.room.sendRefusalsFirst.add(code);
        final listedBefore = room.asked('sceneRehearsalsOf');

        room.sala.sendTheSceneRehearsal();
        await waitFor(
          'o ensaio ir',
          () => room.harness.room.scenesSent.isNotEmpty,
        );
        await _theRoomRests(room);
        await settle(const Duration(milliseconds: 400));

        _expectNoHaltAndNoPerson(room);
        expect(room.repliedOnTheCanvas, isFalse);
        expect(room.state.stage, SalaStage.cena);
        expect(room.asked('sceneRehearsalsOf') - listedBefore, 1);
      });
    }

    test(
      'a TURN_COLLISION leaves the circle at rest, the rehearsal unsent, and '
      '«terminei» sends it again',
      () async {
        final room = await _atRest([_unsentWithFrases()]);
        await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
        room.harness.room.sendRefusalsFirst.add('TURN_COLLISION');

        room.sala.sendTheSceneRehearsal();
        await waitFor(
          'o ensaio ir',
          () => room.harness.room.scenesSent.isNotEmpty,
        );
        await _theRoomRests(room);
        await settle(const Duration(milliseconds: 400));

        _expectNoHaltAndNoPerson(room);
        expect(room.repliedOnTheCanvas, isFalse);
        expect(room.state.stage, SalaStage.cena);
        expect(room.state.scene.step, SceneStep.translate);
        expect(_rows(room), [(1, true, 2)]);

        room.sala.sendTheSceneRehearsal();
        await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

        expect(room.harness.room.scenesSent, hasLength(2));
        expect(room.state.stage, SalaStage.conversa);
      },
    );
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

    test('play during a speaker\'s download plays the take, and the '
        'translation that lands after it never sounds', () async {
      final room = await inListenMode();
      final take = room.state.scene.take;
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..playTheSceneRehearsal();
      await settle();
      expect(
        room.harness.playback.played,
        [take],
        reason: 'o play ficava apagado enquanto a tradução descia',
      );
      room.harness.room.finishHeldClip();
      await settle();

      expect(
        room.harness.playback.played,
        [take],
        reason: 'a tradução que chegava tarde tocava por cima do ensaio',
      );
    });

    test('a bar during a speaker\'s download plays its stretch, and the '
        'translation that lands after it never sounds', () async {
      final room = await inListenMode();
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..playTheFrase('f1');
      await settle();
      expect(
        room.harness.playback.ranges,
        ['0-4000'],
        reason: 'a barra ficava apagada enquanto a tradução descia',
      );
      room.harness.room.finishHeldClip();
      await settle();

      expect(
        room.harness.playback.played,
        hasLength(1),
        reason: 'a tradução que chegava tarde tocava por cima da frase',
      );
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

    testWidgets('on a speaker\'s download, play and the bars stay lit, not '
        'dimmed', (tester) async {
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

      expect(
        _enabled(tester, byLabel('Tocar ou pausar a gravação')),
        isTrue,
        reason: 'o play se apagava enquanto a tradução descia',
      );
      expect(
        _enabled(tester, byLabel('frase 1')),
        isTrue,
        reason: 'as barras se apagavam enquanto a tradução descia',
      );
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('nothing else moves while the send is in the air', () {
    Future<_Room> sending(
      List<SceneRehearsalRecord> rehearsals,
      SceneStep step,
    ) async {
      final room = await _atRest(
        rehearsals,
        SalaHarness(restartWake: Duration.zero),
      );
      await _theScreenOpens(room, on: _showing(2, step));
      room.harness.room.holdNextTurn();
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      return room;
    }

    Future<void> theReplyComes(_Room room) async {
      room.harness.room.finishHeldTurn();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);
    }

    test('a row', () async {
      final room = await sending([
        _sentOne,
        _unsentTwoWithAFrase,
      ], SceneStep.translate);
      final fetched = room.harness.room.clipsFetched.length;

      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await settle();

      expect(room.harness.room.clipsFetched, hasLength(fetched));
      expect(room.state.scene.rehearsal?.n, 2);
      await theReplyComes(room);
    });

    test('play', () async {
      final room = await sending([
        _sentOne,
        _unsentTwoWithAFrase,
      ], SceneStep.translate);

      room.sala.playTheSceneRehearsal();
      await settle();

      expect(room.harness.playback.played, isEmpty);
      await theReplyComes(room);
    });

    test('«gravar o ensaio da cena de novo»', () async {
      final room = await sending([
        _sentOne,
        _unsentTwoWithAFrase,
      ], SceneStep.translate);

      room.sala.recordTheSceneAgain();
      await settle();

      expect(room.state.scene.step, SceneStep.translate);
      await theReplyComes(room);
    });

    test('«recomeçar a tradução»', () async {
      final room = await sending([
        _sentOne,
        _rehearsal(n: 2, frases: [_frase('f1', 0, 24000)]),
      ], SceneStep.placesUnknown);

      room.sala.restartTheSceneTranslation();
      await settle();
      room.sala.restartTheSceneTranslation();
      await settle();

      expect(room.harness.room.restartsSent, isEmpty);
      await theReplyComes(room);
    });
  });

  test(
    'a send that meets another tablet\'s send waits on the ladder before it is sent again',
    () async {
      final room = await _atRest([
        _unsentWithFrases(),
      ], SalaHarness(retryBackoff: const [Duration(milliseconds: 600)]));
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room.sendRefusalsFirst.add(
        RefusalCode.sceneRehearsalSending,
      );

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );
      await settle(const Duration(milliseconds: 250));

      expect(room.harness.room.scenesSent, hasLength(1));
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);
    },
  );

  group('a halt on the scene screen waits for the conversation, as hers', () {
    test('terminei still sends under it', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.sala.haltForABrokenBuild();
      expect(room.state.needsPerson, isFalse);

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'o ensaio ir',
        () => room.harness.room.scenesSent.isNotEmpty,
      );

      expect(
        room.harness.room.scenesSent,
        hasLength(1),
        reason: 'a parada travava o terminei da cena, e o dela segue mandando',
      );
    });

    testWidgets('no sign is drawn over it and terminei stays lit', (
      tester,
    ) async {
      final (harness, container) = await _theScreenShows(tester, [
        _unsentWithFrases(),
      ], when: (state) => state.scene.step == SceneStep.translate);
      container.read(salaSessionProvider.notifier).haltForABrokenBuild();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        thePersonSign,
        findsNothing,
        reason: 'o sinal cobria a cena, e o dela só fica sobre a conversa',
      );
      expect(_enabled(tester, _terminei), isTrue);
    });
  });

  group(
    'an unanswered «terminei» is sent again under the turn id it was given',
    () {
      Future<_Room> refusedOnce(
        List<SceneRehearsalRecord> rehearsals,
        int n,
      ) async {
        final room = await _atRest(rehearsals);
        await _theScreenOpens(room, on: _showing(n, SceneStep.translate));
        room.harness.room.sendRefusalsFirst.add(RefusalCode.unnamed(422));
        room.sala.sendTheSceneRehearsal();
        await waitFor(
          'o ensaio ir',
          () => room.harness.room.scenesSent.isNotEmpty,
        );
        await _theRoomRests(room);
        await settle();
        return room;
      }

      Set<String> turnIds(_Room room) =>
          room.harness.room.scenesSent.map((send) => send.turnId).toSet();

      test('on the next tap', () async {
        final room = await refusedOnce([_unsentWithFrases()], 1);

        room.sala.sendTheSceneRehearsal();
        await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

        expect(room.harness.room.scenesSent, hasLength(2));
        expect(turnIds(room), hasLength(1));
      });

      test('after the team opened another row and came back', () async {
        final room = await refusedOnce([_sentOne, _unsentTwoWithAFrase], 2);
        await _theRowOpens(room, 1, SceneStep.sent);
        await _theRowOpens(room, 2, SceneStep.translate);

        room.sala.sendTheSceneRehearsal();
        await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

        expect(turnIds(room), hasLength(1));
      });

      test('but a screen opened again mints a new one', () async {
        final room = await refusedOnce([_unsentWithFrases()], 1);
        room.sala.leaveTheSceneRehearsal();
        await waitFor(
          'a conversa voltar',
          () => room.state.stage == SalaStage.conversa,
        );
        await settle();
        await _theScreenOpens(room, on: _showing(1, SceneStep.translate));

        room.sala.sendTheSceneRehearsal();
        await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

        expect(turnIds(room), hasLength(2));
      });
    },
  );

  test(
    'a lost send whose look comes back empty keeps the screen with no sign, reads '
    'the list again, sends nothing again, and the sign shows back on the Canvas',
    () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..failHeldTurnWith = const NetworkFailed('a rede caiu')
        ..sceneRehearsals[0] = _asTheRoomHoldsIt(
          _unsentWithFrases(),
          sentAt: '2026-10-15T15:00:00+00:00',
        );
      final listed = room.asked('sceneRehearsalsOf');

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'a lista ser lida de novo',
        () => room.asked('sceneRehearsalsOf') > listed,
      );
      await _theRoomRests(room);
      await settle(const Duration(milliseconds: 400));

      expect(room.state.stage, SalaStage.cena);
      expect(room.state.needsPerson, isFalse);
      expect(
        room.harness.room.scenesSent,
        hasLength(1),
        reason: 'nada é reenviado sozinho',
      );

      room.sala.leaveTheSceneRehearsal();
      await waitFor(
        'a conversa voltar',
        () => room.state.stage == SalaStage.conversa,
      );
      await waitFor('o sinal da pessoa', () => room.state.needsPerson);
      expect(room.harness.room.scenesSent, hasLength(1));
      expect(room.repliedOnTheCanvas, isFalse);
    },
  );

  test(
    'a session gone while the moved attempt is being read leaves the next screen as it is',
    () async {
      final room = await _atRest([_unsentWithFrases(afterRestart: 'a1')]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.restartOutOfOrder)
        ..holdNextSceneList();
      final listed = room.asked('sceneRehearsalsOf');

      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'a lista ser pedida',
        () => room.asked('sceneRehearsalsOf') > listed,
      );
      final saidBefore = room.harness.voice.assets.length;
      room.harness.room.dropCoverageStream(error: const SessionGone());
      await waitFor(
        'a escolha abrir',
        () => room.state.stage == SalaStage.escolha,
      );
      room.harness.room.failSceneWith = const NetworkFailed('a rede caiu');
      room.harness.room.finishHeldSceneList();
      await settle(const Duration(milliseconds: 400));

      expect(
        room.harness.voice.assets
            .skip(saidBefore)
            .where((asset) => asset.contains('sem_conexao')),
        isEmpty,
      );
    },
  );

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
      'the list read again after a refused send never replaces the row the team tapped meanwhile',
      () async {
        final room = await _atRest([
          _sentOne,
          _rehearsal(
            n: 2,
            recordedAt: DateTime(2026, 10, 15, 14, 10),
            frases: [_frase('f1', 0, 4000)],
          ),
        ]);
        await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
        room.harness.room
          ..sendRefusalsFirst.add(RefusalCode.unnamed(422))
          ..holdNextSceneList();
        room.sala.sendTheSceneRehearsal();
        await _theRoomRests(room);
        room.harness.room.holdNextClip();

        room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
        await settle();
        room.harness.room.finishHeldSceneList();
        await settle();
        room.harness.room.finishHeldClip();
        await settle(const Duration(milliseconds: 400));

        expect(_showing(1, SceneStep.sent)(room.state.scene), isTrue);
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
      await tester.pump(const Duration(milliseconds: 700));
      notifier.restartTheSceneTranslation();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_enabled(tester, byLabel(_sentRow)), isFalse);
      notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(salaSessionProvider).scene.rehearsal?.n, 2);

      harness.room.finishHeldRestart();
      await tester.pump(const Duration(seconds: 7));
    });
  });

  test('a reopen over a take still waiting lists this session\'s rehearsals, '
      'with no row on screen', () async {
    final room = await _atRest([_sentOne, _unsentTwo, _ofAnotherSession]);
    await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
    room.sala.recordTheSceneAgain();
    await settle();
    room.harness.room.failSceneWith = const NetworkFailed('sem rede');
    await _recordAndStop(room);
    await waitFor(
      'o ensaio ficar esperando',
      () => room.state.scene.keep is NotKept,
    );
    room.sala.leaveTheSceneRehearsal();
    await waitFor(
      'a conversa voltar',
      () => room.state.stage == SalaStage.conversa,
    );
    room.harness.room
      ..holdNextKeepBeforeTheRoomActs()
      ..failSceneWith = null;

    await _theScreenOpens(
      room,
      on: (scene) =>
          scene.keep is NotKept && room.state.sceneRehearsals.isNotEmpty,
    );

    expect(_rows(room), [(1, false, 3), (2, true, 0)]);
    expect(room.state.scene.rehearsal, isNull);
    expect(room.state.scene.step, SceneStep.record);
    room.harness.room.finishHeldKeep();
    await settle();
  });

  group('every way out clears the scene rehearsal\'s list', () {
    void expectCleared(_Room room) {
      expect(room.state.sceneRehearsals, isEmpty);
      expect(room.state.scene.step, SceneStep.record);
    }

    test('after the reply of terminei', () async {
      final room = await _atRest([_unsentWithFrases()]);
      await _theScreenOpens(room, on: _showing(1, SceneStep.translate));
      room.sala.sendTheSceneRehearsal();
      await waitFor('a resposta tocar', () => room.repliedOnTheCanvas);

      expectCleared(room);
    });

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

    test('after a gone session met at the list a refused row reads', () async {
      final room = await _atRest([_sentOne, _unsentTwo]);
      await _theScreenOpens(room, on: _showing(2, SceneStep.translate));
      room.harness.room.forgetTheSession(_session);

      room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await waitFor(
        'a escolha abrir',
        () => room.state.stage == SalaStage.escolha,
      );

      expectCleared(room);
    });
  });
}
