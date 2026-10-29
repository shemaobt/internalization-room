import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _translate = 'traduzir o ensaio da cena';
const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _keepTheEarlier = 'manter a tradução de antes';
const _restart = 'recomeçar a tradução';
const _playPause = 'Tocar ou pausar a gravação';
const _terminei = 'terminei';
const _sending = 'enviando a tradução do ensaio da cena para a voz…';
const _recordAgain = 'gravar o ensaio da cena de novo';
const _pauseRow = ['um pouco antes', 'ouvir a pausa', 'um pouco depois'];

String _bar(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';
String _hearMine(int n) => 'ouvir a minha tradução da frase $n';

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

enum _Refusal { waiting, sending, microphone, person }

final _twoFrases = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: 'sessao-1',
  n: 1,
  frases: const [
    SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
    SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 9000),
  ],
);

Future<(SalaHarness, ProviderContainer)> _theLastFraseTranslatedAgain(
  WidgetTester tester,
) async {
  final (harness, container) = await translateOnScreen(
    tester,
    take: aSpokenWav(
      length: const Duration(seconds: 20),
      gaps: [(_s(9.9), _s(10.1))],
    ),
    length: const Duration(seconds: 20),
    rehearsal: _twoFrases,
  );
  await tester.tap(byLabel(_translate));
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).channel is PartPlaying,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(byLabel(_bar(2)));
  await tester.pump(const Duration(milliseconds: 300));
  return (harness, container);
}

