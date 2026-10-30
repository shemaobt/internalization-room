import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _herGuard = CaptureGuard(
  minDuration: Duration(milliseconds: 700),
  minBytes: 800,
);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

Future<void> _onAFrozenClock(
  Future<void> Function(void Function(Duration) later) body,
) async {
  var now = DateTime(2026, 10, 30);
  await withClock(Clock(() => now), () => body((by) => now = now.add(by)));
}

void main() {
  test('a question of 0.4 s with 2 KB in it reaches the desk: the hand holds '
      'it to no window', () async {
    await _onAFrozenClock((later) async {
      final harness = SalaHarness(captureGuard: _herGuard)
        ..recorder.questionSpeaks = Uint8List(2048);
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.handTap();
      await settle();
      notifier.conversaTap();
      await settle();
      later(const Duration(milliseconds: 400));
      notifier.conversaTap();
      await waitFor(
        'a pergunta chegar à mesa',
        () => harness.inbox.questionsSent.isNotEmpty,
      );

      expect(
        harness.inbox.questionsSent,
        ['sessao-1'],
        reason:
            'uma pergunta curta de verdade era apagada por durar menos de '
            '0,7 s; a dela só cai abaixo de 800 bytes',
      );
    });
  });

  test('a question of 0.4 s with 2 KB in it raised on the Panorama reaches the '
      'desk too', () async {
    await _onAFrozenClock((later) async {
      final harness = SalaHarness(captureGuard: _herGuard)
        ..recorder.questionSpeaks = Uint8List(2048);
      harness.room.passages = [_panorama, ...harness.room.passages];
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState state() => container.read(salaSessionProvider);
      await enterThePanorama(notifier, state);
      await waitFor(
        'o panorama ser dito e a sala voltar ao convite',
        () => state().panoramaSaid && state().voice == VoiceState.invite,
      );

      notifier.handTap();
      await settle();
      notifier.panoramaTap();
      await settle();
      later(const Duration(milliseconds: 400));
      notifier.panoramaTap();
      await waitFor(
        'a pergunta do Panorama chegar à mesa',
        () => harness.inbox.questionsSent.isNotEmpty,
      );

      expect(
        harness.inbox.questionsSent,
        ['sessao-1'],
        reason:
            'a pergunta do Panorama passa pela mesma entrega da mão, e era '
            'apagada por durar menos de 0,7 s',
      );
    });
  });

  test('a question with under 800 bytes in it is thrown away unsent however '
      'long it ran, and its file goes with it', () async {
    await _onAFrozenClock((later) async {
      final harness = SalaHarness(captureGuard: _herGuard);
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.handTap();
      await settle();
      notifier.conversaTap();
      await settle();
      later(const Duration(seconds: 5));
      notifier.conversaTap();
      await waitFor(
        'o arquivo da pergunta ser apagado',
        () => harness.recorder.deleted.isNotEmpty,
      );

      expect(
        harness.inbox.questionsSent,
        isEmpty,
        reason: 'uma pergunta de 14 bytes é um toque, não uma pergunta',
      );
      expect(harness.recorder.deleted, [harness.recorder.lastPath]);
    });
  });
}
