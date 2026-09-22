import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa, settle;

const _guard = CaptureGuard(
  minDuration: Duration(milliseconds: 50),
  minBytes: 1,
);
const _longEnough = Duration(milliseconds: 90);

Future<void> _miss(SalaSessionNotifier notifier) async {
  notifier.conversaTap();
  notifier.conversaTap();
  await settle();
}

void main() {
  test(
    'a second tap inside the window is ignored, not a second miss',
    () async {
      final harness = SalaHarness(captureGuard: _guard);
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      harness.voice.assets.clear();
      final callsBefore = harness.room.calls.length;

      await _miss(notifier);

      expect(
        harness.voice.assets,
        isEmpty,
        reason:
            'o toque de dentro da janela nunca chega a falar nada — a '
            'gravação continua, não é um take reprovado',
      );
      expect(
        harness.room.calls.length,
        callsBefore,
        reason: 'a gravação ainda está de pé; nada foi mandado para a sala',
      );
      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.listening,
        reason: 'o segundo toque foi ignorado, o primeiro continua valendo',
      );
      expect(container.read(salaSessionProvider).needsPerson, isFalse);
    },
  );

  test('a stop past the window still reaches the room, as before', () async {
    final harness = SalaHarness(captureGuard: _guard);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final turnsBefore = harness.room.turnsSent;

    notifier.conversaTap();
    await settle(_longEnough);
    notifier.conversaTap();
    await settle();

    expect(
      harness.room.turnsSent,
      turnsBefore + 1,
      reason: 'um toque depois da janela ainda encerra e sobe a tomada',
    );
  });
}
