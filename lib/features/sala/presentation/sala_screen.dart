import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/facilitator_voice_service.dart';
import '../data/mic_permission.dart';
import '../data/session_notifier.dart';
import '../data/take_upload_queue.dart';
import '../domain/facilitator_script.dart';
import '../domain/session_state.dart';
import 'widgets/colar_overlay.dart';
import 'widgets/conversa_view.dart';
import 'widgets/convite_view.dart';
import 'widgets/ensaio_view.dart';
import 'widgets/hear_again_button.dart';
import 'widgets/mic_gate_view.dart';
import 'widgets/retro_view.dart';

class SalaScreen extends ConsumerStatefulWidget {
  const SalaScreen({super.key});

  @override
  ConsumerState<SalaScreen> createState() => _SalaScreenState();
}

class _SalaScreenState extends ConsumerState<SalaScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(takeUploadQueueProvider).flush());
      unawaited(_openRoom());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) unawaited(_openRoom());
  }

  Future<void> _openRoom() async {
    final access = await ref.read(micPermissionProvider.notifier).check();
    if (!mounted) return;
    if (access == MicAccess.granted) {
      ref.read(salaSessionProvider.notifier).beckon();
    } else {
      unawaited(ref.read(facilitatorVoiceProvider).playAsset(micBlockedAsset));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    final mic = ref.watch(micPermissionProvider);

    if (mic == MicAccess.denied) {
      return const Scaffold(body: SafeArea(child: MicGateView()));
    }

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: KeyedSubtree(
                  key: ValueKey(session.stage),
                  child: _stageView(session.stage),
                ),
              ),
            ),
            if (session.colarOn)
              const Positioned.fill(
                child: SafeArea(bottom: false, child: _ColarLayer()),
              ),
            const HearAgainButton(),
          ],
        ),
      ),
    );
  }

  Widget _stageView(SalaStage stage) {
    switch (stage) {
      case SalaStage.convite:
        return const ConviteView();
      case SalaStage.conversa:
        return const ConversaView();
      case SalaStage.ensaio:
        return const EnsaioView();
      case SalaStage.retro:
        return const RetroView();
      case SalaStage.fim:
        return const SizedBox.expand();
    }
  }
}

class _ColarLayer extends ConsumerWidget {
  const _ColarLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    return ColarOverlay(session: session);
  }
}
