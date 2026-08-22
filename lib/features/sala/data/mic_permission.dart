import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_repository.dart';

enum MicAccess { unknown, granted, denied }

class MicPermissionNotifier extends Notifier<MicAccess> {
  RecordingRepository get _recorder => ref.read(recordingRepositoryProvider);

  @override
  MicAccess build() => MicAccess.unknown;

  Future<MicAccess> check() async {
    // A question that could not be asked is not an answer of no. Sixty seconds without a
    // reply from the platform used to put the team on the microphone-denied screen.
    state = switch (await _recorder.hasPermission()) {
      true => MicAccess.granted,
      false => MicAccess.denied,
      null => MicAccess.unknown,
    };
    return state;
  }

  void refuse() => state = MicAccess.denied;
}

final micPermissionProvider = NotifierProvider<MicPermissionNotifier, MicAccess>(
  MicPermissionNotifier.new,
);
