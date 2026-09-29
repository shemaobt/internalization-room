import 'package:clock/clock.dart';

class TurnClock {
  TurnClock({Stopwatch? stopwatch})
    : _stopwatch = stopwatch ?? (clock.stopwatch()..start());

  final Stopwatch _stopwatch;
  final Map<String, int> _marks = {};

  void mark(String name) => _marks[name] = _stopwatch.elapsedMilliseconds;

  String? clientTiming(List<(String, String, String)> segments) {
    final parts = <String>[
      for (final (name, from, to) in segments)
        if (_marks[from] != null && _marks[to] != null)
          '$name=${_marks[to]! - _marks[from]!}',
    ];
    return parts.isEmpty ? null : parts.join(';');
  }
}
