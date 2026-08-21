import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_repository.dart';

enum MicAccess { unknown, granted, denied }

class MicPermissionNotifier extends Notifier<MicAccess> {
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);

  @override
  MicAccess build() => MicAccess.unknown;

  Future<MicAccess> check() async {
    final granted = await _recorder.hasPermission();
    state = granted ? MicAccess.granted : MicAccess.denied;
    return state;
  }

  void refuse() => state = MicAccess.denied;
}

final micPermissionProvider = NotifierProvider<MicPermissionNotifier, MicAccess>(
  MicPermissionNotifier.new,
);
