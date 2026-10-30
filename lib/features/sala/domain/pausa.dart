import 'dart:math';
import 'dart:typed_data';

import 'wav.dart';

typedef Silence = ({Duration from, Duration to});

enum Nudge { earlier, later }

const _binWidth = Duration(milliseconds: 20);
const _quietFraction = 0.08;
const _shortestSilence = Duration(milliseconds: 150);
const _nearPeakPercentile = 98;
const _shortestStretch = Duration(milliseconds: 200);
const _endMargin = Duration(milliseconds: 100);
const _shortestTail = Duration(milliseconds: 500);
const _lookBack = Duration(milliseconds: 1500);
const _lookAhead = Duration(milliseconds: 250);
const _nudgeStep = Duration(milliseconds: 400);
const _nudgeTolerance = Duration(milliseconds: 50);
const _atTheEnd = Duration(milliseconds: 50);

class Envelope {
  final Duration length;
  final List<double> loudness;

  const Envelope(this.length, this.loudness);
}

Envelope? envelopeOf(Uint8List wav) {
  final data = wavDataOf(wav);
  if (data == null ||
      data.format != 1 ||
      data.bits != 16 ||
      data.channels < 1 ||
      data.rate <= 0) {
    return null;
  }
  return _loudness(
    ByteData.sublistView(wav),
    data.offset,
    min(data.size, wav.length - data.offset) ~/ (2 * data.channels),
    data.channels,
    data.rate,
  );
}

Envelope _loudness(
  ByteData bytes,
  int data,
  int frames,
  int channels,
  int rate,
) {
  final perBin = max(1, rate * _binWidth.inMicroseconds ~/ 1000000);
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
  final nearPeak =
      sorted[min(
        sorted.length - 1,
        sorted.length * _nearPeakPercentile ~/ 100,
      )];
  final quiet = nearPeak * _quietFraction;
  final shortest = (_shortestSilence.inMicroseconds / _binWidth.inMicroseconds)
      .ceil();
  final silences = <Silence>[];
  int? opened;
  void close(int end) {
    final start = opened;
    opened = null;
    if (start == null || end - start < shortest) return;
    silences.add((from: _binWidth * start, to: _binWidth * end));
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
  final from = _clamp(tap - _lookBack, lo, hi);
  final to = _clamp(tap + _lookAhead, lo, hi);
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
            ? middle < at - _nudgeTolerance && at - middle <= _lookBack
            : middle > at + _nudgeTolerance && middle - at <= _lookBack,
      );
  if (reachable.isNotEmpty) {
    return _clamp(earlier ? reachable.last : reachable.first, lo, hi);
  }
  return _clamp(earlier ? at - _nudgeStep : at + _nudgeStep, lo, hi);
}

({Duration lo, Duration hi})? pauseBounds(Duration cursor, Duration length) {
  final lo = cursor + _shortestStretch;
  final hi = length - _endMargin;
  return hi < lo ? null : (lo: lo, hi: hi);
}

Duration? pauseAtTheTap(Duration tap, Duration cursor, Duration? length) {
  final floor = cursor + _shortestStretch;
  if (tap >= floor) return tap;
  if (length != null && length < floor) return null;
  return floor;
}

bool isAStub(Duration cursor, Duration end) => end - cursor < _shortestTail;

bool isAtTheEnd(Duration pausa, Duration end) => pausa >= end - _atTheEnd;

Duration theMomentBefore(Duration pausa, Duration cursor) {
  final from = pausa - _lookBack;
  return from > cursor ? from : cursor;
}
