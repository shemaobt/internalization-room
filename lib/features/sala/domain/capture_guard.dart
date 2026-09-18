enum TapDecision { start, stop, ignore }

class CaptureGuard {
  const CaptureGuard({
    this.minDuration = const Duration(milliseconds: 1200),
    this.minBytes = 800,
  });

  final Duration minDuration;
  final int minBytes;

  TapDecision decide({required bool isRecording, required Duration elapsed}) {
    if (!isRecording) return TapDecision.start;
    return elapsed < minDuration ? TapDecision.ignore : TapDecision.stop;
  }

  bool accepts({required Duration duration, required int bytes}) =>
      duration >= minDuration && bytes >= minBytes;
}
