import 'dart:math';
import 'dart:typed_data';

typedef Silence = ({Duration from, Duration to});

enum Nudge { earlier, later }

const _bin = Duration(milliseconds: 20);
const _floor = 0.08;
const _shortestSilence = Duration(milliseconds: 150);
const _back = Duration(milliseconds: 1500);
const _ahead = Duration(milliseconds: 250);
const _step = Duration(milliseconds: 400);
const _hair = Duration(milliseconds: 50);

class Envelope {
  final Duration length;
  final List<double> loudness;

  const Envelope(this.length, this.loudness);
}

Envelope? envelopeOf(Uint8List wav) {
  if (wav.length < 44) return null;
  final bytes = ByteData.sublistView(wav);
  String tag(int at) => String.fromCharCodes(wav, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  var format = 0, channels = 0, rate = 0, bits = 0;
  var at = 12;
  while (at + 8 <= wav.length) {
    final size = bytes.getUint32(at + 4, Endian.little);
    final body = at + 8;
    switch (tag(at)) {
      case 'fmt ':
        if (body + 16 > wav.length) return null;
        format = bytes.getUint16(body, Endian.little);
        channels = bytes.getUint16(body + 2, Endian.little);
        rate = bytes.getUint32(body + 4, Endian.little);
        bits = bytes.getUint16(body + 14, Endian.little);
      case 'data':
        if (format != 1 || bits != 16 || channels < 1 || rate <= 0) {
          return null;
        }
        return _loudness(
          bytes,
          body,
          min(size, wav.length - body) ~/ (2 * channels),
          channels,
          rate,
        );
    }
    at = body + size + (size & 1);
  }
  return null;
}

Envelope _loudness(
  ByteData bytes,
  int data,
  int frames,
  int channels,
  int rate,
) {
  final perBin = max(1, rate * _bin.inMicroseconds ~/ 1000000);
  final loudness = <double>[];
  for (var start = 0; start < frames; start += perBin) {
    final end = min(frames, start + perBin);
    var sum = 0.0;
    for (var frame = start; frame < end; frame++) {
      var mixed = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        mixed += bytes.getInt16(
          data + (frame * channels + channel) * 2,
          Endian.little,
        );
      }
      mixed /= channels * 32768;
      sum += mixed * mixed;
    }
    loudness.add(sqrt(sum / (end - start)));
  }
  return Envelope(Duration(microseconds: frames * 1000000 ~/ rate), loudness);
}

List<Silence> silencesIn(Envelope envelope) {
  final loudness = envelope.loudness;
  if (loudness.isEmpty) return const [];
  final sorted = [...loudness]..sort();
  final nearPeak = sorted[min(sorted.length - 1, sorted.length * 98 ~/ 100)];
  final quiet = nearPeak * _floor;
  final shortest = _shortestSilence.inMicroseconds ~/ _bin.inMicroseconds;
  final silences = <Silence>[];
  int? opened;
  void close(int end) {
    final start = opened;
    opened = null;
    if (start == null || end - start < shortest) return;
    silences.add((from: _bin * start, to: _bin * end));
  }

  for (var i = 0; i < loudness.length; i++) {
    if (loudness[i] < quiet) {
      opened ??= i;
    } else {
      close(i);
    }
  }
  close(loudness.length);
  return silences;
}

Duration _middle(Silence silence) =>
    silence.from + (silence.to - silence.from) ~/ 2;

Duration _clamp(Duration at, Duration lo, Duration hi) =>
    at < lo ? lo : (at > hi ? hi : at);

Duration placeThePause(
  Envelope envelope,
  Duration tap, {
  required Duration lo,
  required Duration hi,
}) {
  final from = _clamp(tap - _back, lo, hi);
  final to = _clamp(tap + _ahead, lo, hi);
  Silence? best;
  Duration? bestScore;
  for (final silence in silencesIn(envelope)) {
    if (silence.to < from || silence.from > to) continue;
    final score = tap >= silence.from && tap <= silence.to
        ? Duration.zero
        : tap > silence.to
        ? tap - silence.to
        : (silence.from - tap) * 2;
    if (bestScore == null ||
        score < bestScore ||
        (score == bestScore && silence.from > best!.from)) {
      best = silence;
      bestScore = score;
    }
  }
  if (best == null) return _clamp(tap, lo, hi);
  return _clamp(_middle(best), from, to);
}

Duration nudgeThePause(
  Envelope envelope,
  Duration at,
  Nudge direction, {
  required Duration lo,
  required Duration hi,
}) {
  final earlier = direction == Nudge.earlier;
  final reachable = silencesIn(envelope)
      .map(_middle)
      .where(
        (middle) => earlier
            ? middle < at - _hair && at - middle <= _back
            : middle > at + _hair && middle - at <= _back,
      );
  if (reachable.isNotEmpty) {
    return _clamp(earlier ? reachable.last : reachable.first, lo, hi);
  }
  return _clamp(earlier ? at - _step : at + _step, lo, hi);
}

({Duration lo, Duration hi})? pauseBounds(Duration cursor, Duration length) {
  final lo = cursor + const Duration(milliseconds: 200);
  final hi = length - const Duration(milliseconds: 100);
  return hi < lo ? null : (lo: lo, hi: hi);
}

Duration theMomentBefore(Duration pausa, Duration cursor) {
  final from = pausa - _back;
  return from > cursor ? from : cursor;
}
