import 'dart:math';
import 'dart:typed_data';

import 'wav.dart';

const _shortestTake = Duration(milliseconds: 300);
const _smallestCompressedTake = 800;

/// Whether a take is a finger brushing the circle rather than something the team said,
/// read from the head of its file and the file's whole length.
bool isAnAccidentalTap({
  required bool wav,
  required Uint8List head,
  required int length,
}) {
  if (!wav) return length < _smallestCompressedTake;
  final data = wavDataOf(head);
  if (data == null || data.channels < 1 || data.rate <= 0 || data.bits < 8) {
    return true;
  }
  final perSecond = data.rate * data.channels * (data.bits ~/ 8);
  final audio = max(0, min(data.size, length - data.offset));
  return Duration(microseconds: audio * 1000000 ~/ perSecond) < _shortestTake;
}
