import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle;
import 'the_scene_circles_are_her_check_ring_test.dart'
    show ripplesOf, theEdgeOf;

const _session = 'sessao-1';

const _instruction =
    'Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase acaba, '
    'e de novo para traduzir só aquela frase.';
const _translate = 'traduzir o ensaio da cena';
const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _pausaHint =
    'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para '
    'traduzir';
const _pausaAtTheTap =
    'a pausa ficou no toque — toquem no círculo para traduzir';
const _pausedHint = 'pausado — toque no círculo para marcar onde a frase acaba';
const _endedHint = 'fim do ensaio da cena';
const _playPause = 'Tocar ou pausar a gravação';
const _again = 'gravar o ensaio da cena de novo';
const _terminei = 'terminei';
const _confirm = 'Confirmar a tradução e seguir';

String _bar(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? afterRestart,
  int? durationMs,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  afterRestart: afterRestart,
  durationMs: durationMs,
  frases: frases,
);

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

bool _theFraseMicrophoneIsOpen(SalaSessionState state) =>
    switch (state.channel) {
      Microphone(owner: MicOwner.frase) => true,
      _ => false,
    };

/// A room at rest with one unsent scene rehearsal whose take is [take], opened on its
/// translate step.
Future<SceneRoom> _onTheTranslateStep({
  Uint8List? take,
  Duration length = const Duration(seconds: 10),
  SceneRehearsalRecord? rehearsal,
  List<SceneRehearsalRecord> alsoListed = const [],
  bool loudnessLate = false,
}) async {
  final room = await atRest(SalaHarness(filaEmMemoria: true));
  if (loudnessLate) room.harness.holdTheEnvelope();
  room.harness.room.sceneRehearsals
    ..addAll(alsoListed)
    ..add(rehearsal ?? _rehearsal());
  room.harness.room.sceneAudio = take ?? aSpokenWav(length: length);
  room.harness.playback.measured = length;
  room.sala.openTheSceneRehearsal();
  await translateOpens(room);
  await settle();
  return room;
}

Future<void> _listening(SceneRoom room) async {
  final plays = room.harness.playback.played.length;
  room.sala.playTheSceneRehearsal();
  await waitFor(
    'o ensaio da cena tocar',
    () =>
        room.harness.playback.played.length > plays &&
        room.state.channel is PartPlaying,
  );
  await settle();
}

Future<void> _circle(SceneRoom room) async {
  room.sala.tapTheTranslateCircle();
  await settle();
}

Future<void> _theFraseMicrophoneOpens(SceneRoom room) async {
  room.sala.tapTheTranslateCircle();
  await waitFor(
    'o microfone da frase abrir',
    () => _theFraseMicrophoneIsOpen(room.state),
  );
}

Future<void> _theFraseIsSent(SceneRoom room, {int already = 0}) async {
  room.sala.tapTheTranslateCircle();
  await waitFor(
    'a frase ir para a sala',
    () => room.harness.room.frasesKept.length > already,
  );
  await settle();
}

/// Mark a pausa at [at] while the take plays, open the frase microphone and close it.
Future<void> _aFraseAt(SceneRoom room, Duration at, {int already = 0}) async {
  room.harness.playback.at = at;
  await _circle(room);
  await _theFraseMicrophoneOpens(room);
  await _theFraseIsSent(room, already: already);
}

/// What a team does for a frase it saw go nowhere: tap the circle, and again if it
/// opened the microphone, until the room was sent something.
Future<void> _theTeamTellsItAgain(SceneRoom room) async {
  final posts = room.harness.room.frasesKept.length;
  for (
    var tap = 0;
    tap < 4 && room.harness.room.frasesKept.length == posts;
    tap++
  ) {
    room.sala.tapTheTranslateCircle();
    await settle();
    await waitFor('a tela parar de esperar', () => !room.state.scene.waiting);
  }
  await settle();
}

/// A frase at 4 s whose post ends with [failure] after the room did or did not keep it.
Future<void> _aFraseWhoseAnswerIsLost(
  SceneRoom room,
  RoomFailure failure, {
  bool keptBefore = true,
}) async {
  room.harness.room
    ..refusesOverlappingFrases = true
    ..frasesLandBeforeTheyFail = keptBefore
    ..frasesLandAfterTheyFail = !keptBefore
    ..sceneAnswersFirst.add(failure);
  await _aFraseAt(room, _s(4.0));
  room.harness.room
    ..frasesLandBeforeTheyFail = false
    ..frasesLandAfterTheyFail = false;
}

int _currentFrasesOf(SceneRoom room, [int n = 1]) => room
    .harness
    .room
    .sceneRehearsals
    .singleWhere((rehearsal) => rehearsal.n == n)
    .translatedFrases;

Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.tap(byLabel(label));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _onScreenPlaying(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await _tapAndSettle(tester, _translate);
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).channel is PartPlaying,
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _onScreenTheFraseIsSent(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final before = harness.room.frasesKept.length;
  await _tapAndSettle(tester, _tell);
  await pumpUntil(
    tester,
    () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
  );
  await _tapAndSettle(tester, _tell);
  await pumpUntil(tester, () => harness.room.frasesKept.length > before);
  await tester.pump(const Duration(milliseconds: 500));
}

Iterable<String> _wordsUnder(Finder root) sync* {
  for (final element
      in find
          .descendant(of: root, matching: find.byType(Semantics))
          .evaluate()) {
    final label = (element.widget as Semantics).properties.label;
    if (label != null) yield label;
  }
  for (final element
      in find.descendant(of: root, matching: find.byType(Text)).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) yield data;
  }
}

