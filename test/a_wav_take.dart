import 'dart:typed_data';

/// A rehearsal part as the ticket states it on disk: a 44-byte RIFF/WAVE header for PCM,
/// one channel, 16000 Hz, 16 bits, followed by a few samples.
Uint8List aWavTake() {
  const samples = [0, 1200, -1200, 3000, -3000, 0];
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 16000, Endian.little);
  bytes.setUint32(28, 16000 * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List aSpokenWav({
  Duration length = const Duration(seconds: 10),
  List<(Duration, Duration)> gaps = const [],
  int channels = 1,
  bool chunkBeforeData = false,
  bool silentThroughout = false,
}) {
  const rate = 16000;
  final frames = length.inMicroseconds * rate ~/ Duration.microsecondsPerSecond;
  final dataBytes = frames * channels * 2;
  final extra = chunkBeforeData ? 12 : 0;
  final bytes = ByteData(44 + extra + dataBytes);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + extra + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  var at = 36;
  if (chunkBeforeData) {
    ascii(at, 'LIST');
    bytes.setUint32(at + 4, 4, Endian.little);
    ascii(at + 8, 'INFO');
    at += 12;
  }
  ascii(at, 'data');
  bytes.setUint32(at + 4, dataBytes, Endian.little);
  at += 8;
  bool quiet(int frame) {
    final instant = Duration(microseconds: frame * 1000000 ~/ rate);
    return gaps.any((gap) => instant >= gap.$1 && instant < gap.$2);
  }

  for (var frame = 0; frame < frames; frame++) {
    final sample = silentThroughout || quiet(frame)
        ? 0
        : (frame.isEven ? 8000 : -8000);
    for (var channel = 0; channel < channels; channel++) {
      bytes.setInt16(at, sample, Endian.little);
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}
