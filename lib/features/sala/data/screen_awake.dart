import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenAwake {
  Future<void> hold() => WakelockPlus.enable();

  Future<void> release() => WakelockPlus.disable();
}

final screenAwakeProvider = Provider<ScreenAwake>((ref) => ScreenAwake());
