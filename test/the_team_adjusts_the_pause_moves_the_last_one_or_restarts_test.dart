import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';
const _attempt = '1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b';

const _translate = 'traduzir o ensaio da cena';
const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _playPause = 'Tocar ou pausar a gravação';
const _earlier = 'um pouco antes';
const _hearThePause = 'ouvir a pausa';
const _later = 'um pouco depois';
const _pausaAtTheTap =
    'a pausa ficou no toque — toquem no círculo para traduzir';
const _keepTheEarlier = 'manter a tradução de antes';
const _notUnderstood = 'não entendi — traduzam de novo esse pedaço';
const _onlyOnTheLast =
    'a pausa só se move na última frase — as frases mudaram; toquem na barra '
    'de novo';
const _pastTheEnd = 'a pausa nova passa do fim da gravação — um pouco antes';
const _cannotStandThere =
    'a pausa não pode ficar aí — a frase foi atualizada; toquem na barra de '
    'novo';
const _listenMode =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase para '
    'ouvir o ensaio naquela parte, e no alto-falante para ouvir a tradução de '
    'vocês.';
const _terminei = 'terminei';
const _recordAgain = 'gravar o ensaio da cena de novo';
const _restart = 'recomeçar a tradução';
const _restarted = 'tradução recomeçada — o ensaio da cena ficou';
const _restartFailed = 'não deu para recomeçar agora — tentem de novo';

