import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_link_notifier.dart';
import '../data/mic_permission.dart';
import '../data/screen_awake.dart';
import '../data/session_notifier.dart';
import '../data/store_build_gate.dart';
import '../domain/session_state.dart';
import '../dev/dev_skip_bar.dart';
import 'widgets/checagem_externa_view.dart';
import 'widgets/codigo_view.dart';
import 'widgets/colar_overlay.dart';
import 'widgets/conversa_view.dart';
import 'widgets/panorama_view.dart';
import 'widgets/ensaio_view.dart';
import 'widgets/escolha_view.dart';
import 'widgets/hand_button.dart';
import 'widgets/claquete.dart';
import 'widgets/hear_again_button.dart';
import 'widgets/back_to_passage_button.dart';
import 'widgets/language_and_look.dart';
import 'widgets/leave_passage_button.dart';
import 'widgets/person_sign.dart';
import 'widgets/retro_view.dart';
import 'widgets/scene_rehearsal_view.dart';
import 'widgets/update_view.dart';

class SalaScreen extends ConsumerStatefulWidget {
  /// Whether the build carries an address at all.
  final bool built;

  const SalaScreen({super.key, this.built = true});

  @override
  ConsumerState<SalaScreen> createState() => _SalaScreenState();
}

class _SalaScreenState extends ConsumerState<SalaScreen>
    with WidgetsBindingObserver {
  late final ScreenAwake _awake = ref.read(screenAwakeProvider);
  bool _roomOpened = false;
  Timer? _replyWatch;

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
      unawaited(ref.read(storeBuildGateProvider.notifier).look());
      unawaited(_findTheTeam());
    });
  }

  Future<void> _findTheTeam() async {
    await ref.read(deviceLinkProvider.notifier).findTheTeam();
    if (!mounted) return;
    await ref.read(salaSessionProvider.notifier).refreshUnsent();
  }

  /// The room the tablet was in belonged to the link the Desk just took back. Built
  /// afresh, the next link opens it the way a first launch does.
  void _closeTheRoom() {
    _roomOpened = false;
    _replyWatch?.cancel();
    ref.invalidate(salaSessionProvider);
  }

  @override
  void dispose() {
    _replyWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_awake.release());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused) {
      _replyWatch?.cancel();
    }
    if (lifecycle == AppLifecycleState.paused) {
      ref.read(salaSessionProvider.notifier).theAppWentAway();
    }
    if (lifecycle == AppLifecycleState.resumed &&
        ref.read(salaSessionProvider).stage == SalaStage.escolha) {
      unawaited(ref.read(storeBuildGateProvider.notifier).look());
    }
    if (lifecycle == AppLifecycleState.resumed &&
        ref.read(deviceLinkProvider).linked) {
      unawaited(_openRoom());
    }
  }

  void _watchForReplies() {
    _replyWatch?.cancel();
    _lookForReplies();
    _replyWatch = Timer.periodic(
      ref.read(roomInboxWatchProvider),
      (_) => _lookForReplies(),
    );
  }

  void _lookForReplies() =>
      ref.read(salaSessionProvider.notifier).lookForReplies();

  Future<void> _openRoom() async {
    _watchForReplies();
    await ref.read(micPermissionProvider.notifier).check();
    if (!mounted) return;
    unawaited(ref.read(salaSessionProvider.notifier).openTheRoom());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(salaSessionProvider);
    final link = ref.watch(deviceLinkProvider);
    ref.listen(deviceLinkProvider, (was, now) {
      if ((was?.linked ?? false) && !now.linked) _closeTheRoom();
    });
    ref.listen(salaSessionProvider.select((s) => s.stage), (was, now) {
      if (now == SalaStage.escolha && was != SalaStage.escolha) {
        unawaited(ref.read(storeBuildGateProvider.notifier).look());
      }
    });

    if (ref.watch(storeBuildGateProvider)) {
      return Scaffold(
        body: SafeArea(
          child: UpdateView(language: ref.watch(roomLanguageProvider)),
        ),
      );
    }

    if (!link.linked && widget.built) {
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_openRoom()),
      );
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
                layoutBuilder: _oneOfEachStage,
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
            const _HandLayer(),
            const HearAgainButton(),
            const ClaqueteLayer(),
            const LeavePassageButton(),
            if (!session.sceneRehearsalIsOpen) const BackToPassageButton(),
            const LanguageAndLook(),
            const PersonSign(),
            const DevSkipBar(),
          ],
        ),
      ),
    );
  }

  Widget _oneOfEachStage(Widget? current, List<Widget> fading) {
    final seen = <Key?>{};
    final kept = fading.reversed.where((view) => seen.add(view.key)).toList();
    return Stack(
      alignment: Alignment.center,
      children: [...kept.reversed, ?current],
    );
  }

  Widget _stageView(SalaStage stage) {
    switch (stage) {
      case SalaStage.panorama:
        return const PanoramaView();
      case SalaStage.escolha:
        return const EscolhaView();
      case SalaStage.conversa:
        return const ConversaView();
      case SalaStage.ensaio:
        return const EnsaioView();
      case SalaStage.retro:
        return const RetroView();
      case SalaStage.cena:
        return const SceneRehearsalView();
      case SalaStage.checagem:
        return const ChecagemExternaView();
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

/// The hand lives outside the switcher, so no second copy flashes up beside it while two
/// screens cross-fade.
class _HandLayer extends ConsumerWidget {
  const _HandLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final screen = MediaQuery.sizeOf(context);
    return Positioned(
      left: screen.width * 0.08 - 2,
      bottom:
          MediaQuery.viewPaddingOf(context).bottom + screen.height * 0.16 - 2,
      child: HandButton(
        visible: session.atTheTeamsIdleTurn || session.aQuestionRecords,
        noteMode: session.noteMode,
        hasUnheardReply: session.hasUnheardReply,
        playingReply: session.playingReplyId != null,
        language: ref.watch(roomLanguageProvider),
        onTap: notifier.handTap,
      ),
    );
  }
}
