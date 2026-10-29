import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'scenario_helpers.dart' show byLabel;

const _translate = 'traduzir o ensaio da cena';
const _keepTheEarlier = 'manter a tradução de antes';

String _bar(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

Duration _s(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

enum _Refusal { waiting, sending, microphone }

final _twoFrases = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: 'sessao-1',
  n: 1,
  frases: const [
    SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
    SceneFrase(fraseId: 'f2', startsMs: 4000, endsMs: 9000),
  ],
);

Future<ProviderContainer> _theLastFraseTranslatedAgain(
  WidgetTester tester,
) async {
  final (_, container) = await translateOnScreen(
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
  return container;
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
  };
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    '«manter a tradução de antes» is drawn out while the screen waits, while «terminei» is in the air and with the microphone open',
    (tester) async {
      final container = await _theLastFraseTranslatedAgain(tester);
      expect(_lit(tester, _keepTheEarlier), isTrue);

      for (final refusal in _Refusal.values) {
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
}
