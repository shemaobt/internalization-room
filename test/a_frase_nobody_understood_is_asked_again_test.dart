import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';
const _rehearsalId = 'ensaio-da-cena-1';

const _notUnderstood = 'não entendi — traduzam de novo esse pedaço';
const _translate = 'traduzir o ensaio da cena';
const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _playPause = 'Tocar ou pausar a gravação';
const _pausaHint =
    'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para '
    'traduzir';
const _pausaAtTheTap =
    'a pausa ficou no toque — toquem no círculo para traduzir';
const _endedHint = 'fim do ensaio da cena';
const _keepTheEarlier = 'manter a tradução de antes';
const _again = 'gravar o ensaio da cena de novo';
const _terminei = 'terminei';
const _sending = 'enviando a tradução do ensaio da cena para a voz…';
const _wentToTheVoice = 'a tradução do ensaio da cena foi para a voz';

String _translateAgainBar(int n) =>
    'Ouvir esta frase de novo e traduzir de novo — $n';
String _translatingAgainLine(int n) =>
    'traduzindo de novo a frase $n — toquem no círculo (a pausa só se move na '
    'última frase; para mudar uma pausa anterior, recomeçar a tradução)';
String _hearMine(int n) => 'ouvir a minha tradução da frase $n';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  int? durationMs,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  durationMs: durationMs,
  frases: frases,
);

final _fourFrases = _rehearsal(
  frases: [
    _frase('f1', 0, 4000),
    _frase('f2', 4000, 9000),
    _frase('f3', 9000, 13000),
    _frase('f4', 13000, 17000),
  ],
);

final _oneFrase = _rehearsal(frases: [_frase('f1', 0, 3000)]);

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

final _anM4aTake = Uint8List.fromList(List.filled(4000, 7));

final class _Screen {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Screen(this.tester, this.harness, this.container);

  SalaSessionState get state => container.read(salaSessionProvider);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  FakeRoom get room => harness.room;

  Future<void> beat([int ms = 300]) => tester.pump(Duration(milliseconds: ms));

  Future<void> until(bool Function() done) => pumpUntil(tester, done);

  Future<void> tap(String label) async {
    await tester.tap(byLabel(label));
    await beat();
  }

  bool get theFraseMicrophoneIsOpen => switch (state.channel) {
    Microphone(owner: MicOwner.frase) => true,
    _ => false,
  };

  bool shows(String words) =>
      byLabel(words).evaluate().isNotEmpty &&
      find.text(words).evaluate().isNotEmpty;

  int get replies =>
      harness.voice.played.where((url) => url == turnoUrl).length;

  Future<void> listens() async {
    await tap(_translate);
    await until(() => state.channel is PartPlaying);
    await beat(100);
  }

  Future<void> theFraseMicrophoneOpens() async {
    await tap(_tell);
    await until(() => theFraseMicrophoneIsOpen);
  }

  /// The circle that opens the frase microphone and the circle that stops it, then the
  /// room's answer.
  Future<void> tellsTheFrase() async {
    final posts = room.frasesKept.length;
    await theFraseMicrophoneOpens();
    await tap(_tell);
    await until(() => room.frasesKept.length > posts && !state.scene.waiting);
    await beat(500);
  }

  int get currentFrases => room.sceneRehearsals
      .singleWhere((rehearsal) => rehearsal.rehearsalId == _rehearsalId)
      .translatedFrases;
}

Future<_Screen> _onScreen(
  WidgetTester tester, {
  Uint8List? take,
  Duration length = const Duration(seconds: 20),
  required SceneRehearsalRecord rehearsal,
  List<SceneRehearsalRecord> alsoListed = const [],
}) async {
  final (harness, container) = await translateOnScreen(
    tester,
    take: take ?? aSpokenWav(length: length),
    length: length,
    rehearsal: rehearsal,
    alsoListed: alsoListed,
  );
  return _Screen(tester, harness, container);
}

/// Frase 1 kept, the take listened to from where it stops, and a pausa marked at 6 s.
Future<_Screen> _aPausaAfterFrase1(
  WidgetTester tester, {
  Uint8List? take,
  List<SceneRehearsalRecord> alsoListed = const [],
}) async {
  final screen = await _onScreen(
    tester,
    take: take,
    length: const Duration(seconds: 10),
    rehearsal: _oneFrase,
    alsoListed: alsoListed,
  );
  await screen.listens();
  screen.harness.playback.at = _s(6.0);
  await screen.tap(_tell);
  return screen;
}

/// The frase at the pausa told, and the room heard no words in it.
Future<_Screen> _aFraseNobodyUnderstood(
  WidgetTester tester, {
  List<SceneRehearsalRecord> alsoListed = const [],
}) async {
  final screen = await _aPausaAfterFrase1(
    tester,
    take: _anM4aTake,
    alsoListed: alsoListed,
  );
  screen.room.sceneAnswersFirst.add(const Refused(RefusalCode.wordlessTelling));
  await screen.tellsTheFrase();
  return screen;
}

