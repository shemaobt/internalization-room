import 'dart:typed_data';

typedef WavData = ({
  int format,
  int channels,
  int rate,
  int bits,
  int offset,
  int size,
});

const _wavHeader = 44;

WavData? wavDataOf(Uint8List wav) {
  if (wav.length < _wavHeader) return null;
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
        return (
          format: format,
          channels: channels,
          rate: rate,
          bits: bits,
          offset: body,
          size: size,
        );
    }
    at = body + size + (size & 1);
  }
  return null;
}

Duration? wavLengthOf(Uint8List wav) {
  final data = wavDataOf(wav);
  if (data == null ||
      data.format != 1 ||
      data.channels < 1 ||
      data.rate <= 0 ||
      data.bits < 8 ||
      data.size == 0 ||
      data.size == 0xFFFFFFFF) {
    return null;
  }
  final present = wav.length - data.offset;
  final bytes = data.size < present ? data.size : present;
  final perSecond = data.rate * data.channels * (data.bits ~/ 8);
  return Duration(
    microseconds: bytes * Duration.microsecondsPerSecond ~/ perSecond,
  );
}
