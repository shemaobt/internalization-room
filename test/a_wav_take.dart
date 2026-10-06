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
