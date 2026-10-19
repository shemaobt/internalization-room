import 'dart:typed_data';

/// A rehearsal part as the ticket states it on disk: a 44-byte RIFF/WAVE header for PCM,
/// one channel, 16000 Hz, 16 bits, followed by a few samples.
Uint8List aWavTake({
  List<int> samples = const [0, 1200, -1200, 3000, -3000, 0],
  int channels = 1,
  bool chunkBeforeData = false,
  int paddingBeforeData = 0,
}) {
  const rate = 16000;
  final dataBytes = samples.length * 2;
  final extra = chunkBeforeData ? 12 + paddingBeforeData : 0;
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
    bytes.setUint32(at + 4, 4 + paddingBeforeData, Endian.little);
    ascii(at + 8, 'INFO');
    at += 12 + paddingBeforeData;
  }
  ascii(at, 'data');
  bytes.setUint32(at + 4, dataBytes, Endian.little);
  at += 8;
  for (final sample in samples) {
    bytes.setInt16(at, sample, Endian.little);
    at += 2;
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
  bool quiet(int frame) {
    final instant = Duration(microseconds: frame * 1000000 ~/ rate);
    return gaps.any((gap) => instant >= gap.$1 && instant < gap.$2);
  }

  return aWavTake(
    samples: [
      for (var frame = 0; frame < frames; frame++)
        for (var channel = 0; channel < channels; channel++)
          silentThroughout || quiet(frame) ? 0 : (frame.isEven ? 8000 : -8000),
    ],
    channels: channels,
    chunkBeforeData: chunkBeforeData,
  );
}
