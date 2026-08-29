import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_link_notifier.dart';
import '../data/facilitator_voice_service.dart';
import '../data/mic_permission.dart';
import '../data/screen_awake.dart';
import '../data/session_notifier.dart';
import '../data/take_upload_queue.dart';
import '../domain/facilitator_script.dart';
import '../domain/session_state.dart';
import '../dev/dev_skip_bar.dart';
import 'widgets/codigo_view.dart';
import 'widgets/colar_overlay.dart';
import 'widgets/conversa_view.dart';
import 'widgets/convite_view.dart';
import 'widgets/ensaio_view.dart';
import 'widgets/escolha_view.dart';
import 'widgets/hear_again_button.dart';
import 'widgets/leave_passage_button.dart';
import 'widgets/mic_gate_view.dart';
import 'widgets/retro_cord.dart';
import 'widgets/retro_view.dart';

class SalaScreen extends ConsumerStatefulWidget {
  /// Whether the build carries an address and a key at all.
  final bool built;

  const SalaScreen({super.key, this.built = true});

  @override
  ConsumerState<SalaScreen> createState() => _SalaScreenState();
}

class _SalaScreenState extends ConsumerState<SalaScreen> with WidgetsBindingObserver {
  late final ScreenAwake _awake = ref.read(screenAwakeProvider);
  bool _roomOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_awake.hold());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.built) {
        ref.read(salaSessionProvider.notifier).haltForABrokenBuild();
        return;
      }
      unawaited(
        ref
            .read(takeUploadQueueProvider)
            .flush()
            .then((_) => ref.read(salaSessionProvider.notifier).refreshUnsent()),
      );
      unawaited(ref.read(deviceLinkProvider.notifier).findTheTeam());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_awake.release());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed && ref.read(deviceLinkProvider).linked) {
      unawaited(_openRoom());
    }
  }

  Future<void> _openRoom() async {
    final access = await ref.read(micPermissionProvider.notifier).check();
    if (!mounted) return;
    if (access == MicAccess.granted) {
      unawaited(ref.read(salaSessionProvider.notifier).openTheRoom());
    } else {
      unawaited(ref.read(facilitatorVoiceProvider).playAsset(micBlockedAsset));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    final mic = ref.watch(micPermissionProvider);
    final link = ref.watch(deviceLinkProvider);

    if (!link.linked) {
      return Scaffold(body: SafeArea(child: CodigoView(code: link.code)));
    }

    if (link.linked && !_roomOpened) {
      _roomOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_openRoom()));
    }

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
              )
            else if (session.stage == SalaStage.retro)
              const Positioned.fill(
                child: SafeArea(bottom: false, child: _RetroCordLayer()),
              ),
            const HearAgainButton(),
            const LeavePassageButton(),
            const DevSkipBar(),
          ],
        ),
      ),
    );
  }

  Widget _stageView(SalaStage stage) {
    switch (stage) {
      case SalaStage.convite:
        return const ConviteView();
      case SalaStage.escolha:
        return const EscolhaView();
      case SalaStage.conversa:
        return const ConversaView();
      case SalaStage.ensaio:
        return const EnsaioView();
      case SalaStage.retro:
        return const RetroView();
      case SalaStage.fim:
        return const _FimView();
    }
  }
}

class _FimView extends ConsumerWidget {
  const _FimView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Começar de novo',
      child: GestureDetector(
        onTap: ref.read(salaSessionProvider.notifier).beginAgain,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RetroCordLayer extends ConsumerWidget {
  const _RetroCordLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    return RetroCord(
      partes: session.partes.length,
      fimDasPartes: session.btFimDasPartesMs,
      parteNoArMs: session.btParteNoArMs,
      ouvidoMs: session.btOuvidoMs,
      trechos: session.btTrechos,
      apontado: session.btFindingSegmentId,
    );
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
