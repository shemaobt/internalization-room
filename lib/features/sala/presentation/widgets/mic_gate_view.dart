import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/facilitator_voice_service.dart';
import '../../data/mic_permission.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'facilitator_circle.dart';

class MicGateView extends ConsumerWidget {
  const MicGateView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: FacilitatorCircle(
        size: 196,
        voice: VoiceState.blocked,
        semanticLabel: 'A sala precisa do microfone para funcionar',
        onTap: () => unawaited(_askAgain(ref)),
      ),
    );
  }

  /// Ask the platform again, and if the answer changed, open the room properly.
  ///
  /// Checking alone was enough to swap the screen and not enough to start anything: the
  /// invite never beckoned, so a team that cannot read got a silent circle, and the
  /// once-per-book rule for the panorama was bypassed — the next touch minted a fresh
  /// panorama session and replayed the whole book overview.
  Future<void> _askAgain(WidgetRef ref) async {
    final access = await ref.read(micPermissionProvider.notifier).check();
    if (access == MicAccess.granted) {
      unawaited(ref.read(salaSessionProvider.notifier).openTheRoom());
      return;
    }
    unawaited(ref.read(facilitatorVoiceProvider).playAsset(micBlockedAsset));
  }
}