String _bar(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';
String _lastFraseLine(int n) =>
    'traduzindo de novo a frase $n — se precisar, movam a pausa; depois '
    'toquem no círculo';
String _earlierFraseLine(int n) =>
    'traduzindo de novo a frase $n — toquem no círculo (a pausa só se move na '
    'última frase; para mudar uma pausa anterior, recomeçar a tradução)';
String _armed(int n) => 'toque de novo para apagar as $n frases traduzidas';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal(List<SceneFrase> frases, {String? sentAt}) =>
    SceneRehearsalRecord(
      rehearsalId: 'ensaio-da-cena-1',
      sessionId: _session,
      n: 1,
      afterRestart: _attempt,
      sentAt: sentAt,
      frases: frases,
    );

final _twoFrases = _rehearsal([
  _frase('f1', 0, 4000),
  _frase('f2', 4000, 9000),
]);

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

final _anM4aTake = Uint8List.fromList(List.filled(4000, 7));

final class _Screen {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Screen(this.tester, this.harness, this.container);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  FakePlayback get playback => harness.playback;

  Future<void> beat([int ms = 300]) => tester.pump(Duration(milliseconds: ms));

  Future<void> until(bool Function() done) => pumpUntil(tester, done);

  Future<void> tap(String label) async {
    await tester.tap(byLabel(label));
    await beat();
  }

  bool shows(String words) => byLabel(words).evaluate().isNotEmpty;

  bool lit(String words) => byLabel(words).evaluate().any(
    (element) => (element.widget as Semantics).properties.enabled ?? false,
  );

  bool faded(String words) => tester
      .widgetList<Opacity>(
        find.descendant(of: byLabel(words), matching: find.byType(Opacity)),
      )
      .any((opacity) => opacity.opacity < 1);

  int asked(String call) => room.calls.where((asked) => asked == call).length;

  bool get theFraseMicrophoneIsOpen => switch (state.channel) {
    Microphone(owner: MicOwner.frase) => true,
    _ => false,
  };

  Future<void> listens() async {
    await tap(_translate);
    await until(() => state.channel is PartPlaying);
    await beat(100);
  }

  /// The circle tapped while the take plays at [at].
  Future<void> marksThePausaAt(double at) async {
    playback.at = _s(at);
    await tap(_tell);
  }

  /// The circle that opens the frase microphone and the circle that stops it, then the
  /// room's answer.
  Future<void> tellsTheFrase() async {
    final posts = room.frasesKept.length;
    await tap(_tell);
    await until(() => theFraseMicrophoneIsOpen);
    await tap(_tell);
    await until(() => room.frasesKept.length > posts && !state.scene.waiting);
    await beat(500);
  }
}

Future<_Screen> _onScreen(
  WidgetTester tester, {
  Uint8List? take,
  Duration length = const Duration(seconds: 10),
  List<(Duration, Duration)> gaps = const [],
  required SceneRehearsalRecord rehearsal,
}) async {
  final (harness, container) = await translateOnScreen(
    tester,
    take: take ?? aSpokenWav(length: length, gaps: gaps),
    length: length,
    rehearsal: rehearsal,
  );
  return _Screen(tester, harness, container);
}

/// A take of [length] listened to over [rehearsal], with the pausa marked at [at].
Future<_Screen> _aPausaAt(
  WidgetTester tester,
  double at, {
  Uint8List? take,
  Duration length = const Duration(seconds: 10),
  List<(Duration, Duration)> gaps = const [],
  List<SceneFrase> frases = const [],
}) async {
  final screen = await _onScreen(
    tester,
    take: take,
    length: length,
    gaps: gaps,
    rehearsal: _rehearsal(frases),
  );
  await screen.listens();
  await screen.marksThePausaAt(at);
  return screen;
}

/// Frases 1 and 2 on a 20 s take with a silence at 10 s, listened to, and frase 2's bar
/// tapped.
Future<_Screen> _theLastBarTapped(WidgetTester tester) async {
  final screen = await _onScreen(
    tester,
    length: const Duration(seconds: 20),
    gaps: [(_s(9.9), _s(10.1))],
    rehearsal: _twoFrases,
  );
  await screen.listens();
  await screen.tap(_bar(2));
  return screen;
}

/// Frase 2's pause moved to the silence at 10 s and told, the room answering [code],
/// while a second tablet appended a frase from 9 s to 11 s.
Future<_Screen> _aMoveRefused(WidgetTester tester, String code) async {
  final screen = await _theLastBarTapped(tester);
  await screen.tap(_later);
  screen.room
    ..sceneAnswersFirst.add(Refused(code))
    ..sceneRehearsals[0] = _rehearsal([
      ..._twoFrases.frases,
      _frase('f3', 9000, 11000),
    ]);
  await screen.tellsTheFrase();
  return screen;
}

void main() {
  group('the adjust row', () {
    testWidgets(
      'a marked pausa shows her three buttons, and «ouvir a pausa» plays the 1.5 s before it and stops there',
      (tester) async {
        final screen = await _aPausaAt(tester, 5.0);

        expect(screen.shows(_earlier), isTrue);
        expect(screen.shows(_hearThePause), isTrue);
        expect(screen.shows(_later), isTrue);
        await screen.tap(_hearThePause);
        expect(screen.playback.ranges.last, '3500-5000');
      },
    );

    for (final (language, words) in [
      ('pt', [_earlier, _hearThePause, _later]),
      ('en', ['a little earlier', 'hear the pause', 'a little later']),
    ]) {
      testWidgets(
        '$language: a marked pausa writes her three buttons in her words, and each is called by what it says',
        (tester) async {
          final screen = await _aPausaAt(tester, 5.0);
          screen.container.read(roomLanguageProvider.notifier).choose(language);
          await screen.beat();

          for (final word in words) {
            expect(
              find.descendant(of: byLabel(word), matching: find.text(word)),
              findsOneWidget,
              reason:
                  'o botão era um ícone, e a palavra dela só o leitor de tela dizia',
            );
          }
        },
      );
    }

    testWidgets('«ouvir a pausa» never starts before the previous pause', (
      tester,
    ) async {
      final screen = await _aPausaAt(
        tester,
        4.6,
        frases: [_frase('f1', 0, 4000)],
      );

      await screen.tap(_hearThePause);

      expect(screen.playback.ranges.last, '4000-4600');
    });

    testWidgets(
      '«um pouco depois» with a silence 1 s later moves the pausa to that silence',
      (tester) async {
        final screen = await _aPausaAt(tester, 5.0, gaps: [(_s(5.9), _s(6.1))]);

        await screen.tap(_later);
        await screen.tellsTheFrase();

        expect(screen.room.frasesKept.single.endsMs, 6000);
      },
    );

    testWidgets(
      '«um pouco depois» with no silence within 1.5 s moves the pausa 0.4 s',
      (tester) async {
        final screen = await _aPausaAt(tester, 5.0);

        await screen.tap(_later);
        await screen.tellsTheFrase();

        expect(screen.room.frasesKept.single.endsMs, 5400);
      },
    );

    testWidgets(
      '«um pouco antes» never brings the pausa within 0.2 s of the previous pause',
      (tester) async {
        final screen = await _aPausaAt(
          tester,
          4.3,
          frases: [_frase('f1', 0, 4000)],
        );

        await screen.tap(_earlier);
        await screen.tap(_earlier);
        await screen.tellsTheFrase();

        expect(screen.room.frasesKept.single.endsMs, 4200);
      },
    );

    testWidgets(
      '«um pouco depois» never brings the pausa within 0.1 s of the end',
      (tester) async {
        final screen = await _aPausaAt(tester, 9.7);

        await screen.tap(_later);
        await screen.tellsTheFrase();

        expect(screen.room.frasesKept.single.endsMs, 9900);
      },
    );

    testWidgets(
      'play with a pausa pending drops it and the take plays on from it',
      (tester) async {
        final screen = await _aPausaAt(tester, 5.0);

        await screen.tap(_playPause);

        expect(screen.playback.playedFrom.last, _s(5.0));
        expect(screen.shows(_earlier), isFalse);
      },
    );

    testWidgets(
      'play while «ouvir a pausa» sounds only stops it, and the pausa stays',
      (tester) async {
        final screen = await _aPausaAt(tester, 5.0);
        await screen.tap(_hearThePause);
        screen.playback.at = _s(4.0);

        await screen.tap(_playPause);

        expect(screen.playback.sounding, isFalse);
        expect(screen.shows(_earlier), isTrue);
        await screen.tellsTheFrase();
        expect(screen.room.frasesKept.single.endsMs, 5000);
      },
    );

    testWidgets('a take kept as m4a shows no adjust row', (tester) async {
      final screen = await _aPausaAt(tester, 5.0, take: _anM4aTake);

      expect(screen.shows('$_pausaAtTheTap — 0:05 / 0:10'), isTrue);
      expect(screen.shows(_earlier), isFalse);
    });
  });

  group('the last bar', () {
    testWidgets(
      'tapping the last bar opens the row at its end with the last-frase line',
      (tester) async {
        final screen = await _theLastBarTapped(tester);

        expect(screen.playback.ranges.last, '4000-9000');
        expect(screen.shows(_lastFraseLine(2)), isTrue);
        expect(screen.shows(_earlier), isTrue);
        expect(screen.shows(_hearThePause), isTrue);
        expect(screen.shows(_later), isTrue);
        expect(screen.shows(_keepTheEarlier), isTrue);
      },
    );

    testWidgets(
      'under the circle «manter a tradução de antes» comes before her line, not after it',
      (tester) async {
        await _theLastBarTapped(tester);
        double top(String label) => tester.getTopLeft(byLabel(label)).dy;

        expect(top(_tell), lessThan(top(_keepTheEarlier)));
        expect(
          top(_keepTheEarlier),
          lessThan(top(_lastFraseLine(2))),
          reason: '«manter» vinha depois da linha dela',
        );
      },
    );

    testWidgets(
      'moving the last pause later and saving changes the frase\'s span and the take goes on from the new end',
      (tester) async {
        final screen = await _theLastBarTapped(tester);

        await screen.tap(_later);
        await screen.tap(_tell);
        await screen.until(() => screen.theFraseMicrophoneIsOpen);
        expect(screen.theFraseMicrophoneIsOpen, isTrue);
        await screen.tap(_tell);
        await screen.until(() => screen.room.frasesKept.isNotEmpty);
        await screen.beat(500);

        final sent = screen.room.frasesKept.single;
        expect(
          (sent.startsMs, sent.endsMs, sent.replaces),
          (4000, 10000, 'f2'),
        );
        expect(screen.playback.playedFrom.last, _s(10.0));
        expect(screen.shows(_bar(1)), isTrue);
        expect(screen.shows(_bar(2)), isTrue);
        expect(screen.shows(_bar(3)), isFalse);
      },
    );

    testWidgets(
      '«um pouco depois» never moves a pause standing at the take\'s end earlier',
      (tester) async {
        final screen = await _onScreen(
          tester,
          rehearsal: _rehearsal([
            _frase('f1', 0, 4000),
            _frase('f2', 4000, 10000),
          ]),
        );
        await screen.listens();
        await screen.tap(_bar(2));

        await screen.tap(_later);
        await screen.tellsTheFrase();

        expect(screen.room.frasesKept.single.endsMs, 10000);
      },
    );

    testWidgets(
      'a moved pause the room kept but whose answer was lost goes on from its new end once the list shows it',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        await screen.tap(_later);
        screen.room
          ..frasesLandBeforeTheyFail = true
          ..sceneAnswersFirst.add(const NetworkFailed('sem rede'));

        await screen.tellsTheFrase();
        await screen.beat(1000);

        expect(screen.playback.playedFrom.last, _s(10.0));
      },
    );

    testWidgets('«manter a tradução de antes» drops the move', (tester) async {
      final screen = await _theLastBarTapped(tester);
      await screen.tap(_later);

      await screen.tap(_keepTheEarlier);

      expect(screen.shows(_earlier), isFalse);
      expect(screen.shows(_lastFraseLine(2)), isFalse);
      await screen.tap(_tell);
      expect(screen.theFraseMicrophoneIsOpen, isFalse);
      expect(screen.room.frasesKept, isEmpty);
      expect(screen.playback.playedFrom.last, _s(9.0));
    });

    testWidgets(
      'the last frase translated again without moving its pause stays paused after saving',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        final plays = screen.playback.playedFrom.length;

        await screen.tellsTheFrase();

        final sent = screen.room.frasesKept.single;
        expect((sent.startsMs, sent.endsMs, sent.replaces), (4000, 9000, 'f2'));
        expect(screen.playback.playedFrom, hasLength(plays));
      },
    );

    testWidgets(
      'play during the last frase\'s move plays the take on from the moved pause, and the move, its line and «manter» stay',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        await screen.tap(_later);

        await screen.tap(_playPause);

        expect(
          screen.playback.playedFrom.last,
          _s(10.0),
          reason: 'o play largava a frase e seguia de onde a tradução parou',
        );
        expect(screen.state.channel, isA<PartPlaying>());
        expect(screen.shows(_earlier), isTrue);
        expect(screen.shows(_lastFraseLine(2)), isTrue);
        expect(screen.shows(_keepTheEarlier), isTrue);
        await screen.tellsTheFrase();
        final sent = screen.room.frasesKept.single;
        expect(
          (sent.startsMs, sent.endsMs, sent.replaces),
          (4000, 10000, 'f2'),
        );
      },
    );

    testWidgets(
      'play while the last frase plays on the move only pauses it, and the move and its line stay',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        final plays = screen.playback.playedFrom.length;

        await screen.tap(_playPause);

        expect(
          screen.playback.sounding,
          isFalse,
          reason: 'o play tocava de novo em vez de só pausar',
        );
        expect(screen.playback.playedFrom, hasLength(plays));
        expect(screen.state.scene.pausa, _s(9.0));
        expect(screen.shows(_earlier), isTrue);
        expect(screen.shows(_lastFraseLine(2)), isTrue);
        expect(screen.shows(_keepTheEarlier), isTrue);
      },
    );

    testWidgets(
      'play with the last frase\'s pause on the move at the take\'s end plays «ouvir a pausa»',
      (tester) async {
        final screen = await _onScreen(
          tester,
          rehearsal: _rehearsal([
            _frase('f1', 0, 4000),
            _frase('f2', 4000, 10000),
          ]),
        );
        await screen.listens();
        await screen.tap(_bar(2));
        screen.playback.finishPlayback();
        await screen.beat();
        final plays = screen.playback.playedFrom.length;

        await screen.tap(_playPause);

        expect(
          screen.playback.ranges.last,
          '8500-10000',
          reason: 'o play tocava do fim da gravação e não se ouvia nada',
        );
        expect(screen.playback.playedFrom, hasLength(plays));
        expect(screen.shows(_lastFraseLine(2)), isTrue);
      },
    );

    testWidgets(
      'play with the last frase\'s pause on the move 30 ms before the take\'s end plays «ouvir a pausa», not the 30 ms after it',
      (tester) async {
        final screen = await _onScreen(
          tester,
          rehearsal: _rehearsal([
            _frase('f1', 0, 4000),
            _frase('f2', 4000, 9970),
          ]),
        );
        await screen.listens();
        await screen.tap(_bar(2));
        screen.playback.finishPlayback();
        await screen.beat();
        final plays = screen.playback.playedFrom.length;

        await screen.tap(_playPause);

        expect(
          screen.playback.ranges.last,
          '8470-9970',
          reason: 'o play tocava os 30 ms depois da pausa e calava na hora',
        );
        expect(screen.playback.playedFrom, hasLength(plays));
      },
    );

    testWidgets(
      'a failed restart\'s line stays when play hears the moving pause at the take\'s end, as it stays anywhere earlier',
      (tester) async {
        final screen = await _onScreen(
          tester,
          rehearsal: _rehearsal([
            _frase('f1', 0, 4000),
            _frase('f2', 4000, 10000),
          ]),
        );
        await screen.listens();
        await screen.tap(_bar(2));
        screen.playback.finishPlayback();
        await screen.beat();
        await screen.tap(_restart);
        await screen.beat(700);
        screen.room.failSceneWith = const NetworkFailed('sem rede');
        await screen.tap(_armed(2));
        await screen.until(() => screen.shows(_restartFailed));
        expect(screen.shows(_lastFraseLine(2)), isTrue);

        await screen.tap(_playPause);

        expect(screen.playback.ranges.last, '8500-10000');
        expect(
          screen.shows(_restartFailed),
          isTrue,
          reason: 'o play no fim da gravação apagava a linha do recomeço',
        );
        expect(screen.shows(_lastFraseLine(2)), isTrue);
        await screen.beat(6000);
      },
    );

    testWidgets(
      'a moved pause waiting to be sent again cannot be moved or heard, and the circle sends it at its end',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        await screen.tap(_later);
        screen.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.sceneRehearsalSending),
        );
        await screen.tellsTheFrase();
        final heard = screen.playback.ranges.length;

        await screen.tap(_later);
        await screen.tap(_hearThePause);

        expect(screen.playback.ranges, hasLength(heard));
        await screen.tap(_tell);
        await screen.until(() => screen.room.frasesKept.length > 1);
        expect(screen.room.frasesKept.last.endsMs, 10000);
      },
    );

    testWidgets(
      'a moved pause survives a list read while its frase is still the last one',
      (tester) async {
        final screen = await _onScreen(
          tester,
          length: const Duration(seconds: 20),
          rehearsal: _twoFrases,
        );
        await screen.listens();
        await screen.marksThePausaAt(12.0);
        screen.room
          ..sceneAnswersFirst.add(const Refused(RefusalCode.notFound))
          ..holdNextSceneList();
        await screen.tellsTheFrase();
        await screen.tap(_bar(2));
        await screen.tap(_earlier);

        screen.room.finishHeldSceneList();
        await screen.beat(500);
        await screen.tellsTheFrase();

        final sent = screen.room.frasesKept.last;
        expect((sent.startsMs, sent.endsMs, sent.replaces), (4000, 8600, 'f2'));
      },
    );
  });

  group('an earlier bar', () {
    testWidgets(
      'tapping the second of four bars says the earlier-bar line and shows no adjust row',
      (tester) async {
        final screen = await _onScreen(
          tester,
          length: const Duration(seconds: 20),
          rehearsal: _rehearsal([
            _frase('f1', 0, 3000),
            _frase('f2', 3000, 6000),
            _frase('f3', 6000, 9000),
            _frase('f4', 9000, 12000),
          ]),
        );
        await screen.listens();

        await screen.tap(_bar(2));

        expect(screen.shows(_earlierFraseLine(2)), isTrue);
        expect(screen.shows(_earlier), isFalse);
        await screen.tellsTheFrase();
        final sent = screen.room.frasesKept.single;
        expect((sent.startsMs, sent.endsMs, sent.replaces), (3000, 6000, 'f2'));
      },
    );
  });

  group('a refused move', () {
    testWidgets(
      'a move refused because a second tablet appended a frase drops the move, reads the frases again and says why',
      (tester) async {
        final screen = await _theLastBarTapped(tester);
        await screen.tap(_later);
        final reads = screen.asked('sceneRehearsalsOf');
        screen.room
          ..sceneAnswersFirst.add(
            const Refused(RefusalCode.pauseOnlyOnTheLastFrase),
          )
          ..sceneRehearsals[0] = _rehearsal([
            ..._twoFrases.frases,
            _frase('f3', 9000, 11000),
          ]);

        await screen.tellsTheFrase();

        expect(screen.shows(_onlyOnTheLast), isTrue);
        expect(screen.shows(_notUnderstood), isFalse);
        expect(screen.asked('sceneRehearsalsOf'), reads + 1);
        expect(screen.shows(_bar(3)), isTrue);
        expect(screen.shows(_earlier), isFalse);
        expect(screen.shows(_keepTheEarlier), isFalse);
        expect(screen.state.needsPerson, isFalse);
      },
    );

    testWidgets(
      'a move past the end says «a pausa nova passa do fim da gravação — um pouco antes»',
      (tester) async {
        final screen = await _aMoveRefused(tester, RefusalCode.pausePastTheEnd);

        expect(screen.shows(_pastTheEnd), isTrue);
      },
    );

    testWidgets(
      'a move on a frase updated since says «a pausa não pode ficar aí — a frase foi atualizada; toquem na barra de novo»',
      (tester) async {
        final screen = await _aMoveRefused(
          tester,
          RefusalCode.pauseCannotStandThere,
        );

        expect(screen.shows(_cannotStandThere), isTrue);
      },
    );

    testWidgets('a refusal line clears at the next gesture', (tester) async {
      final screen = await _aMoveRefused(
        tester,
        RefusalCode.pauseOnlyOnTheLastFrase,
      );

      await screen.tap(_bar(3));

      expect(screen.shows(_onlyOnTheLast), isFalse);
      expect(screen.shows(_lastFraseLine(3)), isTrue);
    });

    testWidgets('«terminei» clears a refusal line', (tester) async {
      final screen = await _aMoveRefused(
        tester,
        RefusalCode.pauseOnlyOnTheLastFrase,
      );
      screen.room.holdNextTurn();

      await screen.tap(_terminei);

      expect(screen.shows(_onlyOnTheLast), isFalse);
      screen.room.finishHeldTurn();
      await screen.beat(2000);
    });
  });

  group('«terminei» with a moved pause waiting to be sent again', () {
    for (final (code, line) in [
      (RefusalCode.pauseOnlyOnTheLastFrase, _onlyOnTheLast),
      (RefusalCode.pausePastTheEnd, _pastTheEnd),
      (RefusalCode.pauseCannotStandThere, _cannotStandThere),
    ]) {
      testWidgets(
        '$code: nothing is sent and her line stands; a second «terminei» sends without the move',
        (tester) async {
          final screen = await _theLastBarTapped(tester);
          await screen.tap(_later);
          screen.room.sceneAnswersFirst.add(
            const Refused(RefusalCode.sceneRehearsalSending),
          );
          await screen.tellsTheFrase();
          screen.room.sceneAnswersFirst.add(Refused(code));

          await screen.tap(_terminei);
          await screen.until(() => screen.room.frasesKept.length > 1);
          await screen.beat(1000);

          expect(screen.room.scenesSent, isEmpty);
          expect(screen.shows(line), isTrue);
          screen.room.holdNextTurn();
          await screen.tap(_terminei);
          await screen.until(() => screen.room.scenesSent.isNotEmpty);
          expect(screen.room.frasesKept, hasLength(2));
          expect(
            screen.room.sceneRehearsals.single.currentFrases.last.endsMs,
            9000,
          );
          screen.room.finishHeldTurn();
          await screen.beat(2000);
        },
      );
    }
  });

  group('«recomeçar a tradução»', () {
    testWidgets(
      'the first tap arms «recomeçar a tradução» with the count, and it disarms after 6 s',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);

        await screen.tap(_restart);

        expect(screen.shows(_armed(2)), isTrue);
        expect(screen.room.restartsSent, isEmpty);
        await screen.beat(6000);
        expect(screen.shows(_restart), isTrue);
        expect(screen.shows(_armed(2)), isFalse);
        expect(screen.room.restartsSent, isEmpty);
      },
    );

    testWidgets(
      'two taps clear the frases from the screen, keep the recording and say so for 6 s',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);
        await screen.listens();

        await screen.tap(_restart);
        await screen.beat(700);
        await screen.tap(_armed(2));
        await screen.until(() => screen.shows(_restarted));

        expect(screen.room.restartsSent.single.closes, _attempt);
        expect(screen.shows(_bar(1)), isFalse);
        expect(screen.shows(_restarted), isTrue);
        expect(screen.lit(_translate), isTrue);
        expect(File(screen.state.scene.take!).existsSync(), isTrue);
        await screen.beat(6000);
        expect(screen.shows(_restarted), isFalse);
      },
    );

    testWidgets(
      'the restart\'s line sits under the circle, above the frases told and «terminei», not under «recomeçar»',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);
        await screen.tap(_restart);
        await screen.beat(700);
        screen.room.failSceneWith = const NetworkFailed('sem rede');
        await screen.tap(_armed(2));
        await screen.until(() => screen.shows(_restartFailed));
        double top(String label) => tester.getTopLeft(byLabel(label)).dy;

        expect(top(_tell), lessThan(top(_restartFailed)));
        expect(
          top(_restartFailed),
          lessThan(top('frases traduzidas')),
          reason:
              'a linha dela ficava embaixo de «recomeçar», depois das frases',
        );
        expect(top(_restartFailed), lessThan(top(_terminei)));
      },
    );

    testWidgets(
      'an armed «recomeçar» is drawn out and cannot be tapped for its 600 ms, then wakes',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);

        await screen.tap(_restart);

        expect(
          screen.lit(_armed(2)),
          isFalse,
          reason: '«recomeçar» parecia aceso nos 600 ms e ignorava o toque',
        );
        expect(screen.faded(_armed(2)), isTrue);
        await screen.beat(400);
        expect(screen.lit(_armed(2)), isTrue);
        expect(screen.faded(_armed(2)), isFalse);
        await screen.beat(6000);
      },
    );

    testWidgets('a double tap only arms', (tester) async {
      final screen = await _onScreen(tester, rehearsal: _twoFrases);

      await tester.tap(byLabel(_restart));
      await screen.beat(100);
      await tester.tap(byLabel(_armed(2)));
      await screen.beat();

      expect(screen.room.restartsSent, isEmpty);
      expect(screen.shows(_armed(2)), isTrue);
      await screen.beat(6000);
    });

    testWidgets(
      'a restart the room refuses says «não deu para recomeçar agora — tentem de novo»',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);
        await screen.tap(_restart);
        await screen.beat(700);
        screen.room.failSceneWith = const NetworkFailed('sem rede');

        await screen.tap(_armed(2));
        await screen.until(() => screen.shows(_restartFailed));

        expect(screen.shows(_restartFailed), isTrue);
        expect(screen.shows(_bar(1)), isTrue);
      },
    );

    testWidgets(
      'on places unknown, a restart the room refuses writes «não deu para recomeçar agora — tentem de novo», as on the translate step',
      (tester) async {
        final screen = await _onScreen(
          tester,
          rehearsal: _rehearsal([_frase('f1', 0, 12000)]),
        );
        expect(screen.state.scene.step, SceneStep.placesUnknown);
        await screen.tap(_restart);
        await screen.beat(700);
        screen.room.failSceneWith = const NetworkFailed('sem rede');

        await screen.tap(_armed(1));
        await screen.until(() => screen.shows(_restartFailed));

        expect(screen.shows(_restartFailed), isTrue);
        expect(
          find.text(_restartFailed),
          findsOneWidget,
          reason: 'a linha dela só chegava ao VoiceOver nesta tela',
        );
      },
    );

    testWidgets('a sent rehearsal shows no «recomeçar a tradução»', (
      tester,
    ) async {
      final screen = await _onScreen(
        tester,
        rehearsal: _rehearsal(
          _twoFrases.frases,
          sentAt: '2026-10-14T10:00:00Z',
        ),
      );
      screen.container
          .read(salaSessionProvider.notifier)
          .openTheListedSceneRehearsal('ensaio-da-cena-1');
      await screen.until(() => screen.state.scene.step == SceneStep.sent);

      expect(screen.shows(_listenMode), isTrue);
      expect(screen.shows(_restart), isFalse);
    });

    testWidgets('a rehearsal with no frase shows no «recomeçar a tradução»', (
      tester,
    ) async {
      final screen = await _onScreen(tester, rehearsal: _rehearsal(const []));

      expect(screen.shows(_translate), isTrue);
      expect(screen.shows(_restart), isFalse);
    });
  });

  group('before the team listens', () {
    testWidgets(
      'play is lit and plays the take from where the translation stopped, not only «traduzir»',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);

        expect(
          screen.lit(_playPause),
          isTrue,
          reason: 'o play ficava apagado até «traduzir o ensaio da cena»',
        );
        await screen.tap(_playPause);

        expect(screen.state.channel, isA<PartPlaying>());
        expect(screen.playback.playedFrom.last, _s(9.0));
      },
    );

    testWidgets(
      'the circle is lit and plays the take from where the translation stopped, opening no microphone',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);

        expect(
          tester.widget<Semantics>(byLabel(_tell)).properties.enabled,
          isNot(isFalse),
          reason: 'o círculo ficava apagado até «traduzir o ensaio da cena»',
        );
        await screen.tap(_tell);

        expect(screen.state.channel, isA<PartPlaying>());
        expect(screen.playback.playedFrom.last, _s(9.0));
        expect(screen.theFraseMicrophoneIsOpen, isFalse);
      },
    );
  });

  group('a frase\'s microphone open', () {
    testWidgets(
      '«terminei» and «gravar o ensaio da cena de novo» are drawn out, and «gravar» leaves the microphone open',
      (tester) async {
        final screen = await _onScreen(tester, rehearsal: _twoFrases);
        await screen.listens();
        await screen.marksThePausaAt(9.5);
        await screen.tap(_tell);
        await screen.until(() => screen.theFraseMicrophoneIsOpen);
        expect(screen.theFraseMicrophoneIsOpen, isTrue);

        expect(
          screen.lit(_terminei),
          isFalse,
          reason: '«terminei» parecia aceso com o microfone aberto',
        );
        expect(screen.faded(_terminei), isTrue);
        expect(
          screen.lit(_recordAgain),
          isFalse,
          reason: '«gravar de novo» jogava fora a gravação aberta',
        );
        expect(screen.faded(_recordAgain), isTrue);
        await screen.tap(_recordAgain);
        expect(screen.theFraseMicrophoneIsOpen, isTrue);
        expect(screen.state.scene.step, SceneStep.translate);
      },
    );
  });
}
