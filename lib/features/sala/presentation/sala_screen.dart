import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_link_notifier.dart';
import '../data/mic_permission.dart';
import '../data/screen_awake.dart';
import '../data/session_notifier.dart';
import '../data/take_upload_queue.dart';
import '../domain/session_state.dart';
import '../dev/dev_skip_bar.dart';
import 'widgets/codigo_view.dart';
import 'widgets/colar_overlay.dart';
import 'widgets/conversa_view.dart';
import 'widgets/convite_view.dart';
import 'widgets/ensaio_view.dart';
import 'widgets/escolha_view.dart';
import 'widgets/hand_button.dart';
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
      ref.read(salaSessionProvider.notifier).sayTheMicIsBlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    final mic = ref.watch(micPermissionProvider);
    final link = ref.watch(deviceLinkProvider);

    if (!link.linked) {
      return Scaffold(
        body: SafeArea(
          child: CodigoView(
            code: link.code,
            language: ref.watch(roomLanguageProvider),
          ),
        ),
      );
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
                duration: const Duration(milliseconds: 1400),
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
            const _HandLayer(),
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

/// How often the cord asks the player where the sound is.
///
/// Ten times a second is what a bead crossing a whole rehearsal needs: finer redraws the
/// same pixel, coarser reads as a bead that jumps rather than one that walks.
const _passoDaCabeca = Duration(milliseconds: 100);

class _RetroCordLayer extends ConsumerStatefulWidget {
  const _RetroCordLayer();

  @override
  ConsumerState<_RetroCordLayer> createState() => _RetroCordLayerState();
}

/// The cord's reading head, kept here rather than in [SalaSessionState].
///
/// The head moves ten times a second and only this layer draws it. Carried in the session
/// it would rebuild every widget in the room at that rate — and the room watches the
/// session from everywhere. The asking dies with the layer, so nothing walks after the
/// team leaves the passage.
///
/// Out of a sound being played the head is where the room wrote it down: pausing, crossing
/// a boundary and picking a part back up all say where the team stopped hearing, and none
/// of them are guesses the player can be asked for.
class _RetroCordLayerState extends ConsumerState<_RetroCordLayer> {
  Timer? _asking;
  int _ouvidoMs = 0;

  @override
  void initState() {
    super.initState();
    final session = ref.read(salaSessionProvider);
    _ouvidoMs = session.btOuvidoMs;
    _followTheAudio(_soando(session));
  }

  static bool _soando(SalaSessionState session) =>
      session.btClipRodando || session.btTrechoTocando;

  @override
  void dispose() {
    _asking?.cancel();
    super.dispose();
  }

  void _followTheAudio(bool rodando) {
    _asking?.cancel();
    _asking = null;
    if (!rodando) return;
    _asking = Timer.periodic(_passoDaCabeca, (_) {
      final agora = ref.read(salaSessionProvider.notifier).ouvidoAgoraMs;
      if (agora != _ouvidoMs) setState(() => _ouvidoMs = agora);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    // The watch above already rebuilds this layer on any session change; what the select
    // adds is the edge — the one frame the clip starts or stops — which is when the
    // asking has to be started or put down.
    ref.listen<bool>(
      salaSessionProvider.select(_soando),
      (_, rodando) {
        // The part that starts is not the one that stopped, and the player still answers
        // for the old one until it has loaded the new. The room's own number is the one
        // that is right on this frame.
        if (rodando) _ouvidoMs = ref.read(salaSessionProvider).btOuvidoMs;
        _followTheAudio(rodando);
      },
    );
    return RetroCord(
      partes: session.partes.length,
      fimDasPartes: session.btFimDasPartesMs,
      parteNoArMs: session.btParteNoArMs,
      ouvidoMs: _soando(session) ? _ouvidoMs : session.btOuvidoMs,
      trechos: session.btTrechos,
      apontado: session.btEsperandoConserto,
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

/// The hand lives outside the switcher, so raising it once during the convite carries
/// through into the conversa without a second copy flashing up beside it while the two
/// screens cross-fade.
class _HandLayer extends ConsumerWidget {
  const _HandLayer();

  static const _inside = {SalaStage.convite, SalaStage.conversa};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!_inside.contains(session.stage)) return const SizedBox.shrink();
    final notifier = ref.read(salaSessionProvider.notifier);
    return Positioned(
      left: 14,
      bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
      child: HandButton(
        noteMode: session.noteMode,
        questionPending: session.questionPending,
        hasUnheardReply: session.hasUnheardReply,
        playingReply: session.playingReplyId != null,
        onTap: notifier.handTap,
      ),
    );
  }
}
