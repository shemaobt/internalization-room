import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

const _guard = CaptureGuard(
  minDuration: Duration(milliseconds: 50),
  minBytes: 1,
);
const _longEnough = Duration(milliseconds: 90);

void main() {
  test(
    'a second tap inside the window cancels the capture, not a second miss',
    () async {
      final harness = SalaHarness(captureGuard: _guard);
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      harness.voice.assets.clear();
      harness.voice.fixedLines.clear();
      final callsBefore = harness.room.calls.length;

      await withClock(Clock.fixed(DateTime(2026, 10, 9)), () async {
        notifier.conversaTap();
        await settle();
        notifier.conversaTap();
        await settle();
      });

      expect(harness.voice.assets, isEmpty);
      expect(harness.voice.fixedLines, isEmpty);
      expect(harness.room.calls.length, callsBefore);
      expect(harness.recorder.sounds, contains('recorder:discard'));
      expect(container.read(salaSessionProvider).voice, VoiceState.invite);
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