/// The four frases on screen, the take listened to, and frase [n]'s bar tapped.
Future<_Screen> _aBarTapped(
  WidgetTester tester,
  int n, {
  List<SceneRehearsalRecord> alsoListed = const [],
}) async {
  final screen = await _onScreen(
    tester,
    rehearsal: _fourFrases,
    alsoListed: alsoListed,
  );
  await screen.listens();
  await screen.tap(_translateAgainBar(n));
  return screen;
}

/// «terminei» on a rehearsal with a frase, whose turn the room holds, and how many
/// fixed lines the voice had said before it.
Future<(_Screen, int)> _sendingTheScene(WidgetTester tester) async {
  final screen = await _onScreen(tester, rehearsal: _oneFrase);
  final said = screen.harness.voice.fixedLines.length;
  screen.room.holdNextTurn();
  await screen.tap(_terminei);
  return (screen, said);
}

/// The held turn answered, until her send-off line shows, to within 10 ms.
Future<void> _theVoiceAnswers(_Screen screen) async {
  screen.room.finishHeldTurn();
  await pumpUntil(
    screen.tester,
    () => screen.shows(_wentToTheVoice),
    beat: const Duration(milliseconds: 10),
  );
}

void main() {
  group('not understood', () {
    testWidgets(
      'a frase translated in silence says her line, stores no frase and the circle opens the microphone for that frase again',
      (tester) async {
        final screen = await _aFraseNobodyUnderstood(tester);

        expect(byLabel(_notUnderstood), findsOneWidget);
        expect(find.text(_notUnderstood), findsOneWidget);
        expect(byLabel(_translateAgainBar(2)), findsNothing);
        expect(screen.currentFrases, 1);
        expect(byLabel('$_pausaAtTheTap — 0:06 / 0:10'), findsOneWidget);

        await screen.theFraseMicrophoneOpens();
        expect(screen.theFraseMicrophoneIsOpen, isTrue);
        expect(byLabel(_notUnderstood), findsNothing);
        await screen.tap(_tell);
        await screen.until(() => screen.room.frasesKept.length > 1);

        final [first, second] = screen.room.frasesKept;
        expect(
          (second.startsMs, second.endsMs),
          (first.startsMs, first.endsMs),
        );
      },
    );

    testWidgets(
      'three frases nobody understood in a row call no person and never fall',
      (tester) async {
        final screen = await _aPausaAfterFrase1(tester);

        for (var time = 0; time < 3; time++) {
          screen.room.sceneAnswersFirst.add(
            const Refused(RefusalCode.wordlessTelling),
          );
          await screen.tellsTheFrase();
        }

        expect(screen.room.frasesKept, hasLength(3));
        expect(screen.state.needsPerson, isFalse);
        expect(screen.state.halt, isA<NoHalt>());
        expect(screen.shows(_notUnderstood), isTrue);
      },
    );

    for (final lost in [
      const NetworkFailed('HTTP 502'),
      const NetworkFailed('timeout'),
    ]) {
      testWidgets(
        'a frase the room answers 502 or never answers says her line: $lost',
        (tester) async {
          final screen = await _aPausaAfterFrase1(tester);
          screen.room.sceneAnswersFirst.add(lost);

          await screen.tellsTheFrase();

          expect(screen.shows(_notUnderstood), isTrue);
          expect(byLabel('$_pausaHint — 0:06 / 0:10'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'a frase the room kept whose answer was lost, told again, is refused as out of place and shows once',
      (tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room
          ..refusesOverlappingFrases = true
          ..frasesLandBeforeTheyFail = true
          ..sceneAnswersFirst.add(const NetworkFailed('timeout'));
        await screen.tellsTheFrase();
        screen.room.frasesLandBeforeTheyFail = false;
        expect(screen.shows(_notUnderstood), isTrue);

        await screen.tellsTheFrase();
        await screen.until(
          () => byLabel(_translateAgainBar(2)).evaluate().isNotEmpty,
        );
        await screen.beat(500);

        final [first, second] = screen.room.frasesKept;
        expect(second.audio, isNot(first.audio));
        expect(screen.currentFrases, 2);
        expect(byLabel(_translateAgainBar(2)), findsOneWidget);
        expect(byLabel(_translateAgainBar(3)), findsNothing);
      },
    );

    testWidgets(
      'a frase the room never got says her line, and told again it is kept',
      (tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room.sceneAnswersFirst.add(const NetworkFailed('timeout'));
        await screen.tellsTheFrase();
        expect(screen.shows(_notUnderstood), isTrue);

        await screen.tellsTheFrase();

        final [first, second] = screen.room.frasesKept;
        expect(second.audio, isNot(first.audio));
        expect(screen.currentFrases, 2);
        expect(byLabel(_translateAgainBar(2)), findsOneWidget);
        expect(byLabel(_notUnderstood), findsNothing);
      },
    );

    testWidgets(
      'a frase refused as forbidden is not understood and calls nobody',
      (tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room.sceneAnswersFirst.add(const Refused(RefusalCode.forbidden));

        await screen.tellsTheFrase();

        expect(screen.state.needsPerson, isFalse);
        expect(byLabel(_notUnderstood), findsOneWidget);
        closeTheRoom(screen.container);
        await screen.beat();
      },
    );

    group('her line goes when the team', () {
      testWidgets('records again', (tester) async {
        final screen = await _aFraseNobodyUnderstood(tester);

        await screen.tap(_again);

        expect(byLabel(_notUnderstood), findsNothing);
      });

      testWidgets('opens another unsent row', (tester) async {
        final screen = await _aFraseNobodyUnderstood(
          tester,
          alsoListed: [_rehearsal(n: 0)],
        );

        screen.sala.openTheListedSceneRehearsal('ensaio-da-cena-0');
        await screen.until(
          () =>
              screen.state.scene.rehearsal?.n == 0 &&
              !screen.state.scene.waiting,
        );
        await screen.beat();

        expect(byLabel(_notUnderstood), findsNothing);
      });

      testWidgets('tells a frase that then lands', (tester) async {
        final screen = await _aFraseNobodyUnderstood(tester);

        await screen.tellsTheFrase();

        expect(byLabel(_translateAgainBar(2)), findsOneWidget);
        expect(byLabel(_notUnderstood), findsNothing);
      });
    });

    testWidgets('a refused re-translation keeps the bar armed and her line', (
      tester,
    ) async {
      final screen = await _aBarTapped(tester, 2);
      screen.room.sceneAnswersFirst.add(
        const Refused(RefusalCode.wordlessTelling),
      );

      await screen.tellsTheFrase();

      expect(screen.shows(_notUnderstood), isTrue);
      await screen.theFraseMicrophoneOpens();
      expect(screen.theFraseMicrophoneIsOpen, isTrue);
      await screen.tap(_tell);
      await screen.until(() => screen.room.frasesKept.length > 1);
      final second = screen.room.frasesKept.last;
      expect(second.replaces, 'f2');
      expect((second.startsMs, second.endsMs), (4000, 9000));
    });
  });

  group('translate again', () {
    testWidgets(
      'tapping frase 3\'s bar plays its stretch and arms a new translation; «manter a tradução de antes» keeps the one before',
      (tester) async {
        final screen = await _aBarTapped(tester, 3);

        expect(screen.harness.playback.ranges.last, '9000-13000');
        expect(screen.shows(_translatingAgainLine(3)), isTrue);

        await screen.tap(_keepTheEarlier);
        expect(byLabel(_translatingAgainLine(3)), findsNothing);
        expect(screen.harness.playback.sounding, isFalse);
        expect(screen.room.frasesKept, isEmpty);

        final plays = screen.harness.playback.playedFrom.length;
        await screen.tap(_tell);
        expect(screen.state.channel, isNot(isA<Microphone>()));
        expect(screen.harness.playback.playedFrom, hasLength(plays + 1));
        expect(
          screen.harness.playback.playedFrom.last,
          const Duration(milliseconds: 17000),
        );
      },
    );

    testWidgets(
      're-translating frase 3 replaces it, keeps its span and the take does not play on',
      (tester) async {
        final screen = await _aBarTapped(tester, 3);
        final playedBefore = screen.harness.playback.played.length;

        await screen.tellsTheFrase();

        final sent = screen.room.frasesKept.single;
        expect(
          (sent.startsMs, sent.endsMs, sent.replaces),
          (9000, 13000, 'f3'),
        );
        expect(screen.harness.playback.played, hasLength(playedBefore));
        expect(screen.currentFrases, 4);
        await screen.tap(_hearMine(3));
        await screen.until(() => screen.harness.room.clipsFetched.isNotEmpty);
        expect(
          screen.harness.room.clipsFetched.last,
          RoomRepository.sceneFraseAudioUrl(
            _session,
            _rehearsalId,
            '$_rehearsalId-frase-5',
          ),
        );
      },
    );

    testWidgets('a translatedAgain stretch played to its end places no pausa', (
      tester,
    ) async {
      final screen = await _aBarTapped(tester, 3);

      screen.harness.playback.finishPlayback();
      await screen.beat();

      expect(find.textContaining(_pausaHint), findsNothing);
      expect(find.textContaining(_pausaAtTheTap), findsNothing);
      expect(byLabel(_endedHint), findsNothing);
      await screen.tellsTheFrase();
      expect(screen.room.frasesKept.single.replaces, 'f3');
    });

    testWidgets(
      'play while a frase is armed again drops it and goes on from where the translation stopped',
      (tester) async {
        final screen = await _aBarTapped(tester, 2);
        final plays = screen.harness.playback.playedFrom.length;

        await screen.tap(_playPause);

        expect(byLabel(_translatingAgainLine(2)), findsNothing);
        expect(screen.harness.playback.playedFrom, hasLength(plays + 1));
        expect(
          screen.harness.playback.playedFrom.last,
          const Duration(milliseconds: 17000),
        );
        screen.harness.playback.at = _s(18.5);
        await screen.tap(_tell);
        await screen.tellsTheFrase();
        final sent = screen.room.frasesKept.single;
        expect(sent.replaces, isNull);
        expect(sent.startsMs, 17000);
      },
    );
  });

  testWidgets(
    'a frase waiting to be sent again keeps the bars from arming, and the circle sends it',
    (tester) async {
      final screen = await _aPausaAfterFrase1(tester);
      screen.room.sceneAnswersFirst.add(
        const Refused(RefusalCode.sceneRehearsalSending),
      );
      await screen.tellsTheFrase();
      final ranges = screen.harness.playback.ranges.length;

      await screen.tap(_translateAgainBar(1));

      expect(byLabel(_translatingAgainLine(1)), findsNothing);
      expect(screen.harness.playback.ranges, hasLength(ranges));
      await screen.tap(_tell);
      await screen.until(() => screen.room.frasesKept.length > 1);
      final [first, second] = screen.room.frasesKept;
      expect(second.audio, first.audio);
      expect(second.replaces, isNull);
    },
  );

  testWidgets(
    '«manter a tradução de antes» lets go of a translation again the room has not kept',
    (tester) async {
      final screen = await _aBarTapped(tester, 2);
      screen.room.sceneAnswersFirst.add(
        const Refused(RefusalCode.sceneRehearsalSending),
      );
      await screen.tellsTheFrase();

      await screen.tap(_keepTheEarlier);
      await screen.tap(_playPause);
      screen.harness.playback.at = _s(18.5);
      await screen.tap(_tell);
      await screen.tellsTheFrase();

      final sent = screen.room.frasesKept.last;
      expect(screen.room.frasesKept, hasLength(2));
      expect((sent.startsMs, sent.replaces), (17000, null));
    },
  );

  testWidgets('play lets go of a translation again the room has not kept', (
    tester,
  ) async {
    final screen = await _aBarTapped(tester, 2);
    screen.room.sceneAnswersFirst.add(
      const Refused(RefusalCode.sceneRehearsalSending),
    );
    await screen.tellsTheFrase();

    await screen.tap(_playPause);
    screen.harness.playback.at = _s(18.5);
    await screen.tap(_tell);
    await screen.tellsTheFrase();

    final sent = screen.room.frasesKept.last;
    expect(screen.room.frasesKept, hasLength(2));
    expect((sent.startsMs, sent.replaces), (17000, null));
  });

  testWidgets('«terminei» gives up a frase armed to be translated again', (
    tester,
  ) async {
    final screen = await _aBarTapped(tester, 2);
    screen.room.holdNextTurn();

    await screen.tap(_terminei);

    expect(byLabel(_translatingAgainLine(2)), findsNothing);
    expect(byLabel(_keepTheEarlier), findsNothing);
    screen.room.finishHeldTurn();
    await screen.beat(2000);
  });

  group('hear my translation', () {
    testWidgets(
      '«ouvir a minha tradução da frase 2» stops the take and plays the team\'s translation of frase 2',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _fourFrases);
        await screen.listens();
        final take = screen.harness.playback.played.last;

        await screen.tap(_hearMine(2));
        await screen.until(() => screen.harness.playback.played.last != take);

        expect(
          screen.harness.room.clipsFetched.last,
          RoomRepository.sceneFraseAudioUrl(_session, _rehearsalId, 'f2'),
        );
        expect(screen.harness.playback.played.last, contains('frase-f2'));
        expect(find.textContaining(_pausaHint), findsNothing);
      },
    );
  });

  group('a list read while a frase is armed to be translated again', () {
    /// Frase 5 told at 18.5 s and refused as NOT_FOUND, whose list read the room holds
    /// until bar 2 is tapped, then answers with [listed].
    Future<_Screen> theListLands(
      WidgetTester tester, {
      SceneRehearsalRecord? listed,
    }) async {
      final screen = await _onScreen(tester, rehearsal: _fourFrases);
      await screen.listens();
      screen.harness.playback.at = _s(18.5);
      await screen.tap(_tell);
      screen.room
        ..sceneAnswersFirst.add(const Refused(RefusalCode.notFound))
        ..holdNextSceneList();
      if (listed != null) screen.room.sceneRehearsals[0] = listed;
      await screen.tellsTheFrase();
      await screen.tap(_translateAgainBar(2));
      screen.room.finishHeldSceneList();
      await screen.beat(500);
      return screen;
    }

    testWidgets(
      'keeps the frase armed when the list still holds it, and the circle records it',
      (tester) async {
        final screen = await theListLands(tester);

        expect(screen.shows(_translatingAgainLine(2)), isTrue);
        await screen.tellsTheFrase();
        final sent = screen.room.frasesKept.last;
        expect((sent.startsMs, sent.endsMs, sent.replaces), (4000, 9000, 'f2'));
      },
    );

    testWidgets(
      'drops the arm and stops its stretch when the list no longer holds the frase',
      (tester) async {
        final screen = await theListLands(
          tester,
          listed: _rehearsal(frases: [_frase('f1', 0, 4000)]),
        );

        expect(byLabel(_translatingAgainLine(2)), findsNothing);
        expect(byLabel(_keepTheEarlier), findsNothing);
        expect(screen.harness.playback.sounding, isFalse);
      },
    );
  });

  testWidgets(
    'a translation again whose answer and list read were both lost says her line without «manter», and translated again it replaces the newest',
    (tester) async {
      final screen = await _aBarTapped(tester, 3);
      screen.room
        ..frasesLandBeforeTheyFail = true
        ..sceneAnswersFirst.add(const NetworkFailed('timeout'))
        ..sceneListsAnswerFirst.add(const NetworkFailed('timeout'));
      await screen.tellsTheFrase();
      screen.room.frasesLandBeforeTheyFail = false;
      expect(screen.shows(_notUnderstood), isTrue);
      expect(byLabel(_keepTheEarlier), findsNothing);

      await screen.tellsTheFrase();

      final [first, second] = screen.room.frasesKept;
      expect((first.replaces, second.replaces), ('f3', 'f3'));
      expect(screen.currentFrases, 4);
      expect(byLabel(_translateAgainBar(3)), findsOneWidget);
      expect(byLabel(_notUnderstood), findsNothing);
      await screen.tap(_hearMine(3));
      await screen.until(() => screen.room.clipsFetched.isNotEmpty);
      expect(
        screen.room.clipsFetched.last,
        RoomRepository.sceneFraseAudioUrl(
          _session,
          _rehearsalId,
          '$_rehearsalId-frase-6',
        ),
      );
    },
  );

  group('«terminei» with a held frase whose last try fails', () {
    for (final (named, failure) in [
      ('nobody understood it', const Refused(RefusalCode.wordlessTelling)),
      ('its answer was lost', const NetworkFailed('timeout')),
      ('the room refused it with no name', Refused(RefusalCode.unnamed(422))),
    ]) {
      /// Frase 2 held at 6 s, «terminei», and the resend fails with [failure].
      Future<_Screen> theSendStops(WidgetTester tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.sceneRehearsalSending),
        );
        await screen.tellsTheFrase();
        final posts = screen.room.frasesKept.length;
        screen.room.sceneAnswersFirst.add(failure);
        await screen.tap(_terminei);
        await screen.until(
          () =>
              screen.room.frasesKept.length > posts &&
              !screen.state.scene.waiting,
        );
        await screen.beat(500);
        return screen;
      }

      testWidgets(
        '$named: nothing is sent, her line shows and the piece stays at its cut; told again, «terminei» sends it',
        (tester) async {
          final screen = await theSendStops(tester);

          expect(screen.room.scenesSent, isEmpty);
          expect(screen.shows(_notUnderstood), isTrue);
          expect(byLabel('$_pausaHint — 0:06 / 0:10'), findsOneWidget);
          await screen.tellsTheFrase();
          expect(byLabel(_translateAgainBar(2)), findsOneWidget);
          await screen.tap(_terminei);
          await screen.until(() => screen.room.scenesSent.isNotEmpty);
          expect(screen.room.scenesSent, hasLength(1));
          expect(screen.currentFrases, 2);
          await screen.beat(2000);
        },
      );

      testWidgets('$named: a second «terminei» sends without it', (
        tester,
      ) async {
        final screen = await theSendStops(tester);

        await screen.tap(_terminei);
        await screen.until(() => screen.room.scenesSent.isNotEmpty);

        expect(screen.room.scenesSent, hasLength(1));
        expect(screen.currentFrases, 1);
        await screen.beat(2000);
      });
    }
  });

  group('a translation again whose answer was lost reads the list', () {
    testWidgets(
      'the room kept it: it shows as kept with no line, «ouvir» plays it and «terminei» carries it',
      (tester) async {
        final screen = await _aBarTapped(tester, 3);
        screen.room
          ..frasesLandBeforeTheyFail = true
          ..sceneAnswersFirst.add(const NetworkFailed('timeout'));

        await screen.tellsTheFrase();
        screen.room.frasesLandBeforeTheyFail = false;

        expect(byLabel(_notUnderstood), findsNothing);
        expect(byLabel(_keepTheEarlier), findsNothing);
        expect(byLabel(_translatingAgainLine(3)), findsNothing);
        await screen.tap(_hearMine(3));
        await screen.until(() => screen.room.clipsFetched.isNotEmpty);
        expect(
          screen.room.clipsFetched.last,
          RoomRepository.sceneFraseAudioUrl(
            _session,
            _rehearsalId,
            '$_rehearsalId-frase-5',
          ),
        );
        await screen.beat(500);
        await screen.tap(_terminei);
        await screen.until(() => screen.room.scenesSent.isNotEmpty);
        expect(screen.room.scenesSent, hasLength(1));
        expect(screen.room.frasesKept, hasLength(1));
        await screen.beat(2000);
      },
    );

    testWidgets('the room did not keep it: her line and «manter»', (
      tester,
    ) async {
      final screen = await _aBarTapped(tester, 3);
      screen.room.sceneAnswersFirst.add(const NetworkFailed('timeout'));

      await screen.tellsTheFrase();

      expect(screen.shows(_notUnderstood), isTrue);
      expect(byLabel(_keepTheEarlier), findsOneWidget);
      expect(screen.currentFrases, 4);
    });
  });

  group('a translation again whose answer was lost', () {
    /// Frase 3 translated again, its answer lost after the room kept it if [kept], and
    /// the list read the room holds until the room's `finishHeldSceneList`.
    Future<_Screen> theListIsRead(
      WidgetTester tester, {
      required bool kept,
    }) async {
      final screen = await _aBarTapped(tester, 3);
      screen.room
        ..frasesLandBeforeTheyFail = kept
        ..sceneAnswersFirst.add(const NetworkFailed('timeout'))
        ..holdNextSceneList();
      final posts = screen.room.frasesKept.length;
      await screen.theFraseMicrophoneOpens();
      await screen.tap(_tell);
      await screen.until(() => screen.room.frasesKept.length > posts);
      await screen.beat(500);
      screen.room.frasesLandBeforeTheyFail = false;
      return screen;
    }

    testWidgets(
      'shows only «traduzindo de novo» while the list is read, and the circle waits',
      (tester) async {
        final screen = await theListIsRead(tester, kept: true);

        expect(screen.shows(_translatingAgainLine(3)), isTrue);
        expect(byLabel(_notUnderstood), findsNothing);
        expect(byLabel(_keepTheEarlier), findsNothing);
        await screen.tap(_tell);
        expect(screen.state.channel, isNot(isA<Microphone>()));
        screen.room.finishHeldSceneList();
        await screen.beat(500);
        expect(byLabel(_notUnderstood), findsNothing);
        expect(byLabel(_translatingAgainLine(3)), findsNothing);
      },
    );

    testWidgets(
      'the room did not keep it: the list read shows her line and «manter»',
      (tester) async {
        final screen = await theListIsRead(tester, kept: false);

        screen.room.finishHeldSceneList();
        await screen.beat(500);

        expect(screen.shows(_notUnderstood), isTrue);
        expect(byLabel(_keepTheEarlier), findsOneWidget);
      },
    );

    testWidgets(
      'the room did not keep it: the list read shows what the room holds, another tablet\'s frase included, with her line and «manter»',
      (tester) async {
        final screen = await _aBarTapped(tester, 3);
        screen.room
          ..sceneRehearsals[0] = _rehearsal(
            frases: [..._fourFrases.frases, _frase('f5', 17000, 19000)],
          )
          ..sceneAnswersFirst.add(const NetworkFailed('timeout'));

        await screen.tellsTheFrase();

        expect(byLabel(_translateAgainBar(5)), findsOneWidget);
        expect(screen.shows(_notUnderstood), isTrue);
        expect(byLabel(_keepTheEarlier), findsOneWidget);
      },
    );

    /// Frase 3 translated again, kept by the room, its answer lost and its list read
    /// lost too.
    Future<_Screen> nothingIsKnown(
      WidgetTester tester, {
      List<SceneRehearsalRecord> alsoListed = const [],
    }) async {
      final screen = await _aBarTapped(tester, 3, alsoListed: alsoListed);
      screen.room
        ..frasesLandBeforeTheyFail = true
        ..sceneAnswersFirst.add(const NetworkFailed('timeout'))
        ..sceneListsAnswerFirst.add(const NetworkFailed('timeout'));
      await screen.tellsTheFrase();
      screen.room.frasesLandBeforeTheyFail = false;
      return screen;
    }

    int listReads(_Screen screen) =>
        screen.room.calls.where((call) => call == 'sceneRehearsalsOf').length;

    testWidgets(
      'and the list read too: play reads the list first, shows the new one and plays on',
      (tester) async {
        final screen = await nothingIsKnown(tester);
        final reads = listReads(screen);
        final plays = screen.harness.playback.playedFrom.length;

        await screen.tap(_playPause);
        await screen.beat(500);

        expect(listReads(screen), reads + 1);
        expect(byLabel(_notUnderstood), findsNothing);
        expect(screen.harness.playback.playedFrom, hasLength(plays + 1));
        await screen.tap(_hearMine(3));
        await screen.until(() => screen.room.clipsFetched.isNotEmpty);
        expect(
          screen.room.clipsFetched.last,
          RoomRepository.sceneFraseAudioUrl(
            _session,
            _rehearsalId,
            '$_rehearsalId-frase-5',
          ),
        );
      },
    );

    testWidgets(
      'and the list read too: the last frase told again, a play tapped over the pause being heard, whose list lands on places unknown, leaves the take silent',
      (tester) async {
        final screen = await _aBarTapped(tester, 4);
        screen.room
          ..frasesLandBeforeTheyFail = true
          ..sceneAnswersFirst.add(const NetworkFailed('timeout'))
          ..sceneListsAnswerFirst.add(const NetworkFailed('timeout'));
        await screen.tellsTheFrase();
        screen.room.frasesLandBeforeTheyFail = false;
        await screen.tap('ouvir a pausa');
        await screen.until(() => screen.state.channel is PartPlaying);
        expect(screen.state.channel, isA<PartPlaying>());
        screen.room.sceneRehearsals[0] = _rehearsal(
          frases: [..._fourFrases.frases, _frase('f5', 17000, 25000)],
        );

        await screen.tap(_playPause);
        await screen.until(
          () => screen.state.scene.step == SceneStep.placesUnknown,
        );
        await screen.beat(500);

        expect(screen.state.scene.step, SceneStep.placesUnknown);
        expect(
          screen.state.channel,
          isNot(isA<PartPlaying>()),
          reason:
              'o take seguia tocando na tela de lugares desconhecidos, onde nada o para',
        );
      },
    );

    testWidgets(
      'and the list read too: «terminei» reads the list first and sends the scene once',
      (tester) async {
        final screen = await nothingIsKnown(tester);
        final reads = listReads(screen);

        await screen.tap(_terminei);
        await screen.until(() => screen.room.scenesSent.isNotEmpty);

        expect(listReads(screen), reads + 1);
        expect(screen.room.scenesSent, hasLength(1));
        await screen.beat(2000);
      },
    );

    /// «terminei», once the list read before it lands, and what the scene sent
    /// holds against what the screen showed when it went.
    Future<void> theSceneGoesAsShown(_Screen screen) async {
      final reads = listReads(screen);

      await screen.tap(_terminei);
      await screen.until(() => screen.room.scenesSent.isNotEmpty);

      expect(listReads(screen), reads + 1);
      expect(screen.room.scenesSent, hasLength(1));
      expect(
        screen.state.scene.rehearsal!.currentFrases[2].fraseId,
        screen.room.sceneRehearsals
            .singleWhere((rehearsal) => rehearsal.rehearsalId == _rehearsalId)
            .currentFrases[2]
            .fraseId,
      );
      await screen.beat(2000);
    }

    testWidgets(
      'and the list read too: a new translation of that frase kept ends it, and «terminei» reads no list',
      (tester) async {
        final screen = await nothingIsKnown(tester);
        await screen.tellsTheFrase();
        final reads = listReads(screen);

        await screen.tap(_terminei);
        await screen.until(() => screen.room.scenesSent.isNotEmpty);

        expect(listReads(screen), reads);
        expect(screen.room.scenesSent, hasLength(1));
        await screen.beat(2000);
      },
    );

    testWidgets(
      'and the list read too: another rehearsal\'s list read settles it and shows what the room holds when this one opens again',
      (tester) async {
        final screen = await nothingIsKnown(
          tester,
          alsoListed: [
            _rehearsal(
              n: 0,
              frases: [_frase('g1', 0, 3000), _frase('g2', 3000, 6000)],
            ),
          ],
        );
        screen.sala.openTheListedSceneRehearsal('ensaio-da-cena-0');
        await screen.until(
          () =>
              screen.state.scene.rehearsal?.n == 0 &&
              !screen.state.scene.waiting,
        );
        await screen.listens();
        await screen.tap(_translateAgainBar(1));
        screen.room
          ..frasesLandBeforeTheyFail = true
          ..sceneAnswersFirst.add(const NetworkFailed('timeout'));
        await screen.tellsTheFrase();
        screen.room.frasesLandBeforeTheyFail = false;
        screen.sala.openTheListedSceneRehearsal(_rehearsalId);
        await screen.until(
          () =>
              screen.state.scene.rehearsal?.n == 1 &&
              !screen.state.scene.waiting,
        );
        await screen.beat(500);

        await screen.tap(_terminei);
        await screen.until(() => screen.room.scenesSent.isNotEmpty);

        expect(
          screen.state.scene.rehearsal!.currentFrases[2].fraseId,
          screen.room.sceneRehearsals
              .singleWhere((rehearsal) => rehearsal.rehearsalId == _rehearsalId)
              .currentFrases[2]
              .fraseId,
        );
        await screen.beat(2000);
      },
    );

    for (final bar in [2, 3]) {
      testWidgets(
        'and the list read too: a tap on bar $bar keeps it unknown, and «terminei» reads the list first',
        (tester) async {
          final screen = await nothingIsKnown(tester);
          await screen.tap(_translateAgainBar(bar));

          await theSceneGoesAsShown(screen);
        },
      );
    }

    testWidgets(
      'and the list read too: another rehearsal opened and this one opened again keeps it unknown, and «terminei» reads the list first',
      (tester) async {
        final screen = await nothingIsKnown(
          tester,
          alsoListed: [
            _rehearsal(n: 0, frases: [_frase('g1', 0, 3000)]),
          ],
        );
        for (final n in [0, 1]) {
          screen.sala.openTheListedSceneRehearsal('ensaio-da-cena-$n');
          await screen.until(
            () =>
                screen.state.scene.rehearsal?.n == n &&
                !screen.state.scene.waiting,
          );
          await screen.beat(500);
        }

        await theSceneGoesAsShown(screen);
      },
    );
  });

  testWidgets(
    '«terminei» goes on when the list shows the held translation again was kept',
    (tester) async {
      final screen = await _aBarTapped(tester, 3);
      screen.room.sceneAnswersFirst.add(
        const Refused(RefusalCode.sceneRehearsalSending),
      );
      await screen.tellsTheFrase();
      screen.room
        ..frasesLandBeforeTheyFail = true
        ..sceneAnswersFirst.add(const NetworkFailed('timeout'));

      await screen.tap(_terminei);
      await screen.until(() => screen.room.scenesSent.isNotEmpty);

      expect(screen.room.scenesSent, hasLength(1));
      expect(byLabel(_notUnderstood), findsNothing);
      await screen.beat(2000);
    },
  );

  group('a refusal of the frase lets it go with her line', () {
    for (final code in [
      RefusalCode.unknownReference,
      RefusalCode.tooLarge,
      RefusalCode.unnamed(413),
      RefusalCode.unnamed(422),
      RefusalCode.unreadable,
    ]) {
      testWidgets('a new frase: $code', (tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room.sceneAnswersFirst.add(Refused(code));
        await screen.tellsTheFrase();

        expect(screen.shows(_notUnderstood), isTrue);
        await screen.theFraseMicrophoneOpens();
        expect(screen.room.frasesKept, hasLength(1));
      });

      testWidgets('a translation again: $code', (tester) async {
        final screen = await _aBarTapped(tester, 2);
        screen.room.sceneAnswersFirst.add(Refused(code));
        await screen.tellsTheFrase();

        expect(screen.shows(_notUnderstood), isTrue);
        await screen.theFraseMicrophoneOpens();
        expect(screen.room.frasesKept, hasLength(1));
      });
    }

    testWidgets(
      'SCENE_REHEARSAL_SENDING keeps it held, and the circle sends it again',
      (tester) async {
        final screen = await _aPausaAfterFrase1(tester);
        screen.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.sceneRehearsalSending),
        );
        await screen.tellsTheFrase();

        expect(byLabel(_notUnderstood), findsNothing);
        await screen.tap(_tell);
        await screen.until(() => screen.room.frasesKept.length > 1);
        final [first, second] = screen.room.frasesKept;
        expect(second.audio, first.audio);
        expect(screen.state.channel, isNot(isA<Microphone>()));
      },
    );
  });

  group('the send-off', () {
    testWidgets(
      'terminei shows «enviando…», plays the acknowledgement, then her line, closes after about 1.4 s and the reply plays on the session screen',
      (tester) async {
        final (screen, saidBefore) = await _sendingTheScene(tester);

        expect(
          find.text(_sending),
          findsNWidgets(2),
          reason:
              'o botão e a linha ao lado do play dizem «enviando…», como no dela',
        );
        expect(
          screen.harness.voice.fixedLines
              .skip(saidBefore)
              .map((line) => line.$1),
          contains(isIn(instantAckLines)),
        );

        final replies = screen.replies;
        await _theVoiceAnswers(screen);
        expect(byLabel(_wentToTheVoice), findsOneWidget);
        expect(find.text(_sending), findsNothing);
        expect(byLabel(_sending), findsNothing);
        expect(byLabel(_terminei), findsNothing);
        await screen.until(() => screen.replies > replies);
        await screen.beat(1300);
        expect(screen.state.stage, SalaStage.cena);
        await screen.beat(200);
        expect(screen.state.stage, SalaStage.conversa);
        expect(screen.replies, replies + 1);
      },
    );

    testWidgets('after the scene reply, «Ouvir de novo» plays it again', (
      tester,
    ) async {
      final (screen, _) = await _sendingTheScene(tester);
      final replies = screen.replies;
      await _theVoiceAnswers(screen);
      await screen.until(
        () =>
            screen.replies > replies &&
            screen.state.stage == SalaStage.conversa &&
            screen.state.voice == VoiceState.invite,
      );
      expect(screen.state.canHearAgain, isTrue);

      await screen.tap('Ouvir de novo');
      await screen.until(() => screen.replies > replies + 1);

      expect(screen.replies, replies + 2);
    });

    testWidgets('nothing on the scene screen answers a tap during the 1.4 s', (
      tester,
    ) async {
      final (screen, _) = await _sendingTheScene(tester);
      await _theVoiceAnswers(screen);
      final played = screen.harness.playback.played.length;
      final fetched = screen.harness.room.clipsFetched.length;

      screen.sala
        ..leaveTheSceneRehearsal()
        ..recordTheSceneAgain()
        ..translateTheFraseAgain('f1')
        ..hearTheFraseTranslation('f1')
        ..tapTheTranslateCircle();
      await screen.beat(500);

      expect(screen.state.stage, SalaStage.cena);
      expect(screen.state.scene.step, SceneStep.translate);
      expect(screen.state.channel, isNot(isA<Microphone>()));
      expect(screen.harness.playback.played, hasLength(played));
      expect(screen.harness.room.clipsFetched, hasLength(fetched));
      await screen.beat(1000);
      expect(screen.state.stage, SalaStage.conversa);
    });
  });
}
