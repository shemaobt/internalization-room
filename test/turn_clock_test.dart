import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/turn_clock.dart';

class _FakeStopwatch extends Fake implements Stopwatch {
  int elapsedMilliseconds = 0;
}

void main() {
  test(
    'a segment reads the elapsed time between two marks, not since the clock started',
    () {
      final stopwatch = _FakeStopwatch();
      final clock = TurnClock(stopwatch: stopwatch);

      stopwatch.elapsedMilliseconds = 500;
      clock.mark('stop');
      stopwatch.elapsedMilliseconds = 620;
      clock.mark('answer');

      expect(
        clock.clientTiming([('stop_to_answer', 'stop', 'answer')]),
        'stop_to_answer=120',
      );
    },
  );

  test(
    'a segment whose mark never landed is left out, not sent as a broken pair',
    () {
      final stopwatch = _FakeStopwatch();
      final clock = TurnClock(stopwatch: stopwatch);

      stopwatch.elapsedMilliseconds = 100;
      clock.mark('stop');
      stopwatch.elapsedMilliseconds = 220;
      clock.mark('answer');
      // 'recorder' never marked — the epoch changed before recorder.stop() resolved.

      expect(
        clock.clientTiming([
          ('recorder_stop', 'stop', 'recorder'),
          ('stop_to_answer', 'stop', 'answer'),
        ]),
        'stop_to_answer=120',
      );
    },
  );

  test('nothing to report comes back as null, not an empty string', () {
    final clock = TurnClock(stopwatch: _FakeStopwatch());

    expect(clock.clientTiming([('stop_to_answer', 'stop', 'answer')]), isNull);
  });
}
