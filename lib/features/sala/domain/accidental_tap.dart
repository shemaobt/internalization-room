import 'dart:math';
import 'dart:typed_data';

import 'wav.dart';

const _shortestTake = Duration(milliseconds: 300);
const _smallestCompressedTake = 800;
const _roomWavHeader = 44;
const _roomWavBytesPerSecond = 16000 * 2;

bool isAnAccidentalTap({
  required bool wav,
  required Uint8List head,
  required int length,
}) {
  if (!wav) return length < _smallestCompressedTake;
  final data = wavDataOf(head);
  if (data == null) {
    return _shorterThanATake(length - _roomWavHeader, _roomWavBytesPerSecond);
  }
  if (data.channels < 1 || data.rate <= 0 || data.bits < 8) return true;
  final unfinished = data.size == 0 || data.size == 0xFFFFFFFF;
  return _shorterThanATake(
    unfinished ? length - data.offset : min(data.size, length - data.offset),
    data.rate * data.channels * (data.bits ~/ 8),
  );
}

bool _shorterThanATake(int audio, int perSecond) =>
    Duration(microseconds: max(0, audio) * 1000000 ~/ perSecond) <
    _shortestTake;