void main() {
  group('the translate step', () {
    testWidgets(
      'opening the translate step shows her instruction and plays nothing until «traduzir o ensaio da cena»',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          length: const Duration(seconds: 20),
          take: aSpokenWav(length: const Duration(seconds: 20)),
          rehearsal: _rehearsal(),
        );

        expect(byLabel(_instruction), findsOneWidget);
        expect(find.text(_instruction), findsOneWidget);
        expect(harness.sounds, isNot(contains('playback:play')));

        await _onScreenPlaying(tester, harness, container);

        expect(harness.playback.playedFrom.last, Duration.zero);
        expect(
          byLabel('ouvindo o ensaio da cena… — 0:00 / 0:20'),
          findsOneWidget,
        );
      },
    );

    test(
      'a resumed rehearsal plays from where the translation stopped',
      () async {
        final room = await _onTheTranslateStep(
          length: const Duration(seconds: 20),
          rehearsal: _rehearsal(
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 9000)],
          ),
        );

        await _listening(room);

        expect(
          room.harness.playback.playedFrom.last,
          const Duration(milliseconds: 9000),
        );
      },
    );

    test(
      'before «traduzir» the circle plays the take from where the translation stopped, marking nothing and opening no microphone',
      () async {
        final room = await _onTheTranslateStep(
          length: const Duration(seconds: 20),
          rehearsal: _rehearsal(
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 9000)],
          ),
        );
        final before = room.harness.sounds.length;

        await _circle(room);

        expect(
          room.state.channel,
          isA<PartPlaying>(),
          reason: 'o círculo não fazia nada antes de «traduzir»',
        );
        expect(
          room.harness.playback.playedFrom.last,
          const Duration(milliseconds: 9000),
        );
        expect(room.state.scene.pausa, isNull);
        expect(
          room.harness.sounds.skip(before),
          isNot(contains('recorder:start')),
        );
      },
    );
  });

  group('the pausa', () {
    testWidgets(
      'a tap 0.5 s after a frase ends, with a silence 0.3 s before the tap, lands in the middle of that silence and says her hint',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);

        await _tapAndSettle(tester, _tell);

        expect(
          container.read(salaSessionProvider).channel,
          isNot(isA<PartPlaying>()),
        );
        expect(byLabel('$_pausaHint — 0:03 / 0:10'), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);
        expect(harness.room.frasesKept.single.startsMs, 0);
        expect(harness.room.frasesKept.single.endsMs, 3100);
      },
    );

    testWidgets(
      'a tap with no silence within reach leaves the pausa at the tap',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(1.0), _s(1.4))]),
          rehearsal: _rehearsal(),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(6.0);

        await _tapAndSettle(tester, _tell);

        expect(byLabel('$_pausaHint — 0:06 / 0:10'), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);
        expect(harness.room.frasesKept.single.endsMs, 6000);
      },
    );

    test(
      'a pausa tapped before the take\'s loudness is read stays at the tap, and the next one snaps once it is',
      () async {
        final room = await _onTheTranslateStep(
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2)), (_s(6.0), _s(6.2))]),
          loudnessLate: true,
        );
        await _listening(room);

        await _aFraseAt(room, _s(3.5));
        room.harness.giveTheEnvelope();
        await settle();
        await waitFor(
          'o ensaio seguir tocando',
          () => room.state.channel is PartPlaying,
        );
        await _aFraseAt(room, _s(6.5), already: 1);

        expect(room.harness.room.frasesKept.map((sent) => sent.endsMs), [
          3500,
          6100,
        ]);
      },
    );

    test(
      'a take whose loudness is still being read is not read again when the room lists it anew',
      () async {
        final room = await atRest(
          SalaHarness(filaEmMemoria: true, restartWake: Duration.zero),
        );
        room.harness.holdTheEnvelope();
        room.harness.room
          ..sceneRehearsals.add(_rehearsal(frases: [_frase('f1', 0, 3000)]))
          ..sceneAudio = aSpokenWav(gaps: [(_s(3.0), _s(3.2))])
          ..refuseRestartWith = RefusalCode.restartOutOfOrder;
        room.harness.playback.measured = const Duration(seconds: 10);
        room.sala.openTheSceneRehearsal();
        await translateOpens(room);
        await settle();
        final listed = room.asked('sceneRehearsalsOf');

        await restartTheTranslationInTwoTaps(room);
        await waitFor(
          'a sala listar os ensaios de novo',
          () =>
              room.asked('sceneRehearsalsOf') > listed &&
              !room.state.scene.waiting,
        );
        await settle();

        expect(room.asked('sceneRehearsalsOf'), greaterThan(listed));
        expect(
          room.harness.mostEnvelopesReadAtOnce,
          1,
          reason:
              'a lista relida mostrava o mesmo take de novo, e o arquivo inteiro era '
              'lido outra vez enquanto a primeira leitura ainda corria',
        );
        room.harness.giveTheEnvelope();
        await waitFor(
          'o envelope chegar',
          () => room.state.sceneEnvelope != null,
        );
        expect(room.state.sceneEnvelope, isNotNull);
      },
    );

    test(
      'a take still being read is not read again when another row is opened and it is opened back',
      () async {
        final room = await _onTheTranslateStep(
          rehearsal: _rehearsal(n: 2),
          alsoListed: [_rehearsal()],
          loudnessLate: true,
        );
        for (final n in [1, 2]) {
          room.sala.openTheListedSceneRehearsal('ensaio-da-cena-$n');
          await waitFor(
            'o ensaio $n abrir',
            () =>
                room.state.scene.rehearsal?.n == n && !room.state.scene.waiting,
          );
          await settle();
        }

        expect(
          room.harness.mostEnvelopesReadAtOnce,
          2,
          reason:
              'só uma leitura era lembrada, a do último take; voltar ao primeiro '
              'lia o arquivo inteiro de novo com a primeira leitura ainda no ar',
        );
        room.harness.giveTheEnvelope();
        await waitFor(
          'o envelope chegar',
          () => room.state.sceneEnvelope != null,
        );
        expect(room.state.sceneEnvelope, isNotNull);
      },
    );

    test('the take\'s loudness is read off the UI thread', () async {
      final take = File('${aTempHome('sala-take').path}/cena.wav')
        ..writeAsBytesSync(aSpokenWav(gaps: [(_s(3.0), _s(5.0))]));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final read = await container.read(sceneEnvelopeReaderProvider)(take.path);

      expect(read?.length, const Duration(seconds: 10));
    });

    test(
      'a pausa is never closer than 0.2 s after the previous pause',
      () async {
        final room = await _onTheTranslateStep(
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );
        await _listening(room);

        await _aFraseAt(room, _s(3.1));

        final sent = room.harness.room.frasesKept.single;
        expect(sent.startsMs, 3000);
        expect(sent.endsMs, greaterThanOrEqualTo(3200));
      },
    );

    test(
      'a take with no loudness to read still keeps the pausa 0.2 s after the previous one, not a sliver',
      () async {
        final room = await _onTheTranslateStep(
          take: Uint8List.fromList(List.filled(4000, 7)),
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );
        await _listening(room);

        await _aFraseAt(room, _s(3.1));

        final sent = room.harness.room.frasesKept.single;
        expect(sent.startsMs, 3000);
        expect(
          sent.endsMs,
          3200,
          reason:
              'sem envelope a pausa ficava no toque, e a sala recebia uma frase de '
              '0,1 s',
        );
      },
    );

    test(
      'a take with no loudness to read and no room left for 0.2 s places no pausa',
      () async {
        final room = await _onTheTranslateStep(
          take: Uint8List.fromList(List.filled(4000, 7)),
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 9900)]),
        );
        await _listening(room);

        room.harness.playback.at = _s(9.95);
        await _circle(room);

        expect(
          room.state.scene.pausa,
          isNull,
          reason: 'a pausa ficava no toque, e a frase seguinte teria 0,05 s',
        );
        expect(room.harness.room.frasesKept, isEmpty);
      },
    );

    test('a pausa is never within 0.1 s of the end', () async {
      final room = await _onTheTranslateStep();
      await _listening(room);

      await _aFraseAt(room, _s(9.97));

      expect(
        room.harness.room.frasesKept.single.endsMs,
        lessThanOrEqualTo(9900),
      );
    });

    testWidgets('the play control pauses and marks a pausa like the circle', (
      tester,
    ) async {
      final (harness, container) = await translateOnScreen(
        tester,
        take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
        rehearsal: _rehearsal(),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.5);

      await _tapAndSettle(tester, _playPause);

      expect(
        container.read(salaSessionProvider).channel,
        isNot(isA<PartPlaying>()),
      );
      expect(byLabel('$_pausaHint — 0:03 / 0:10'), findsOneWidget);
      await _onScreenTheFraseIsSent(tester, harness, container);
      expect(harness.room.frasesKept.single.endsMs, 3100);
    });

    testWidgets(
      'paused with no pausa pending says her paused hint, with the clock where the take failed',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          rehearsal: _rehearsal(),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(2);

        harness.playback.failPlayback();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          byLabel('$_pausedHint — 0:02 / 0:10'),
          findsOneWidget,
          reason: 'o take que falhou dizia pausado sem dizer onde parou',
        );
      },
    );

    for (final (language, hearMine, paused) in [
      (
        'pt',
        'ouvir a minha tradução da frase 1',
        'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10',
      ),
      (
        'en',
        'hear my translation of sentence 1',
        'paused — tap the circle to mark where the sentence ends — 0:07 / 0:10',
      ),
    ]) {
      testWidgets(
        '$language: a take stopped by the team\'s own translation says her paused hint with the clock where it stopped',
        (tester) async {
          final (harness, container) = await translateOnScreen(
            tester,
            rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
          );
          final take = container.read(salaSessionProvider).scene.take;
          await _onScreenPlaying(tester, harness, container);
          container.read(roomLanguageProvider.notifier).choose(language);
          harness.playback.at = _s(7);
          await tester.pump(const Duration(milliseconds: 300));

          await tester.tap(byLabel(hearMine));
          await pumpUntil(
            tester,
            () =>
                harness.playback.played.last != take &&
                container.read(salaSessionProvider).channel is PartPlaying,
          );
          expect(harness.playback.played.last, isNot(take));
          harness.playback.finishPlayback();
          await pumpUntil(
            tester,
            () => container.read(salaSessionProvider).channel is! PartPlaying,
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            find.text(paused),
            findsOneWidget,
            reason: 'a dica de pausa vinha sem o relógio de onde o take parou',
          );
          expect(byLabel(paused), findsOneWidget);
        },
      );
    }
  });

  group('the frase', () {
    testWidgets(
      'circle to speak, circle to stop saves «frase N» and the take plays on with no further tap',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);
        final soundsBefore = harness.sounds.length;
        final calls = harness.room.calls.length;

        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        expect(
          container.read(salaSessionProvider).channel,
          const Microphone(MicOwner.frase),
        );
        await _tapAndSettle(tester, _tell);
        await pumpUntil(tester, () => byLabel(_bar(1)).evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));

        expect(harness.room.frasesKept, hasLength(1));
        expect(byLabel(_bar(1)), findsOneWidget);
        expect(
          harness.playback.playedFrom.last,
          const Duration(milliseconds: 3100),
        );
        expect(container.read(salaSessionProvider).channel, isA<PartPlaying>());
        expect(
          harness.sounds
              .skip(soundsBefore)
              .where(
                (sound) => sound.startsWith('voice:') && sound != 'voice:stop',
              ),
          isEmpty,
        );
        expect(harness.room.calls.skip(calls), isNot(contains('sendTurn')));
        expect(byLabel(_confirm), findsNothing);
      },
    );

    test(
      '«terminei» tapped while a frase is in flight sends nothing, and sends once after the frase landed',
      () async {
        final room = await _onTheTranslateStep(
          length: const Duration(seconds: 20),
          take: aSpokenWav(length: const Duration(seconds: 20)),
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );
        await _listening(room);
        room.harness.room.holdNextFrase();
        room.harness.playback.at = _s(8.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);
        await _theFraseIsSent(room);

        room.sala.sendTheSceneRehearsal();
        await settle();
        expect(room.harness.room.scenesSent, isEmpty);

        room.harness.room.finishHeldFrase();
        await waitFor(
          'a frase 2 chegar',
          () => room.state.scene.rehearsal?.translatedFrases == 2,
        );
        room.sala.sendTheSceneRehearsal();
        await waitFor(
          'o ensaio ir para a voz',
          () => room.harness.room.scenesSent.isNotEmpty,
        );
        await settle();
        expect(room.harness.room.scenesSent, hasLength(1));
      },
    );

    testWidgets(
      'the circle turns azul with her two ripples only while the frase microphone is open, and is telha before and after',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        Color edge() => theEdgeOf(tester, _tell).border!.top.color;
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);

        expect(edge(), const Color(0xFFBE4A01));
        expect(ripplesOf(_tell), 0);

        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );

        expect(
          edge(),
          const Color(0xFF89AAA3),
          reason: 'com o microfone aberto o anel dela fica azul',
        );
        expect(ripplesOf(_tell), 2);

        await _tapAndSettle(tester, _tell);
        await pumpUntil(tester, () => byLabel(_bar(1)).evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));

        expect(edge(), const Color(0xFFBE4A01));
      },
    );

    testWidgets(
      'while a frase is on its way to the room the circle breathes her areia thinking ring, not a pulsing red disc',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);
        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        harness.room.holdNextFrase();
        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).scene.waiting,
        );

        expect(container.read(salaSessionProvider).scene.waiting, isTrue);
        expect(
          theEdgeOf(tester, _tell).border!.top.color,
          const Color(0xFFC5C29F),
          reason: 'com a frase no ar o dela pensa, de borda areia',
        );
        harness.room.finishHeldFrase();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'a pending pausa gives the circle her firmer 2.2 edge, and the edge is 1.5 again once the frase is sent',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        double edge() => theEdgeOf(tester, _tell).border!.top.width;
        await _onScreenPlaying(tester, harness, container);

        expect(edge(), 1.5);

        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);

        expect(container.read(salaSessionProvider).scene.pausa, isNotNull);
        expect(
          edge(),
          2.2,
          reason:
              'com a pausa pendente o dela firma a borda: o círculo abre o '
              'microfone',
        );

        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        await _tapAndSettle(tester, _tell);
        await pumpUntil(tester, () => byLabel(_bar(1)).evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 300));

        expect(container.read(salaSessionProvider).scene.pausa, isNull);
        expect(edge(), 1.5);
      },
    );

    testWidgets(
      'a frase the room refuses leaves the pausa pending and the circle records it again',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        harness.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.wordlessTelling),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);

        await _onScreenTheFraseIsSent(tester, harness, container);

        expect(byLabel(_bar(1)), findsNothing);
        expect(byLabel('$_pausaHint — 0:03 / 0:10'), findsOneWidget);
        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        expect(
          container.read(salaSessionProvider).channel,
          const Microphone(MicOwner.frase),
        );
        await _tapAndSettle(tester, _tell);
        await pumpUntil(tester, () => harness.room.frasesKept.length > 1);
        final [first, second] = harness.room.frasesKept;
        expect(
          (second.startsMs, second.endsMs),
          (first.startsMs, first.endsMs),
        );
        expect(container.read(salaSessionProvider).needsPerson, isFalse);
      },
    );

    test(
      'a refused frase microphone records no refusal and calls no person, and the pausa still waits for the circle',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        room.harness.recorder.permitted = false;

        await _circle(room);
        await _circle(room);
        await settle();

        expect(
          room.container.read(micPermissionProvider),
          isNot(MicAccess.denied),
        );
        expect(room.state.needsPerson, isFalse);
        expect(room.state.channel, isNot(isA<Microphone>()));
        room.harness.recorder.permitted = true;
        await _theFraseMicrophoneOpens(room);
        await _theFraseIsSent(room);
        expect(room.harness.room.frasesKept.single.endsMs, 4000);
      },
    );

    test(
      'a second stop tap while the frase microphone closes keeps the frase once',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);
        room.harness.recorder.holdNextStop();

        room.sala.tapTheTranslateCircle();
        room.sala.tapTheTranslateCircle();
        room.harness.recorder.finishStop();
        await waitFor(
          'a frase ir para a sala',
          () => room.harness.room.frasesKept.isNotEmpty,
        );
        await settle();

        expect(room.harness.room.frasesKept, hasLength(1));
      },
    );

    test(
      'a frase microphone that fails to close is closed again by the next circle tap',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);
        room.harness.recorder.stopThrows = true;

        room.sala.tapTheTranslateCircle();
        await settle();
        room.harness.recorder.stopThrows = false;

        expect(_theFraseMicrophoneIsOpen(room.state), isTrue);
        await _theFraseIsSent(room);
        expect(room.harness.room.frasesKept.single.endsMs, 4000);
      },
    );

    test(
      'the room\'s list read again keeps the pausa pending and the take listened to',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        room.harness.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.notFound),
        );
        final listed = room.asked('sceneRehearsalsOf');
        await _theFraseMicrophoneOpens(room);
        await _theFraseIsSent(room);
        await waitFor(
          'a sala ler a lista de novo',
          () => room.asked('sceneRehearsalsOf') > listed,
        );
        await settle();

        await _theFraseMicrophoneOpens(room);
        await _theFraseIsSent(room, already: 1);
        final [first, second] = room.harness.room.frasesKept;
        expect(
          (second.startsMs, second.endsMs),
          (first.startsMs, first.endsMs),
        );
      },
    );

    test(
      'a tap past what the room measured, on a take kept as m4a, ends the frase at the room\'s length',
      () async {
        final room = await _onTheTranslateStep(
          take: Uint8List.fromList(List.filled(4000, 7)),
          rehearsal: _rehearsal(durationMs: 9500),
        );
        await _listening(room);

        await _aFraseAt(room, _s(9.8));

        expect(room.harness.room.frasesKept.single.endsMs, 9500);
      },
    );

    group(
      'a frase the room kept when its answer was lost is never kept twice',
      () {
        test('a network failure, told again at the same pausa', () async {
          final room = await _onTheTranslateStep();
          await _listening(room);
          await _aFraseWhoseAnswerIsLost(room, const NetworkFailed('timeout'));

          await _theTeamTellsItAgain(room);

          expect(_currentFrasesOf(room), 1);
        });

        test('an answer the tablet cannot read', () async {
          final room = await _onTheTranslateStep();
          await _listening(room);
          await _aFraseWhoseAnswerIsLost(
            room,
            const Refused(RefusalCode.unreadable),
          );

          await _theTeamTellsItAgain(room);

          expect(_currentFrasesOf(room), 1);
        });

        test(
          'a frase the room was still hearing when the tablet gave up',
          () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const NetworkFailed('HTTP 503'),
              keptBefore: false,
            );

            await _theTeamTellsItAgain(room);

            expect(_currentFrasesOf(room), 1);
          },
        );

        test('another rehearsal opened and this one opened again', () async {
          final room = await _onTheTranslateStep(
            rehearsal: _rehearsal(n: 2),
            alsoListed: [_rehearsal()],
          );
          await _listening(room);
          await _aFraseWhoseAnswerIsLost(room, const NetworkFailed('timeout'));
          for (final n in [1, 2]) {
            room.sala.openTheListedSceneRehearsal('ensaio-da-cena-$n');
            await waitFor(
              'o ensaio $n abrir',
              () =>
                  room.state.scene.rehearsal?.n == n &&
                  !room.state.scene.waiting,
            );
            await settle();
          }

          await _listening(room);
          room.harness.playback.at = _s(4.0);
          await _theTeamTellsItAgain(room);

          expect(_currentFrasesOf(room, 2), 1);
        });
      },
    );

    group(
      'a frase is held by its rehearsal from the moment it is posted until the room says kept, or refuses that frase',
      () {
        test(
          'held from the post: the screen left and opened again while the frase is in the air sends the same frase',
          () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            room.harness.room
              ..holdNextFrase()
              ..frasesLandBeforeTheyFail = true
              ..sceneAnswersFirst.add(const NetworkFailed('HTTP 503'));
            room.harness.playback.at = _s(4.0);
            await _circle(room);
            await _theFraseMicrophoneOpens(room);
            await _theFraseIsSent(room);
            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await translateOpens(room);
            await settle();
            await _listening(room);
            room.harness.playback.at = _s(4.0);
            await _circle(room);
            await _circle(room);
            if (_theFraseMicrophoneIsOpen(room.state)) await _circle(room);

            room.harness.room.finishHeldFrase();
            await waitFor('a sala responder', () => !room.state.scene.waiting);
            await settle();

            expect(_currentFrasesOf(room), 1);
          },
        );

        test(
          'a refusal that is not of the frase keeps it held: SCENE_REHEARSAL_SENDING on the resend',
          () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
            );
            room.harness.room.sceneAnswersFirst.add(
              const Refused(RefusalCode.sceneRehearsalSending),
            );
            await _theTeamTellsItAgain(room);

            await _theTeamTellsItAgain(room);

            expect(_currentFrasesOf(room), 1);
          },
        );

        for (final code in [
          RefusalCode.wordlessTelling,
          RefusalCode.fraseOutOfPlace,
          RefusalCode.sceneRehearsalSent,
          RefusalCode.notFound,
        ]) {
          test('a refusal of the frase lets it go: $code', () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            room.harness.room.sceneAnswersFirst.add(Refused(code));
            await _aFraseAt(room, _s(4.0));
            final held = room.harness.recorder.lastPath;

            expect(room.harness.recorder.deleted, contains(held));
            room.sala.tapTheTranslateCircle();
            await settle();
            expect(
              room.harness.room.frasesKept,
              hasLength(1),
              reason: 'nada retido para mandar de novo',
            );
          });
        }

        test(
          'the held frase is sent again under the attempt it was recorded in',
          () async {
            final room = await _onTheTranslateStep(
              rehearsal: _rehearsal(afterRestart: 'tentativa-1'),
            );
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
              keptBefore: false,
            );
            room.harness.room.sceneRehearsals[0] = _rehearsal(
              afterRestart: 'tentativa-2',
            );
            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await translateOpens(room);
            await settle();
            expect(room.state.scene.rehearsal?.afterRestart, 'tentativa-2');
            await _listening(room);
            room.harness.playback.at = _s(4.0);

            await _theTeamTellsItAgain(room);

            expect(
              room.harness.room.frasesKept.last.afterRestart,
              'tentativa-1',
            );
          },
        );

        test(
          '«terminei» with a frase held sends the frase first, and the rehearsal once it is kept',
          () async {
            final room = await _onTheTranslateStep(
              rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
            );
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
              keptBefore: false,
            );
            final posts = room.harness.room.frasesKept.length;

            room.sala.sendTheSceneRehearsal();
            await waitFor(
              'o ensaio ir para a voz',
              () => room.harness.room.scenesSent.isNotEmpty,
            );
            await settle();

            expect(room.harness.room.frasesKept, hasLength(posts + 1));
            expect(_currentFrasesOf(room), 2);
            expect(room.harness.room.scenesSent, hasLength(1));
          },
        );

        for (final (named, resent) in [
          ('kept', null),
          ('refused', const Refused(RefusalCode.wordlessTelling)),
        ]) {
          test(
            '«terminei» sends nothing when its screen moved on while the held frase was being sent again: $named',
            () async {
              final room = await _onTheTranslateStep(
                rehearsal: _rehearsal(n: 2, frases: [_frase('f1', 0, 3000)]),
                alsoListed: [
                  _rehearsal(frases: [_frase('r1-f1', 0, 3000)]),
                ],
              );
              await _listening(room);
              await _aFraseWhoseAnswerIsLost(
                room,
                const Refused(RefusalCode.sceneRehearsalSending),
                keptBefore: false,
              );
              final resend = room.harness.room.holdTheNextFrase();
              if (resent != null) {
                room.harness.room.sceneAnswersFirst.add(resent);
              }
              room.sala.sendTheSceneRehearsal();
              await settle();
              room.sala.leaveTheSceneRehearsal();
              await settle();
              room.sala.openTheSceneRehearsal();
              await translateOpens(room);
              await settle();
              room.sala.openTheListedSceneRehearsal('ensaio-da-cena-1');
              await waitFor(
                'o ensaio 1 abrir',
                () =>
                    room.state.scene.rehearsal?.n == 1 &&
                    !room.state.scene.waiting,
              );

              resend.complete();
              await settle();
              await settle();

              expect(room.harness.room.scenesSent, isEmpty);
            },
          );
        }

        test(
          'a late answer of a frase lets go of that frase only, never of the next one held',
          () async {
            final room = await _onTheTranslateStep(
              length: const Duration(seconds: 20),
              take: aSpokenWav(length: const Duration(seconds: 20)),
            );
            await _listening(room);
            final first = room.harness.room.holdTheNextFrase();
            await _aFraseAt(room, _s(4.0));
            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await translateOpens(room);
            await settle();
            await _listening(room);
            room.harness.playback.at = _s(4.0);
            await _theTeamTellsItAgain(room);
            expect(_currentFrasesOf(room), 1);
            room.harness.playback.at = _s(8.0);
            await _circle(room);
            await _theFraseMicrophoneOpens(room);
            final second = room.harness.room.holdTheNextFrase();
            room.sala.tapTheTranslateCircle();
            await waitFor(
              'a segunda frase ir',
              () => room.harness.room.frasesKept.length == 3,
            );

            first.complete();
            await settle();
            room.harness.room
              ..frasesLandBeforeTheyFail = true
              ..sceneAnswersFirst.add(
                const Refused(RefusalCode.sceneRehearsalSending),
              );
            second.complete();
            await waitFor('a sala responder', () => !room.state.scene.waiting);
            room.harness.room.frasesLandBeforeTheyFail = false;
            await settle();
            await _theTeamTellsItAgain(room);

            expect(_currentFrasesOf(room), 2);
          },
        );

        test(
          'a frase over one the room kept while its screen was away is refused, and the screen shows the kept one',
          () async {
            final room = await _onTheTranslateStep();
            room.harness.room.refusesOverlappingFrases = true;
            await _listening(room);
            room.harness.room.holdNextFrase();
            await _aFraseAt(room, _s(4.0));
            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await translateOpens(room);
            await settle();
            room.harness.room.finishHeldFrase();
            await settle();
            await _listening(room);
            final listed = room.asked('sceneRehearsalsOf');

            await _aFraseAt(room, _s(4.0), already: 1);
            await waitFor(
              'a sala ler a lista de novo',
              () => room.asked('sceneRehearsalsOf') > listed,
            );
            await settle();

            expect(_currentFrasesOf(room), 1);
            expect(
              room.state.scene.rehearsal?.frontier,
              const Duration(milliseconds: 4000),
            );
          },
        );

        test(
          '«terminei» with a frase held while the take plays to its end sends the rehearsal once, and the screen stops waiting',
          () async {
            final room = await _onTheTranslateStep(
              rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
            );
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
              keptBefore: false,
            );
            room.sala.playTheSceneRehearsal();
            await waitFor(
              'o ensaio da cena tocar',
              () => room.state.channel is PartPlaying,
            );
            final resend = room.harness.room.holdTheNextFrase();

            room.sala.sendTheSceneRehearsal();
            await settle();
            room.harness.playback.finishPlayback();
            await settle();
            resend.complete();
            await waitFor(
              'o ensaio ir para a voz',
              () => room.harness.room.scenesSent.isNotEmpty,
            );
            await settle();

            expect(room.harness.room.scenesSent, hasLength(1));
          },
        );

        test(
          'a held frase\'s file stays while a post of it is still in the air',
          () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            final first = room.harness.room.holdTheNextFrase();
            await _aFraseAt(room, _s(4.0));
            final path = room.harness.recorder.lastPath;
            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await translateOpens(room);
            await settle();
            await _listening(room);
            room.harness.playback.at = _s(4.0);
            await _circle(room);
            final resend = room.harness.room.holdTheNextFrase();
            room.sala.tapTheTranslateCircle();
            await waitFor(
              'o reenvio ir',
              () => room.harness.room.frasesKept.length == 2,
            );

            first.complete();
            await settle();
            expect(
              room.harness.recorder.deleted,
              isNot(contains(path)),
              reason: 'o reenvio ainda lê o arquivo',
            );
            resend.complete();
            await settle();

            expect(room.harness.recorder.deleted, contains(path));
          },
        );

        test(
          'a frase whose post is in the air when the life is rebuilt is deleted when the post lands',
          () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            final post = room.harness.room.holdTheNextFrase();
            room.harness.room.sceneAnswersFirst.add(
              const NetworkFailed('timeout'),
            );
            await _aFraseAt(room, _s(4.0));
            final path = room.harness.recorder.lastPath;

            room.container.invalidate(salaSessionProvider);
            room.container.read(salaSessionProvider);
            await settle();
            post.complete();
            await settle();

            expect(room.harness.recorder.deleted, contains(path));
          },
        );

        for (final (named, answer) in [
          ('kept', null),
          ('refused', const Refused(RefusalCode.wordlessTelling)),
        ]) {
          test('each frase file is deleted once: $named', () async {
            final room = await _onTheTranslateStep();
            await _listening(room);
            if (answer != null) room.harness.room.sceneAnswersFirst.add(answer);

            await _aFraseAt(room, _s(4.0));
            await settle();

            final path = room.harness.recorder.lastPath;
            expect(
              room.harness.recorder.deleted.where((deleted) => deleted == path),
              hasLength(1),
            );
          });
        }

        test(
          'a pausa marked past the held frase stays pending once the room kept it',
          () async {
            final room = await _onTheTranslateStep(
              rehearsal: _rehearsal(n: 2),
              alsoListed: [_rehearsal()],
            );
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
            );
            for (final n in [1, 2]) {
              room.sala.openTheListedSceneRehearsal('ensaio-da-cena-$n');
              await waitFor(
                'o ensaio $n abrir',
                () =>
                    room.state.scene.rehearsal?.n == n &&
                    !room.state.scene.waiting,
              );
              await settle();
            }
            await _listening(room);
            room.harness.playback.at = _s(8.0);
            await _circle(room);
            final plays = room.harness.playback.played.length;

            await _circle(room);
            await waitFor('a frase voltar', () => !room.state.scene.waiting);
            await settle();

            expect(_currentFrasesOf(room, 2), 1);
            expect(room.harness.playback.played, hasLength(plays));
            await _theFraseMicrophoneOpens(room);
            await _theFraseIsSent(room, already: 2);
            final sent = room.harness.room.frasesKept.last;
            expect((sent.startsMs, sent.endsMs), (4000, 8000));
          },
        );

        group('a held frase\'s file is deleted', () {
          Future<(SceneRoom, String?)> held() async {
            final room = await _onTheTranslateStep(
              rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
            );
            await _listening(room);
            await _aFraseWhoseAnswerIsLost(
              room,
              const Refused(RefusalCode.sceneRehearsalSending),
              keptBefore: false,
            );
            return (room, room.harness.recorder.lastPath);
          }

          test('when the room kept it', () async {
            final (room, path) = await held();
            expect(room.harness.recorder.deleted, isNot(contains(path)));

            await _theTeamTellsItAgain(room);

            expect(room.harness.recorder.deleted, contains(path));
          });

          test('when the rehearsal is recorded again', () async {
            final (room, path) = await held();

            room.sala.recordTheSceneAgain();
            await settle();

            expect(room.harness.recorder.deleted, contains(path));
          });

          test('when the room restarts the translation at the second tap of '
              'recomeçar a tradução', () async {
            final (room, path) = await held();

            room.sala.restartTheSceneTranslation();
            await waitFor(
              'o recomeço acordar',
              () => room.state.sceneRestart == BtRecomeco.pronto,
            );
            room.sala.restartTheSceneTranslation();
            await waitFor(
              'a sala recomeçar',
              () => room.harness.recorder.deleted.contains(path),
            );
          });

          test('when its session is gone', () async {
            final (room, path) = await held();
            room.harness.room.forgetTheSession(_session);

            room.sala.leaveTheSceneRehearsal();
            await settle();
            room.sala.openTheSceneRehearsal();
            await waitFor(
              'a sala esquecer a sessão',
              () => room.harness.recorder.deleted.contains(path),
            );
          });

          test(
            'and a life rebuilt never sweeps the frases left behind again',
            () async {
              final (room, _) = await held();
              final swept = room.harness.recorder.sweeps;
              room.container.dispose();

              final again = room.harness.container();
              addTearDown(again.dispose);
              again.read(salaSessionProvider);
              await settle();

              expect(room.harness.recorder.sweeps, swept);
            },
          );

          test('when the life ends', () async {
            final (room, path) = await held();

            room.container.dispose();
            await settle();

            expect(room.harness.recorder.deleted, contains(path));
          });
        });
      },
    );

    for (final (how, RoomFailure answer) in [
      ('refuses', const Refused('CONFLICT')),
      ('never answers', const NetworkFailed('sem rede')),
    ]) {
      test('a sentence whose restart the room $how stays on the tablet and is '
          'offered again', () async {
        final room = await _onTheTranslateStep(
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );
        await _listening(room);
        await _aFraseWhoseAnswerIsLost(
          room,
          const Refused(RefusalCode.sceneRehearsalSending),
          keptBefore: false,
        );
        final path = room.harness.recorder.lastPath;
        room.harness.room
          ..holdNextRestart()
          ..failSceneWith = answer;

        room.sala.restartTheSceneTranslation();
        await waitFor(
          'o recomeço acordar',
          () => room.state.sceneRestart == BtRecomeco.pronto,
        );
        room.sala.restartTheSceneTranslation();
        await settle();

        expect(room.harness.recorder.deleted, isNot(contains(path)));

        room.harness.room.finishHeldRestart();
        await waitFor(
          'a sala não recomeçar',
          () => room.state.sceneLine == SceneLine.restartFailed,
        );
        room.harness.room.failSceneWith = null;
        await settle();

        expect(room.harness.recorder.deleted, isNot(contains(path)));
        final posts = room.harness.room.frasesKept.length;

        await _theTeamTellsItAgain(room);

        expect(room.harness.room.frasesKept, hasLength(posts + 1));
      });
    }

    test(
      'a frase held after a lost answer whose rehearsal the room no longer has is let go, and the room is not asked for its list again and again',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        await _aFraseWhoseAnswerIsLost(
          room,
          const Refused(RefusalCode.sceneRehearsalSending),
          keptBefore: false,
        );
        room.harness.room.sceneRehearsals.clear();
        final listed = room.asked('sceneRehearsalsOf');

        await _theTeamTellsItAgain(room);
        await settle();

        expect(room.asked('sceneRehearsalsOf') - listed, lessThanOrEqualTo(1));
        room.sala.tapTheTranslateCircle();
        await settle();
        expect(
          _theFraseMicrophoneIsOpen(room.state),
          isTrue,
          reason: 'sem frase guardada, o círculo grava de novo',
        );
      },
    );

    test(
      '«gravar o ensaio da cena de novo» while the stop tap closes the microphone changes nothing, and the frase is kept once',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);
        room.harness.recorder.holdNextStop();

        room.sala.tapTheTranslateCircle();
        room.sala.recordTheSceneAgain();
        await settle();
        expect(room.state.scene.step, SceneStep.translate);
        room.harness.recorder.finishStop();
        await waitFor(
          'a frase ir para a sala',
          () => room.harness.room.frasesKept.isNotEmpty,
        );
        await settle();

        expect(_currentFrasesOf(room), 1);
      },
    );

    test(
      'a frase whose screen was left while the stop tap closed the microphone is never sent',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);
        room.harness.recorder.holdNextStop();

        room.sala.tapTheTranslateCircle();
        room.sala.leaveTheSceneRehearsal();
        room.harness.recorder.finishStop();
        await settle();

        expect(room.harness.room.frasesKept, isEmpty);
      },
    );

    test(
      '«gravar o ensaio da cena de novo» with the frase microphone open closes it and keeps nothing',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        room.harness.playback.at = _s(4.0);
        await _circle(room);
        await _theFraseMicrophoneOpens(room);

        room.sala.recordTheSceneAgain();
        await settle();

        expect(room.state.scene.step, SceneStep.record);
        expect(room.state.channel, isNot(isA<Microphone>()));
        expect(
          room.harness.recorder.deleted,
          [room.harness.recorder.lastPath],
          reason: 'o arquivo da frase foi descartado',
        );
        room.sala.sceneTap();
        await settle();
        expect(room.harness.room.frasesKept, isEmpty);
      },
    );

    test(
      'a frase recorded after «recomeçar a tradução» names the attempt the rehearsal is in',
      () async {
        final restarted = await _onTheTranslateStep(
          rehearsal: _rehearsal(afterRestart: 'tentativa-1'),
        );
        await _listening(restarted);
        await _aFraseAt(restarted, _s(4.0));
        final never = await _onTheTranslateStep();
        await _listening(never);
        await _aFraseAt(never, _s(4.0));

        expect(
          restarted.harness.room.frasesKept.single.afterRestart,
          'tentativa-1',
        );
        expect(never.harness.room.frasesKept.single.afterRestart, isNull);
      },
    );

    testWidgets(
      'the take played to its end leaves the last frase ending at the take\'s end, never past what the room measured',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          rehearsal: _rehearsal(
            durationMs: 9980,
            frases: [_frase('f1', 0, 6000)],
          ),
        );
        await _onScreenPlaying(tester, harness, container);

        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 300));

        await _onScreenTheFraseIsSent(tester, harness, container);
        final sent = harness.room.frasesKept.single;
        expect((sent.startsMs, sent.endsMs), (6000, 9980));
      },
    );

    testWidgets('a take kept as m4a places the pausa at the tap', (
      tester,
    ) async {
      final (harness, container) = await translateOnScreen(
        tester,
        take: Uint8List.fromList(List.filled(4000, 7)),
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.5);

      await _tapAndSettle(tester, _tell);

      await _onScreenTheFraseIsSent(tester, harness, container);
      expect(harness.room.frasesKept.single.endsMs, 3500);
    });

    testWidgets('a take kept as m4a says her pausa is at the tap', (
      tester,
    ) async {
      final (harness, container) = await translateOnScreen(
        tester,
        take: Uint8List.fromList(List.filled(4000, 7)),
        rehearsal: _rehearsal(),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.1);

      await _tapAndSettle(tester, _tell);

      expect(byLabel('$_pausaAtTheTap — 0:03 / 0:10'), findsOneWidget);
      expect(find.textContaining(_pausaHint), findsNothing);
    });

    testWidgets(
      'her «fim do ensaio da cena» shows once the take played to its end, and once everything is translated',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 6000)]),
        );
        await _onScreenPlaying(tester, harness, container);

        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 300));
        expect(byLabel(_endedHint), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);

        expect(byLabel(_bar(2)), findsOneWidget);
        expect(byLabel(_endedHint), findsOneWidget);
        expect(harness.playback.playedFrom, hasLength(1));
      },
    );
  });

  group('the words and the strip', () {
    testWidgets(
      'the translate step reads in her order: the instruction, the play control, the strip, «traduzir», the circle, the frases, «terminei», then «gravar o ensaio da cena de novo»',
      (tester) async {
        await translateOnScreen(
          tester,
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );

        final tops = [
          byLabel(_instruction),
          byLabel(_playPause),
          find.byType(SceneStrip),
          byLabel(_translate),
          byLabel(_tell),
          byLabel(_bar(1)),
          byLabel(_terminei),
          byLabel(_again),
        ].map((control) => tester.getTopLeft(control).dy).toList();

        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]), reason: 'o controle $i');
        }
        expect(find.text(_terminei), findsOneWidget);
        expect(find.text(_again), findsOneWidget);
      },
    );

    testWidgets(
      'each «frase N» is a bar as long as its frase against the longest',
      (tester) async {
        await translateOnScreen(
          tester,
          rehearsal: _rehearsal(
            frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 9000)],
          ),
        );
        double barOf(String frase) => tester
            .getSize(
              find
                  .descendant(
                    of: byLabel(frase),
                    matching: find.byType(FractionallySizedBox),
                  )
                  .first,
            )
            .width;

        expect(find.text('frase 1'), findsOneWidget);
        expect(find.text('frase 2'), findsOneWidget);
        expect(barOf(_bar(1)) / barOf(_bar(2)), closeTo(0.5, 0.01));
      },
    );

    testWidgets(
      'the whole translate step never says «cortar», «corte» or «Trecho»',
      (tester) async {
        final banned = RegExp(r'cortar|corte|trecho', caseSensitive: false);
        final (harness, container) = await translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
          rehearsal: _rehearsal(),
        );
        final seen = <String>[];
        void look() {
          seen.addAll(_wordsUnder(find.byType(SceneRehearsalView)));
          expect(find.byIcon(LucideIcons.scissors), findsNothing);
        }

        look();
        await _onScreenPlaying(tester, harness, container);
        look();
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);
        look();
        await _tapAndSettle(tester, _tell);
        await pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        look();
        await _tapAndSettle(tester, _tell);
        await pumpUntil(tester, () => byLabel(_bar(1)).evaluate().isNotEmpty);
        look();

        expect(seen, isNotEmpty);
        expect(seen.where(banned.hasMatch), isEmpty);
      },
    );

    testWidgets('the strip carries no words and cannot be tapped', (
      tester,
    ) async {
      final (harness, container) = await translateOnScreen(
        tester,
        rehearsal: _rehearsal(),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(4.0);
      await _tapAndSettle(tester, _tell);
      final strip = find.byType(SceneStrip);
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.byType(Text)),
        findsNothing,
      );
      expect(_wordsUnder(strip).where((words) => words.isNotEmpty), isEmpty);
      final sounds = harness.sounds.length;

      await tester.tap(strip, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.sounds.skip(sounds), isEmpty);
      expect(byLabel('$_pausaHint — 0:04 / 0:10'), findsOneWidget);
    });
  });

  test(
    'play while the team\'s translation sounds plays the take on from '
    'where the translation stopped, never a pausa in the translation',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      await _listening(room);
      final take = room.state.scene.take;
      room.sala.hearTheFraseTranslation('f1');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.last != take,
      );
      room.harness.playback.at = _s(6.0);

      room.sala.playTheSceneRehearsal();
      await settle();

      expect(
        room.state.scene.pausa,
        isNull,
        reason: 'o play marcava a pausa na posição da tradução',
      );
      expect(room.harness.playback.played.last, take);
      expect(room.harness.playback.playedFrom.last, _s(4.0));
    },
  );

  test(
    'the circle while the team\'s translation sounds plays the take on from '
    'where the translation stopped, never a pausa in the translation',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      await _listening(room);
      final take = room.state.scene.take;
      room.sala.hearTheFraseTranslation('f1');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.last != take,
      );
      room.harness.playback.at = _s(6.0);

      await _circle(room);

      expect(
        room.state.scene.pausa,
        isNull,
        reason: 'o círculo marcava a pausa na posição da tradução',
      );
      expect(room.harness.playback.played.last, take);
      expect(room.harness.playback.playedFrom.last, _s(4.0));
    },
  );

  test('the circle during a frase\'s download plays the take, and the '
      'translation that lands after it never sounds, as hers', () async {
    final room = await _onTheTranslateStep(
      rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
    );
    await _listening(room);
    final take = room.state.scene.take;
    room.harness.room.holdNextClip();

    room.sala.hearTheFraseTranslation('f1');
    await settle();
    await _circle(room);
    expect(room.harness.playback.played.last, take);
    room.harness.room.finishHeldClip();
    await settle();

    expect(
      room.harness.playback.played.map((path) => path.split('/').last),
      isNot(contains('cena-ensaio-da-cena-1-frase-f1.wav')),
      reason: 'a tradução que chegava tarde cortava o ensaio do círculo',
    );
    expect(room.harness.playback.played.last, take);
  });

  test(
    '«ouvir a pausa» during a frase\'s download hushes the translation, even '
    'when the pausa ends before it lands',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 2000)]),
      );
      await _listening(room);
      room.harness.playback.at = _s(6.0);
      await _circle(room);
      room.harness.room.holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f1')
        ..hearThePause();
      await settle();
      expect(room.harness.playback.ranges.last, '4500-6000');
      room.harness.playback.finishPlayback();
      await settle();
      room.harness.room.finishHeldClip();
      await settle();

      expect(
        room.harness.playback.played.map((path) => path.split('/').last),
        isNot(contains('cena-ensaio-da-cena-1-frase-f1.wav')),
        reason: 'a tradução que chegava depois da pausa tocava sozinha',
      );
    },
  );

  test('a frase\'s translation the room cannot hand over says nothing and '
      'leaves the team on the translate step, never on the choice', () async {
    final room = await _onTheTranslateStep(
      rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
    );
    room.harness.room.failClipWith = const SessionGone();

    room.sala.hearTheFraseTranslation('f1');
    await settle();
    await settle();

    expect(
      room.state.stage,
      SalaStage.cena,
      reason: 'uma tradução que não descia encerrava a sessão',
    );
    expect(room.state.sessionId, _session);
    expect(room.state.scene.step, SceneStep.translate);
    expect(room.state.sceneLine, isNull);
    expect(room.state.machine.aHaltWaitsForTheCanvas, isNull);
    expect(room.state.halt, isA<NoHalt>());
  });

  test(
    'a second speaker during a download plays that frase\'s translation, and '
    'the first ask failing after it writes nothing over it',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(
          frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
        ),
      );
      room.harness.room
        ..failFraseOf['f2'] = const SessionGone()
        ..holdNextClip();

      room.sala
        ..hearTheFraseTranslation('f2')
        ..hearTheFraseTranslation('f1');
      await settle();
      room.harness.room.finishHeldClip();
      await settle();
      await settle();

      expect(
        room.state.stage,
        SalaStage.cena,
        reason: 'o primeiro pedido, ao falhar, encerrava a sessão por cima',
      );
      expect(room.state.sceneLine, isNull);
      expect(
        room.harness.playback.played.map((path) => path.split('/').last),
        ['cena-ensaio-da-cena-1-frase-f1.wav'],
        reason: 'o segundo alto-falante ficava apagado e tocava a frase 2',
      );
    },
  );

  test('the circle during a frase\'s download plays on, and a translation the '
      'disk then fails to keep writes nothing over it', () async {
    final room = await _onTheTranslateStep(
      rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
    );
    await _listening(room);
    final take = room.state.scene.take;
    room.harness.room.holdNextClip();

    room.sala.hearTheFraseTranslation('f1');
    await settle();
    await _circle(room);
    room.harness.recorder.keepBytesFails = true;
    room.harness.room.finishHeldClip();
    await settle();

    expect(
      room.state.sceneLine,
      isNull,
      reason: 'o disco da tradução calada escrevia por cima do círculo',
    );
    expect(room.state.channel, isA<PartPlaying>());
    expect(room.harness.playback.played.last, take);
  });

  test(
    '«manter a tradução de antes» while the team\'s translation sounds leaves '
    'it sounding, as hers',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      room.sala.translateTheFraseAgain('f1');
      await settle();
      room.sala.hearTheFraseTranslation('f1');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.any(
          (path) => path.endsWith('cena-ensaio-da-cena-1-frase-f1.wav'),
        ),
      );

      room.sala.keepTheEarlierTranslation();
      await settle();

      expect(room.state.scene.translatingAgain, isNull);
      expect(
        room.state.channel,
        isA<PartPlaying>(),
        reason: 'o manter calava a tradução de vocês que ainda soava',
      );
    },
  );

  test(
    '«manter a tradução de antes» before the team\'s translation lands keeps '
    'the download alive, and it plays when it lands',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      room.sala.translateTheFraseAgain('f1');
      await settle();
      room.harness.room.holdNextClip();

      room.sala.hearTheFraseTranslation('f1');
      await settle();
      room.sala.keepTheEarlierTranslation();
      await settle();
      room.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 400));

      expect(
        room.harness.playback.played.map((path) => path.split('/').last),
        contains('cena-ensaio-da-cena-1-frase-f1.wav'),
        reason: 'o manter derrubava a tradução de vocês que ainda descia',
      );
      expect(
        room.state.scene.translatingAgain,
        isNull,
        reason: 'a tradução, ao chegar, punha a frase de volta a ser traduzida',
      );
    },
  );

  test('the room\'s list landing while the team\'s translation comes down '
      'neither stops nor drops it: it plays when it lands, as hers', () async {
    final room = await _onTheTranslateStep(
      rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
    );
    room.harness.room
      ..sendRefusalsFirst.add(RefusalCode.unnamed(422))
      ..holdNextSceneList();
    room.sala.sendTheSceneRehearsal();
    await waitFor(
      'a sala descansar',
      () => !room.state.theSceneIsSending && !room.state.scene.waiting,
    );
    room.harness.room.holdNextClip();

    room.sala.hearTheFraseTranslation('f1');
    await settle();
    room.harness.room.finishHeldSceneList();
    await settle();
    room.harness.room.finishHeldClip();
    await settle(const Duration(milliseconds: 400));

    expect(
      room.harness.playback.played.map((path) => path.split('/').last),
      contains('cena-ensaio-da-cena-1-frase-f1.wav'),
      reason: 'a lista que chegava derrubava a tradução de vocês que descia',
    );
  });

  test('the circle that sends a held frase during the team\'s translation '
      'download lets it go: it never plays, as hers', () async {
    final room = await _onTheTranslateStep(
      rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
    );
    await _listening(room);
    room.harness.room.sceneAnswersFirst.add(
      const Refused(RefusalCode.sceneRehearsalSending),
    );
    await _aFraseAt(room, _s(6.0));
    room.harness.room
      ..holdNextFrase()
      ..holdNextClip();

    room.sala.hearTheFraseTranslation('f1');
    await settle();
    room.sala.tapTheTranslateCircle();
    await settle();
    expect(room.state.scene.waiting, isTrue);
    room.harness.room.finishHeldClip();
    await settle(const Duration(milliseconds: 400));

    expect(
      room.harness.playback.played.map((path) => path.split('/').last),
      isNot(contains('cena-ensaio-da-cena-1-frase-f1.wav')),
      reason: 'a tradução que chegava depois do círculo tocava sozinha',
    );
    room.harness.room.finishHeldFrase();
    await settle();
  });

  test(
    'play that waits for the room\'s list first during the team\'s translation '
    'download lets it go: it never plays, as hers',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(
          frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
        ),
      );
      room.sala.translateTheFraseAgain('f1');
      await settle();
      room.harness.room
        ..frasesLandBeforeTheyFail = true
        ..sceneAnswersFirst.add(const NetworkFailed('timeout'))
        ..sceneListsAnswerFirst.add(const NetworkFailed('timeout'));
      await _theFraseMicrophoneOpens(room);
      await _theFraseIsSent(room);
      room.harness.room.frasesLandBeforeTheyFail = false;
      await waitFor(
        'a sala não saber se guardou',
        () => room.state.sceneTranslationUnseen && !room.state.scene.waiting,
      );
      room.harness.room
        ..holdNextSceneList()
        ..holdNextClip();

      room.sala.hearTheFraseTranslation('f2');
      await settle();
      room.sala.playTheSceneRehearsal();
      await settle();
      expect(room.state.scene.waiting, isTrue);
      room.harness.room.finishHeldClip();
      await settle(const Duration(milliseconds: 400));

      expect(
        room.harness.playback.played.map((path) => path.split('/').last),
        isNot(contains('cena-ensaio-da-cena-1-frase-f2.wav')),
        reason:
            'a tradução que chegava enquanto a lista era lida tocava sozinha',
      );
      room.harness.room.finishHeldSceneList();
      await settle();
    },
  );

  test(
    'the room\'s list landing while the team\'s translation sounds leaves it '
    'sounding, as hers',
    () async {
      final room = await _onTheTranslateStep(
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 4000)]),
      );
      room.harness.room
        ..sendRefusalsFirst.add(RefusalCode.unnamed(422))
        ..holdNextSceneList();
      room.sala.sendTheSceneRehearsal();
      await waitFor(
        'a sala descansar',
        () => !room.state.theSceneIsSending && !room.state.scene.waiting,
      );
      room.sala.hearTheFraseTranslation('f1');
      await waitFor(
        'a tradução da frase tocar',
        () => room.harness.playback.played.any(
          (path) => path.endsWith('cena-ensaio-da-cena-1-frase-f1.wav'),
        ),
      );

      room.harness.room.finishHeldSceneList();
      await settle(const Duration(milliseconds: 400));

      expect(
        room.state.channel,
        isA<PartPlaying>(),
        reason: 'a lista que chegava calava a tradução de vocês que soava',
      );
      expect(room.harness.playback.played, hasLength(1));
    },
  );
}