Future<void> _aFraseHeldToBeSentAgain(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.sceneAnswersFirst.add(
    const Refused(RefusalCode.sceneRehearsalSending),
  );
  await tester.tap(byLabel(_tell));
  await pumpUntil(
    tester,
    () => switch (container.read(salaSessionProvider).channel) {
      Microphone(owner: MicOwner.frase) => true,
      _ => false,
    },
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(byLabel(_tell));
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntil(
    tester,
    () => !container.read(salaSessionProvider).scene.waiting,
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(container.read(salaSessionProvider).scene.waiting, isFalse);
  expect(container.read(salaSessionProvider).channel, isNot(isA<Microphone>()));
}

bool _lit(WidgetTester tester, String words) => byLabel(words).evaluate().any(
  (element) => (element.widget as Semantics).properties.enabled ?? false,
);

Future<void> _under(
  WidgetTester tester,
  ProviderContainer container,
  _Refusal refusal,
  void Function() look,
) async {
  final sala = container.read(salaSessionProvider.notifier);
  final now = container.read(salaSessionProvider);
  final channel = now.channel;
  sala.state = switch (refusal) {
    _Refusal.waiting => now.copyWith(scene: now.scene.asWaiting),
    _Refusal.sending => now.copyWith(awaitingTheGuide: true),
    _Refusal.microphone => now.copyWith(
      machine: now.machine.copyWith(channel: const Microphone(MicOwner.frase)),
    ),
    _Refusal.person => now.copyWith(
      machine: now.machine.copyWith(halt: const Blocking()),
    ),
  };
  await tester.pump(const Duration(milliseconds: 300));
  look();
  final then = container.read(salaSessionProvider);
  sala.state = switch (refusal) {
    _Refusal.waiting => then.copyWith(
      scene: then.scene.copyWith(waiting: false),
    ),
    _Refusal.sending => then.copyWith(awaitingTheGuide: false),
    _Refusal.microphone => then.copyWith(
      machine: then.machine.copyWith(channel: channel),
    ),
    _Refusal.person => then.copyWith(
      machine: then.machine.copyWith(halt: const NoHalt()),
    ),
  };
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    '«manter a tradução de antes» is drawn out while the screen waits, while «terminei» is in the air and with the microphone open',
    (tester) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      expect(_lit(tester, _keepTheEarlier), isTrue);

      for (final refusal in [
        _Refusal.waiting,
        _Refusal.sending,
        _Refusal.microphone,
      ]) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            _lit(tester, _keepTheEarlier),
            isFalse,
            reason:
                'com ${refusal.name}, o manter ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    },
  );

  testWidgets(
    'the pause row is drawn out while the screen waits, while «terminei» is in the air, with the microphone open and under the person sign',
    (tester) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      for (final words in _pauseRow) {
        expect(_lit(tester, words), isTrue);
      }

      for (final refusal in _Refusal.values) {
        await _under(tester, container, refusal, () {
          for (final words in _pauseRow) {
            expect(
              _lit(tester, words),
              isFalse,
              reason:
                  'com ${refusal.name}, «$words» ficava aceso e o toque não '
                  'fazia nada',
            );
          }
        });
      }
    },
  );

  testWidgets(
    'the pause row is drawn out while a frase the room did not keep waits to be sent again',
    (tester) async {
      final (harness, container) = await _theLastFraseTranslatedAgain(tester);

      await _aFraseHeldToBeSentAgain(tester, harness, container);

      for (final words in _pauseRow) {
        expect(byLabel(words), findsOneWidget);
        expect(
          _lit(tester, words),
          isFalse,
          reason:
              'com uma frase guardada para enviar de novo, «$words» ficava '
              'aceso e o toque não fazia nada',
        );
      }
    },
  );

  testWidgets(
    'the circle is drawn out while the screen waits, while «terminei» is in the air and under the person sign',
    (tester) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      bool? enabled() =>
          tester.widget<Semantics>(byLabel(_tell)).properties.enabled;
      expect(enabled(), isNot(isFalse));

      for (final refusal in [
        _Refusal.waiting,
        _Refusal.sending,
        _Refusal.person,
      ]) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            enabled(),
            isFalse,
            reason:
                'com ${refusal.name}, o círculo ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    },
  );

  testWidgets(
    '«recomeçar a tradução» is drawn out while the screen waits, while «terminei» is in the air, with the microphone open and under the person sign',
    (tester) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      expect(_lit(tester, _restart), isTrue);

      for (final refusal in _Refusal.values) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            _lit(tester, _restart),
            isFalse,
            reason:
                'com ${refusal.name}, o recomeçar ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    },
  );

  testWidgets(
    'each frase\'s bar is drawn out while the screen waits, while «terminei» is in the air, with the microphone open and while a frase waits to be sent again, and its speaker still plays then',
    (tester) async {
      final (harness, container) = await _theLastFraseTranslatedAgain(tester);
      for (final n in [1, 2]) {
        expect(_lit(tester, _bar(n)), isTrue);
      }

      for (final refusal in [
        _Refusal.waiting,
        _Refusal.sending,
        _Refusal.microphone,
      ]) {
        await _under(tester, container, refusal, () {
          for (final n in [1, 2]) {
            expect(
              _lit(tester, _bar(n)),
              isFalse,
              reason:
                  'com ${refusal.name}, a barra da frase $n ficava acesa e o '
                  'toque não fazia nada',
            );
          }
        });
      }
      await _aFraseHeldToBeSentAgain(tester, harness, container);

      for (final n in [1, 2]) {
        expect(
          _lit(tester, _bar(n)),
          isFalse,
          reason:
              'com uma frase guardada para enviar de novo, a barra da frase $n '
              'ficava acesa e o toque não fazia nada',
        );
        expect(
          _lit(tester, _hearMine(n)),
          isTrue,
          reason: 'o alto-falante apagava junto com a barra, e ele ainda toca',
        );
      }
      final played = harness.playback.played.length;
      await tester.tap(byLabel(_hearMine(1)));
      await pumpUntil(tester, () => harness.playback.played.length > played);
      expect(harness.playback.played, hasLength(played + 1));
    },
  );

  testWidgets(
    'once the frase that waited is sent again and kept, each frase\'s bar is lit again',
    (tester) async {
      final (harness, container) = await _theLastFraseTranslatedAgain(tester);
      await _aFraseHeldToBeSentAgain(tester, harness, container);
      expect(_lit(tester, _bar(1)), isFalse);

      await tester.tap(byLabel(_tell));
      await pumpUntil(
        tester,
        () =>
            harness.room.frasesKept.isNotEmpty &&
            !container.read(salaSessionProvider).scene.waiting,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(harness.room.frasesKept, isNotEmpty);
      for (final n in [1, 2]) {
        expect(
          _lit(tester, _bar(n)),
          isTrue,
          reason:
              'a frase guardada já foi, e a barra da frase $n continuava '
              'apagada',
        );
      }
    },
  );

  testWidgets(
    'once «manter a tradução de antes» lets the frase that waited go, each frase\'s bar is lit again',
    (tester) async {
      final (harness, container) = await _theLastFraseTranslatedAgain(tester);
      await _aFraseHeldToBeSentAgain(tester, harness, container);
      expect(_lit(tester, _bar(1)), isFalse);

      await tester.tap(byLabel(_keepTheEarlier));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(salaSessionProvider).scene.translatingAgain,
        isNull,
      );
      for (final n in [1, 2]) {
        expect(
          _lit(tester, _bar(n)),
          isTrue,
          reason:
              'o manter soltou a frase guardada, e a barra da frase $n '
              'continuava apagada',
        );
      }
    },
  );

  for (final (control, refusals) in [
    (_playPause, [_Refusal.waiting, _Refusal.sending, _Refusal.microphone]),
    (_hearMine(1), [_Refusal.waiting, _Refusal.sending, _Refusal.microphone]),
    (_recordAgain, [_Refusal.waiting, _Refusal.sending]),
  ]) {
    testWidgets('«$control» is drawn out under every refusal of its tap', (
      tester,
    ) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      expect(_lit(tester, control), isTrue);

      for (final refusal in refusals) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            _lit(tester, control),
            isFalse,
            reason:
                'com ${refusal.name}, «$control» ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    });
  }

  testWidgets(
    '«terminei» is drawn out while it is in the air, with the microphone open and under the person sign',
    (tester) async {
      final (_, container) = await _theLastFraseTranslatedAgain(tester);
      expect(_lit(tester, _terminei), isTrue);

      for (final (refusal, words) in [
        (_Refusal.sending, _sending),
        (_Refusal.microphone, _terminei),
        (_Refusal.person, _terminei),
      ]) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            _lit(tester, words),
            isFalse,
            reason:
                'com ${refusal.name}, «$words» ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    },
  );

  testWidgets(
    '«traduzir o ensaio da cena» is drawn out while the screen waits, while «terminei» is in the air and with the microphone open',
    (tester) async {
      final (_, container) = await translateOnScreen(
        tester,
        rehearsal: _twoFrases,
      );
      expect(_lit(tester, _translate), isTrue);

      for (final refusal in [
        _Refusal.waiting,
        _Refusal.sending,
        _Refusal.microphone,
      ]) {
        await _under(
          tester,
          container,
          refusal,
          () => expect(
            _lit(tester, _translate),
            isFalse,
            reason:
                'com ${refusal.name}, o traduzir ficava aceso e o toque não '
                'fazia nada',
          ),
        );
      }
    },
  );

  testWidgets(
    'every control of the translate step stays lit while a frase\'s translation comes down, as hers, not dimmed',
    (tester) async {
      final (harness, _) = await _theLastFraseTranslatedAgain(tester);
      bool? circle() =>
          tester.widget<Semantics>(byLabel(_tell)).properties.enabled;
      final controls = [
        _playPause,
        _bar(1),
        _bar(2),
        _hearMine(2),
        _restart,
        _keepTheEarlier,
        _recordAgain,
      ];
      expect(circle(), isNot(isFalse));
      for (final control in controls) {
        expect(_lit(tester, control), isTrue, reason: control);
      }

      harness.room.holdNextClip();
      await tester.tap(byLabel(_hearMine(1)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        circle(),
        isNot(isFalse),
        reason: 'o círculo se apagava enquanto a tradução da frase descia',
      );
      for (final control in controls) {
        expect(
          _lit(tester, control),
          isTrue,
          reason:
              '«$control» se apagava enquanto a tradução da frase descia; '
              'no dela fica aceso',
        );
      }
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
