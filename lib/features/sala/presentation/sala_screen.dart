import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_notifier.dart';
import '../domain/session_state.dart';
import 'widgets/autocheque_view.dart';
import 'widgets/colar_overlay.dart';
import 'widgets/conversa_view.dart';
import 'widgets/convite_view.dart';
import 'widgets/ensaio_view.dart';
import 'widgets/fim_view.dart';
import 'widgets/retro_view.dart';

class SalaScreen extends ConsumerWidget {
  const SalaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
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
              const Positioned.fill(child: _ColarLayer()),
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
      case SalaStage.autocheque:
        return const AutochequeView();
      case SalaStage.retro:
        return const RetroView();
      case SalaStage.fim:
        return const FimView();
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
