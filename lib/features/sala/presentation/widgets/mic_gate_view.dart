import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mic_permission.dart';
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
        onTap: () => ref.read(micPermissionProvider.notifier).check(),
      ),
    );
  }
}
