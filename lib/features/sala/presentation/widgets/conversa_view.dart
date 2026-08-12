import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';

class ConversaView extends ConsumerWidget {
  const ConversaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FacilitatorCircle(
                size: 158,
                voice: session.voice,
                azulMode: session.hand,
                showListenDot: session.showListenDot,
                semanticLabel: 'Segurar para falar',
                onHoldStart: notifier.conversaHoldStart,
                onHoldEnd: notifier.conversaHoldEnd,
                onHoldCancel: notifier.holdCancel,
              ),
              const SizedBox(height: 44),
              SizedBox(
                height: 64,
                child: session.conversaDone
                    ? AdvanceButton(
                        gradient: BeadStyles.verde,
                        semanticLabel: 'Ir para o ensaio',
                        onTap: notifier.goEnsaio,
                        child: const Icon(
                          LucideIcons.mic,
                          size: 26,
                          color: ShemaBrand.branco,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        Positioned(
          left: 22,
          bottom: 26,
          child: _HandButton(
            active: session.hand,
            colors: colors,
            onDown: notifier.handDown,
            onUp: notifier.handUp,
            onCancel: notifier.handCancel,
          ),
        ),
        if (session.handAck)
          Positioned(
            left: 0,
            right: 0,
            bottom: 110,
            child: Center(
              child: PingIn(
                child: Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: const BoxDecoration(
                      gradient: BeadStyles.azul,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HandButton extends StatelessWidget {
  final bool active;
  final SalaColors colors;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onCancel;

  const _HandButton({
    required this.active,
    required this.colors,
    required this.onDown,
    required this.onUp,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Levantar a mão',
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onCancel(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.card,
            border: Border.all(color: colors.line, width: 1.5),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ShemaBrand.azul.withValues(alpha: 0.35),
                      spreadRadius: 5,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            LucideIcons.hand,
            size: 26,
            color: active ? ShemaBrand.azulInk : colors.mut,
          ),
        ),
      ),
    );
  }
}
