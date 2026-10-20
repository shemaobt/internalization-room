import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

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

final _redMicrophone = byLabel('ensaio da cena');

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
}) async {
  final room = await atRest();
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

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 40 && !done(); vez++) {
    await tester.pump(beat);
  }
}

/// The scene screen pumped over a session at rest in Articulação, open on the translate
/// step of one unsent rehearsal whose take is [take].
Future<(SalaHarness, ProviderContainer)> _translateOnScreen(
  WidgetTester tester, {
  Uint8List? take,
  Duration length = const Duration(seconds: 10),
  SceneRehearsalRecord? rehearsal,
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room.sceneRehearsals.add(rehearsal ?? _rehearsal());
  harness.room.sceneAudio = take ?? aSpokenWav(length: length);
  harness.playback.measured = length;
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
  await tester.tap(_redMicrophone);
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).scene.step == SceneStep.translate,
  );
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container);
}

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
  await _pumpUntil(
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
  await _pumpUntil(
    tester,
    () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
  );
  await _tapAndSettle(tester, _tell);
  await _pumpUntil(tester, () => harness.room.frasesKept.length > before);
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
        final (harness, container) = await _translateOnScreen(
          tester,
          length: const Duration(seconds: 20),
          take: aSpokenWav(length: const Duration(seconds: 20)),
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
      'before «traduzir» the circle marks nothing and opens no microphone',
      () async {
        final room = await _onTheTranslateStep();
        final before = room.harness.sounds.length;

        await _circle(room);
        await _circle(room);

        expect(room.state.channel, isNot(isA<Microphone>()));
        expect(
          room.harness.sounds.skip(before),
          isNot(contains('playback:play')),
        );
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
        final (harness, container) = await _translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);

        await _tapAndSettle(tester, _tell);

        expect(
          container.read(salaSessionProvider).channel,
          isNot(isA<PartPlaying>()),
        );
        expect(byLabel(_pausaHint), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);
        expect(harness.room.frasesKept.single.startsMs, 0);
        expect(harness.room.frasesKept.single.endsMs, 3100);
      },
    );

    testWidgets(
      'a tap with no silence within reach leaves the pausa at the tap',
      (tester) async {
        final (harness, container) = await _translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(1.0), _s(1.4))]),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(6.0);

        await _tapAndSettle(tester, _tell);

        expect(byLabel(_pausaHint), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);
        expect(harness.room.frasesKept.single.endsMs, 6000);
      },
    );

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
      final (harness, container) = await _translateOnScreen(
        tester,
        take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.5);

      await _tapAndSettle(tester, _playPause);

      expect(
        container.read(salaSessionProvider).channel,
        isNot(isA<PartPlaying>()),
      );
      expect(byLabel(_pausaHint), findsOneWidget);
      await _onScreenTheFraseIsSent(tester, harness, container);
      expect(harness.room.frasesKept.single.endsMs, 3100);
    });

    testWidgets('paused with no pausa pending says her paused hint', (
      tester,
    ) async {
      final (harness, container) = await _translateOnScreen(tester);
      await _onScreenPlaying(tester, harness, container);

      harness.playback.failPlayback();
      await tester.pump(const Duration(milliseconds: 300));

      expect(byLabel(_pausedHint), findsOneWidget);
    });
  });

  group('the frase', () {
    testWidgets(
      'circle to speak, circle to stop saves «frase N» and the take plays on with no further tap',
      (tester) async {
        final (harness, container) = await _translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);
        final soundsBefore = harness.sounds.length;
        final calls = harness.room.calls.length;

        await _tapAndSettle(tester, _tell);
        await _pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        expect(
          container.read(salaSessionProvider).channel,
          const Microphone(MicOwner.frase),
        );
        await _tapAndSettle(tester, _tell);
        await _pumpUntil(
          tester,
          () => byLabel('frase 1').evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(harness.room.frasesKept, hasLength(1));
        expect(byLabel('frase 1'), findsOneWidget);
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
      'a frase the room refuses leaves the pausa pending and the circle records it again',
      (tester) async {
        final (harness, container) = await _translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
        );
        harness.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.wordlessTelling),
        );
        await _onScreenPlaying(tester, harness, container);
        harness.playback.at = _s(3.5);
        await _tapAndSettle(tester, _tell);

        await _onScreenTheFraseIsSent(tester, harness, container);

        expect(byLabel('frase 1'), findsNothing);
        expect(byLabel(_pausaHint), findsOneWidget);
        await _tapAndSettle(tester, _tell);
        await _pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        expect(
          container.read(salaSessionProvider).channel,
          const Microphone(MicOwner.frase),
        );
        await _tapAndSettle(tester, _tell);
        await _pumpUntil(tester, () => harness.room.frasesKept.length > 1);
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

    test(
      'a frase held after a lost answer whose rehearsal the room no longer has is let go, and the room is not asked for its list again and again',
      () async {
        final room = await _onTheTranslateStep();
        await _listening(room);
        await _aFraseWhoseAnswerIsLost(
          room,
          const NetworkFailed('timeout'),
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
        final (harness, container) = await _translateOnScreen(
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
      final (harness, container) = await _translateOnScreen(
        tester,
        take: Uint8List.fromList(List.filled(4000, 7)),
        rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.1);

      await _tapAndSettle(tester, _tell);

      await _onScreenTheFraseIsSent(tester, harness, container);
      expect(harness.room.frasesKept.single.endsMs, 3100);
    });

    testWidgets('a take kept as m4a says her pausa is at the tap', (
      tester,
    ) async {
      final (harness, container) = await _translateOnScreen(
        tester,
        take: Uint8List.fromList(List.filled(4000, 7)),
      );
      await _onScreenPlaying(tester, harness, container);
      harness.playback.at = _s(3.1);

      await _tapAndSettle(tester, _tell);

      expect(byLabel(_pausaAtTheTap), findsOneWidget);
      expect(byLabel(_pausaHint), findsNothing);
    });

    testWidgets(
      'her «fim do ensaio da cena» shows once the take played to its end, and once everything is translated',
      (tester) async {
        final (harness, container) = await _translateOnScreen(
          tester,
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 6000)]),
        );
        await _onScreenPlaying(tester, harness, container);

        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 300));
        expect(byLabel(_endedHint), findsOneWidget);
        await _onScreenTheFraseIsSent(tester, harness, container);

        expect(byLabel('frase 2'), findsOneWidget);
        expect(byLabel(_endedHint), findsOneWidget);
        expect(harness.playback.playedFrom, hasLength(1));
      },
    );
  });

  group('the words and the strip', () {
    testWidgets(
      'the translate step reads in her order: the instruction, the play control, the strip, «traduzir», the circle, the frases, «terminei», then «gravar o ensaio da cena de novo»',
      (tester) async {
        await _translateOnScreen(
          tester,
          rehearsal: _rehearsal(frases: [_frase('f1', 0, 3000)]),
        );

        final tops = [
          byLabel(_instruction),
          byLabel(_playPause),
          find.byType(SceneStrip),
          byLabel(_translate),
          byLabel(_tell),
          byLabel('frase 1'),
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
        await _translateOnScreen(
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
        expect(barOf('frase 1') / barOf('frase 2'), closeTo(0.5, 0.01));
      },
    );

    testWidgets(
      'the whole translate step never says «cortar», «corte» or «Trecho»',
      (tester) async {
        final banned = RegExp(r'cortar|corte|trecho', caseSensitive: false);
        final (harness, container) = await _translateOnScreen(
          tester,
          take: aSpokenWav(gaps: [(_s(3.0), _s(3.2))]),
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
        await _pumpUntil(
          tester,
          () => _theFraseMicrophoneIsOpen(container.read(salaSessionProvider)),
        );
        look();
        await _tapAndSettle(tester, _tell);
        await _pumpUntil(
          tester,
          () => byLabel('frase 1').evaluate().isNotEmpty,
        );
        look();

        expect(seen, isNotEmpty);
        expect(seen.where(banned.hasMatch), isEmpty);
      },
    );

    testWidgets('the strip carries no words and cannot be tapped', (
      tester,
    ) async {
      final (harness, container) = await _translateOnScreen(tester);
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
      expect(byLabel(_pausaHint), findsOneWidget);
    });
  });
}
