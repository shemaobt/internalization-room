import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  minBytes: 1,
);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;
  final bool onThePanorama;

  _Room(this.harness, this.container, {this.onThePanorama = false});

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  Future<void> tap() async {
    if (onThePanorama) {
      notifier.panoramaTap();
    } else {
      notifier.conversaTap();
    }
    await settle();
  }
}

Future<void> _onAClock(
  Future<void> Function(void Function(Duration) later) body,
) async {
  var now = DateTime(2026, 10, 29);
  var step = const Duration(seconds: 1);
  await withClock(Clock(() => now = now.add(step)), () async {
    await body((by) {
      step = Duration.zero;
      now = now.add(by);
    });
  });
}

Future<_Room> _inConversa(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  return _Room(harness, container);
}

void main() {
  test('a recorder that answers half a second late still holds the take '
      'against a stop tap 0.4 s after it started', () async {
    await _onAClock((later) async {
      final room = await _inConversa(SalaHarness(captureGuard: _herGuard));
      final turns = room.harness.room.turnsSent;
      room.harness.recorder.holdNextStart();

      await room.tap();
      later(const Duration(milliseconds: 500));
      room.harness.recorder.finishStart();
      await settle();
      later(const Duration(milliseconds: 400));
      await room.tap();

      expect(
        room.state.voice,
        VoiceState.listening,
        reason:
            'a janela contava do toque, e o atraso do gravador já tinha '
            'gastado o tempo dela',
      );
      await settle();
      expect(room.harness.room.turnsSent, turns);

      later(const Duration(milliseconds: 400));
      await room.tap();
      await waitFor(
        'a vez chegar à sala',
        () => room.harness.room.turnsSent == turns + 1,
      );
    });
  });
}
