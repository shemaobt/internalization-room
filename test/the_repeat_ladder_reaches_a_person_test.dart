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
  test('a second tap inside the window is ignored and the take goes on, never '
      'thrown away', () async {
    final harness = SalaHarness(captureGuard: _guard);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();
    harness.voice.fixedLines.clear();
    final callsBefore = harness.room.calls.length;
    final turnsBefore = harness.room.turnsSent;
    final soundsBefore = harness.recorder.sounds.length;

    var now = DateTime(2026, 10, 9);
    await withClock(Clock(() => now), () async {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();

      expect(harness.voice.assets, isEmpty);
      expect(harness.voice.fixedLines, isEmpty);
      expect(harness.room.calls.length, callsBefore);
      expect(
        harness.recorder.sounds.sublist(soundsBefore),
        isNot(contains('recorder:discard')),
        reason: 'o segundo toque rápido jogava a gravação fora em silêncio',
      );
      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.listening,
        reason: 'o círculo voltava a descansar com a equipe ainda falando',
      );
      expect(container.read(salaSessionProvider).needsPerson, isFalse);

      now = now.add(_longEnough);
      notifier.conversaTap();
      await settle();

      expect(
        harness.room.turnsSent,
        turnsBefore + 1,
        reason: 'a gravação que seguiu é a que o toque seguinte manda',
      );
    });
  });

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
