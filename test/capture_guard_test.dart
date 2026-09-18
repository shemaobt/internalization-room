import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/capture_guard.dart';

void main() {
  test('a tap with nothing recording is always a start', () {
    const guard = CaptureGuard();

    expect(
      guard.decide(isRecording: false, elapsed: const Duration(seconds: 9)),
      TapDecision.start,
    );
  });

  test('a tap inside the window is ignored, never treated as a stop', () {
    const guard = CaptureGuard(minDuration: Duration(milliseconds: 1200));

    expect(
      guard.decide(
        isRecording: true,
        elapsed: const Duration(milliseconds: 1199),
      ),
      TapDecision.ignore,
    );
  });

  test('a tap once the window has passed stops the take', () {
    const guard = CaptureGuard(minDuration: Duration(milliseconds: 1200));

    expect(
      guard.decide(
        isRecording: true,
        elapsed: const Duration(milliseconds: 1200),
      ),
      TapDecision.stop,
    );
  });

  test('a take under the byte floor does not count, even held long enough', () {
    const guard = CaptureGuard(
      minDuration: Duration(milliseconds: 1200),
      minBytes: 800,
    );

    expect(
      guard.accepts(duration: const Duration(seconds: 2), bytes: 799),
      isFalse,
    );
  });

  test('a take under the duration floor does not count, even heavy enough', () {
    const guard = CaptureGuard(
      minDuration: Duration(milliseconds: 1200),
      minBytes: 800,
    );

    expect(
      guard.accepts(duration: const Duration(milliseconds: 1199), bytes: 5000),
      isFalse,
    );
  });

  test('a take past both floors counts', () {
    const guard = CaptureGuard(
      minDuration: Duration(milliseconds: 1200),
      minBytes: 800,
    );

    expect(
      guard.accepts(duration: const Duration(milliseconds: 1200), bytes: 800),
      isTrue,
    );
  });
}
